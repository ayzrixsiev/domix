package endpoints

import (
	"bufio"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// the slowloris guard: a caller that sends valid headers and then dribbles the body must be cut off
// rather than holding a handler open forever. a real socket, because httptest's recorder has no
// deadline to set and would pass whether the line is there or not.
func TestASlowBodyIsCutOffRatherThanHeldOpen(t *testing.T) {
	restore := bodyReadTimeout
	bodyReadTimeout = 100 * time.Millisecond
	t.Cleanup(func() { bodyReadTimeout = restore })

	done := make(chan struct{})
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer close(done)
		var body struct {
			Phone string `json:"phone"`
		}
		decodeJSONBody(w, r, &body)
	}))
	defer server.Close()

	conn, err := net.Dial("tcp", server.Listener.Addr().String())
	if err != nil {
		t.Fatalf("dialling the test server: %v", err)
	}
	defer conn.Close()

	// a body we promise and never finish sending
	const promised = 4096
	fmt.Fprintf(conn, "POST / HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n{", promised)

	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("the handler is still reading a body that stopped arriving: the read deadline is gone")
	}

	// and the caller is told, rather than left waiting on a socket nobody reads
	conn.SetReadDeadline(time.Now().Add(5 * time.Second))
	if _, err := bufio.NewReader(conn).ReadString('\n'); err != nil {
		t.Fatalf("no response line after the body was cut off: %v", err)
	}
}
