// Package sysstat measures how close this server is to its limits: the machine's cpu, memory, disk
// and load out of /proc, and the process's own database pool, search slots and go runtime. one
// goroutine takes a reading every Interval and the admin panel's «Система» reads the latest one.
//
// **nothing here is written anywhere.** the readings, the cpu history and the pool's wait count live
// in this process and start again at every restart, which StartedAt is there to say.
package sysstat

import (
	"log"
	"runtime"
	"runtime/debug"
	"runtime/metrics"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	// the panel's own refresh tick, so every poll can show a reading it has not shown before. it is
	// also what cpu% is averaged over.
	Interval = 5 * time.Second

	History    = time.Hour
	historyLen = int(History / Interval)
)

type Config struct {
	// nil leaves the pool figures at zero, which is what the endpoint tests build
	Pool *pgxpool.Pool
	// Home.SearchSlots: its length is how many searches hold a slot now
	SearchSlots chan struct{}
	// any path on the volume the photos are written to
	DiskPath string
}

type CPU struct {
	// busy and stolen, as a share of the last Interval. steal is the hypervisor running another tenant
	// while this one wanted the core - the part of a slowdown no setting on this box can fix.
	Percent, StealPercent float64
}

type Memory struct {
	Total, Available, SwapTotal, SwapFree uint64
}

type Disk struct {
	Total, Free uint64
}

type Load struct {
	One, Five, Fifteen float64
}

type Pool struct {
	Acquired, Max int32

	// pgx's EmptyAcquireCount as it stands: every acquire that found no idle connection, including
	// the ordinary ones that simply opened a new one. see BusyWaits.
	EmptyAcquires int64

	// acquires that waited because every connection was in use - the pool was full, not merely cold.
	// FirstBusyWait is the moment this process first saw one.
	BusyWaits                   int64
	FirstBusyWait, LastBusyWait time.Time
}

type Snapshot struct {
	At, StartedAt time.Time

	// nil where the host cannot be read; CPU is also nil until the second reading exists
	CPU    *CPU
	Memory *Memory
	Disk   *Disk
	Load   *Load
	Cores  int

	// cpu percent per Interval over the last History, oldest first
	CPUHistory []float64

	Pool                        Pool
	SearchInUse, SearchCapacity int

	Goroutines int
	// HeapBytes is the live heap; RuntimeBytes is everything the go runtime has mapped from the os
	HeapBytes, RuntimeBytes uint64
}

type hostReading struct {
	cpu    *cpuTimes
	cores  int
	memory *Memory
	disk   *Disk
	load   *Load
	err    error
}

// what busyWaits is computed from
type poolCounters struct {
	empty, newConns int64
	constructing    int32
}

type Sampler struct {
	cfg     Config
	started time.Time

	// touched only by the sampling goroutine
	prevCPU  *cpuTimes
	prevPool poolCounters
	hostErr  string
	runtime  []metrics.Sample

	mu      sync.Mutex
	latest  Snapshot
	history []float64
}

// New takes the first reading, which everything after it is measured against. Run takes the rest.
func New(cfg Config) *Sampler {
	s := &Sampler{
		cfg:     cfg,
		started: time.Now(),
		history: make([]float64, 0, historyLen),
		runtime: []metrics.Sample{
			{Name: "/memory/classes/heap/objects:bytes"},
			{Name: "/memory/classes/total:bytes"},
		},
	}
	s.sample()
	return s
}

// Run samples every Interval until the process exits.
func (s *Sampler) Run() {
	ticker := time.NewTicker(Interval)
	defer ticker.Stop()
	for range ticker.C {
		s.sample()
	}
}

// Snapshot is the latest reading, with its own copy of the history.
func (s *Sampler) Snapshot() Snapshot {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := s.latest
	out.CPUHistory = append([]float64(nil), s.history...)
	return out
}

