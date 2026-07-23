package session

import (
	"bufio"
	"net"
	"testing"

	"github.com/dragoncoressh/udpgw-standalone/internal/protocol"
)

func TestReadPayloadFromPipe(t *testing.T) {
	clientConn, serverConn := net.Pipe()
	defer clientConn.Close()
	defer serverConn.Close()

	var ip [4]byte
	frame := protocol.BuildRequestFrame(1, 0, ip, 53, []byte{1, 2, 3})
	go func() {
		_, _ = clientConn.Write(frame)
	}()

	payload, err := protocol.ReadPayload(bufio.NewReader(serverConn), 1024)
	if err != nil {
		t.Fatal(err)
	}
	req, err := protocol.ParseRequest(payload)
	if err != nil {
		t.Fatal(err)
	}
	if req.ConnID != 1 || len(req.Data) != 3 {
		t.Fatalf("unexpected req: %+v", req)
	}
}
