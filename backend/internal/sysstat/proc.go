package sysstat

import (
	"bufio"
	"fmt"
	"strconv"
	"strings"
)

// cpuTimes is the aggregate `cpu` line of /proc/stat, in jiffies since boot. one reading of it is
// an average over the machine's whole uptime; only the difference between two means anything.
type cpuTimes struct {
	busy, steal, total uint64
}

// parseCPU reads the aggregate line and counts the per-core ones.
func parseCPU(stat string) (cpuTimes, int, error) {
	var times cpuTimes
	found, cores := false, 0

	scanner := bufio.NewScanner(strings.NewReader(stat))
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) == 0 || !strings.HasPrefix(fields[0], "cpu") {
			continue
		}
		if fields[0] != "cpu" {
			cores++
			continue
		}
		// user nice system idle iowait irq softirq steal, then guest and guest_nice, which the kernel
		// has already counted inside user and nice
		if len(fields) < 9 {
			return cpuTimes{}, 0, fmt.Errorf("sysstat: /proc/stat cpu line has %d fields", len(fields))
		}
		var v [8]uint64
		for i := range v {
			n, err := strconv.ParseUint(fields[i+1], 10, 64)
			if err != nil {
				return cpuTimes{}, 0, fmt.Errorf("sysstat: /proc/stat cpu field %d: %w", i+1, err)
			}
			v[i] = n
		}
		idle, iowait, steal := v[3], v[4], v[7]
		for _, n := range v {
			times.total += n
		}
		// steal is kept out of busy: it is time the hypervisor gave to another tenant, not work done here
		times.busy = times.total - idle - iowait - steal
		times.steal = steal
		found = true
	}
	if err := scanner.Err(); err != nil {
		return cpuTimes{}, 0, err
	}
	if !found {
		return cpuTimes{}, 0, fmt.Errorf("sysstat: /proc/stat has no aggregate cpu line")
	}
	return times, cores, nil
}

// cpuBetween is the share of the interval between two readings spent busy, and stolen, in percent.
// false when no time passed between them, which a counter going backwards would also look like.
func cpuBetween(before, after cpuTimes) (busy, steal float64, ok bool) {
	if after.total <= before.total || after.busy < before.busy || after.steal < before.steal {
		return 0, 0, false
	}
	elapsed := float64(after.total - before.total)
	return float64(after.busy-before.busy) / elapsed * 100, float64(after.steal-before.steal) / elapsed * 100, true
}

// parseMeminfo reads /proc/meminfo, whose figures are in kibibytes.
//
// **used is MemTotal minus MemAvailable, never minus MemFree**: linux fills idle memory with page
// cache it gives back on demand, so a box at rest reads 95% "used" by MemFree and nobody can tell
// a healthy server from one about to be killed.
func parseMeminfo(meminfo string) (Memory, error) {
	var m Memory
	want := map[string]*uint64{
		"MemTotal:": &m.Total, "MemAvailable:": &m.Available,
		"SwapTotal:": &m.SwapTotal, "SwapFree:": &m.SwapFree,
	}

	seen := 0
	scanner := bufio.NewScanner(strings.NewReader(meminfo))
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) < 2 {
			continue
		}
		target, ok := want[fields[0]]
		if !ok {
			continue
		}
		kib, err := strconv.ParseUint(fields[1], 10, 64)
		if err != nil {
			return Memory{}, fmt.Errorf("sysstat: /proc/meminfo %s %w", fields[0], err)
		}
		*target = kib * 1024
		seen++
	}
	if err := scanner.Err(); err != nil {
		return Memory{}, err
	}
	if seen != len(want) {
		return Memory{}, fmt.Errorf("sysstat: /proc/meminfo is missing one of MemTotal, MemAvailable, SwapTotal, SwapFree")
	}
	return m, nil
}

// parseLoadavg reads the first three fields of /proc/loadavg.
func parseLoadavg(loadavg string) (Load, error) {
	fields := strings.Fields(loadavg)
	if len(fields) < 3 {
		return Load{}, fmt.Errorf("sysstat: /proc/loadavg has %d fields", len(fields))
	}
	var v [3]float64
	for i := range v {
		n, err := strconv.ParseFloat(fields[i], 64)
		if err != nil {
			return Load{}, fmt.Errorf("sysstat: /proc/loadavg field %d: %w", i, err)
		}
		v[i] = n
	}
	return Load{One: v[0], Five: v[1], Fifteen: v[2]}, nil
}
