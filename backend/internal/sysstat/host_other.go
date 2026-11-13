//go:build !linux

package sysstat

import "errors"

// the host figures come from /proc, which only linux has. a laptop on another system still runs the
// api; the panel shows those cards empty.
func readHost(string) hostReading {
	return hostReading{err: errors.New("sysstat: host readings need linux's /proc")}
}
