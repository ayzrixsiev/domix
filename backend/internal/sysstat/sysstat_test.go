package sysstat

import (
	"math"
	"testing"
)

// a box up for days at about 5% whose last five seconds were flat out. a single read of /proc/stat
// gives the uptime average, which looks like a plausible number and says nothing about now.
func TestCPUIsTheIntervalBetweenTwoReadingsNotTheAverageSinceBoot(t *testing.T) {
	before := "cpu  50000 0 0 950000 0 0 0 0 0 0\ncpu0 25000 0 0 475000 0 0 0 0 0 0\ncpu1 25000 0 0 475000 0 0 0 0 0 0\n"
	after := "cpu  50900 0 100 950000 0 0 0 0 0 0\ncpu0 25450 0 50 475000 0 0 0 0 0 0\ncpu1 25450 0 50 475000 0 0 0 0 0 0\n"

	a, cores, err := parseCPU(before)
	if err != nil {
		t.Fatal(err)
	}
	if cores != 2 {
		t.Errorf("cores = %d, want 2", cores)
	}
	b, _, err := parseCPU(after)
	if err != nil {
		t.Fatal(err)
	}

	busy, _, ok := cpuBetween(a, b)
	if !ok || math.Abs(busy-100) > 0.001 {
		t.Fatalf("busy = %v (ok %v), want 100: the interval, not the %v%% since boot", busy, ok,
			float64(b.busy)/float64(b.total)*100)
	}
}

// steal and iowait are not this box's work: steal is another tenant on the host, iowait is a core idle
// while a disk answers. busy counts neither, and steal has its own figure.
func TestStealAndIowaitAreNotBusy(t *testing.T) {
	a, _, _ := parseCPU("cpu  0 0 0 0 0 0 0 0 0 0\n")
	b, _, _ := parseCPU("cpu  100 0 0 200 50 0 0 50 0 0\n")

	busy, steal, ok := cpuBetween(a, b)
	if !ok || math.Abs(busy-25) > 0.001 || math.Abs(steal-12.5) > 0.001 {
		t.Fatalf("busy %v steal %v (ok %v), want 25 and 12.5", busy, steal, ok)
	}
}

func TestMemoryInUseLeavesThePageCacheOut(t *testing.T) {
	m, err := parseMeminfo("MemTotal:  4000000 kB\nMemFree:  200000 kB\nMemAvailable:  3000000 kB\n" +
		"SwapTotal:  0 kB\nSwapFree:  0 kB\n")
	if err != nil {
		t.Fatal(err)
	}
	if used := m.Total - m.Available; used != 1000000*1024 {
		t.Fatalf("used = %d, want MemTotal - MemAvailable: MemFree would call the page cache used", used)
	}
}

// the number the panel presents as "the pool ran out": a connection being opened is not one
func TestOnlyAWaitForABusyConnectionCountsAsTheFullPool(t *testing.T) {
	cases := []struct {
		name          string
		before, after poolCounters
		want          int64
	}{
		{"three acquires opened three connections", poolCounters{}, poolCounters{empty: 3, newConns: 3}, 0},
		{"two waited with nothing being opened", poolCounters{empty: 5, newConns: 4}, poolCounters{empty: 7, newConns: 4}, 2},
		{"a connection already opening finished this interval",
			poolCounters{empty: 5, newConns: 4, constructing: 1}, poolCounters{empty: 6, newConns: 4}, 0},
		{"a background connection opened with no acquire", poolCounters{}, poolCounters{newConns: 2}, 0},
	}
	for _, c := range cases {
		if got := busyWaits(c.before, c.after); got != c.want {
			t.Errorf("%s: %d, want %d", c.name, got, c.want)
		}
	}
}