func (s *Sampler) sample() {
	// an unrecovered panic in a goroutine takes the whole process with it, api included
	defer func() {
		if problem := recover(); problem != nil {
			log.Printf("CRITICAL: panic sampling system readings: %v\n%s", problem, debug.Stack())
		}
	}()

	now := time.Now()
	snap := Snapshot{At: now, StartedAt: s.started}

	host := readHost(s.cfg.DiskPath)
	s.noteHostError(host.err)
	snap.Memory, snap.Disk, snap.Load, snap.Cores = host.memory, host.disk, host.load, host.cores

	var cpu *CPU
	if host.cpu != nil {
		if s.prevCPU != nil {
			if busy, steal, ok := cpuBetween(*s.prevCPU, *host.cpu); ok {
				cpu = &CPU{Percent: busy, StealPercent: steal}
			}
		}
		s.prevCPU = host.cpu
	}
	snap.CPU = cpu

	if s.cfg.SearchSlots != nil {
		snap.SearchInUse, snap.SearchCapacity = len(s.cfg.SearchSlots), cap(s.cfg.SearchSlots)
	}

	snap.Goroutines = runtime.NumGoroutine()
	metrics.Read(s.runtime)
	snap.HeapBytes, snap.RuntimeBytes = s.runtime[0].Value.Uint64(), s.runtime[1].Value.Uint64()

	s.mu.Lock()
	defer s.mu.Unlock()

	snap.Pool = s.latest.Pool
	if s.cfg.Pool != nil {
		s.readPool(&snap.Pool, now)
	}

	if cpu != nil {
		if len(s.history) == historyLen {
			copy(s.history, s.history[1:])
			s.history = s.history[:historyLen-1]
		}
		s.history = append(s.history, cpu.Percent)
	}
	s.latest = snap
}

// readPool carries the running wait count forward into p. the first reading is the baseline and
// counts nothing: the boot's own Ping and the MinConns it opened are not waits.
func (s *Sampler) readPool(p *Pool, now time.Time) {
	// **NewConnsCount is read from a Stat taken before the one whose counters it explains.** pgx
	// counts a connection when its constructor starts and the empty acquire when it finishes; read in
	// the other order, a connection opened between the two calls is an acquire with nothing to
	// explain it, and the panel reports a full pool that never was.
	newConns := s.cfg.Pool.Stat().NewConnsCount()
	stat := s.cfg.Pool.Stat()
	counters := poolCounters{empty: stat.EmptyAcquireCount(), newConns: newConns, constructing: stat.ConstructingConns()}

	if !s.latest.At.IsZero() {
		if waits := busyWaits(s.prevPool, counters); waits > 0 {
			p.BusyWaits += waits
			if p.FirstBusyWait.IsZero() {
				p.FirstBusyWait = now
			}
			p.LastBusyWait = now
		}
	}
	s.prevPool = counters

	p.Acquired, p.Max, p.EmptyAcquires = stat.AcquiredConns(), stat.MaxConns(), counters.empty
}

// busyWaits is how many of the interval's empty acquires waited for a connection to be released:
// every one was in use.
//
// **pgx's EmptyAcquireCount alone is not that number.** It also counts an acquire that found no idle
// connection and opened one while the pool had room, which an idle box does whenever three requests
// arrive together after MaxConnIdleTime has shrunk it to MinConns. Read raw, its first non-zero value
// is a quiet afternoon. Every connection that finished opening in the interval was counted in
// newConns during it or was constructing at its start, so subtracting both errs towards silence,
// never towards a false alarm.
func busyWaits(before, after poolCounters) int64 {
	explained := (after.newConns - before.newConns) + int64(before.constructing)
	return max(0, (after.empty-before.empty)-explained)
}

// logged when what is failing changes, not every Interval
func (s *Sampler) noteHostError(err error) {
	msg := ""
	if err != nil {
		msg = err.Error()
	}
	if msg == s.hostErr {
		return
	}
	if msg == "" {
		log.Printf("System readings: the host is readable again")
	} else {
		log.Printf("WARNING: system readings incomplete: %s", msg)
	}
	s.hostErr = msg
}
