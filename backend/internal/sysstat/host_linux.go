package sysstat

import (
	"errors"
	"fmt"
	"os"
	"syscall"
)

// readHost reads the machine. three small files and one statfs: nothing here walks a directory.
// each figure that fails is nil and its error joined, so one unreadable file blanks one card.
func readHost(diskPath string) hostReading {
	var h hostReading
	var errs []error

	if stat, err := os.ReadFile("/proc/stat"); err != nil {
		errs = append(errs, err)
	} else if times, cores, err := parseCPU(string(stat)); err != nil {
		errs = append(errs, err)
	} else {
		h.cpu, h.cores = &times, cores
	}

	if meminfo, err := os.ReadFile("/proc/meminfo"); err != nil {
		errs = append(errs, err)
	} else if m, err := parseMeminfo(string(meminfo)); err != nil {
		errs = append(errs, err)
	} else {
		h.memory = &m
	}

	if loadavg, err := os.ReadFile("/proc/loadavg"); err != nil {
		errs = append(errs, err)
	} else if l, err := parseLoadavg(string(loadavg)); err != nil {
		errs = append(errs, err)
	} else {
		h.load = &l
	}

	var fs syscall.Statfs_t
	if err := syscall.Statfs(diskPath, &fs); err != nil {
		errs = append(errs, fmt.Errorf("sysstat: statfs %s: %w", diskPath, err))
	} else {
		// Bavail, not Bfree: the api runs as an unprivileged user and cannot write into the blocks
		// ext4 reserves for root
		h.disk = &Disk{Total: fs.Blocks * uint64(fs.Bsize), Free: fs.Bavail * uint64(fs.Bsize)}
	}

	h.err = errors.Join(errs...)
	return h
}
