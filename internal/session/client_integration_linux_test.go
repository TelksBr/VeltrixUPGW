//go:build linux

package session

import (
	"context"
	"encoding/binary"
	"io"
	"net"
	"testing"
	"time"

	"github.com/dragoncoressh/udpgw-standalone/internal/config"
	"github.com/dragoncoressh/udpgw-standalone/internal/protocol"
)

func TestClientUDPRoundTrip(t *testing.T) {
	echoConn, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 0})
	if err != nil {
		t.Fatal(err)
	}
	defer echoConn.Close()
	echoAddr := echoConn.LocalAddr().(*net.UDPAddr)

	echoDone := make(chan struct{})
	go func() {
		defer close(echoDone)
		buf := make([]byte, 1500)
		for {
			n, from, err := echoConn.ReadFromUDP(buf)
			if err != nil {
				return
			}
			_, _ = echoConn.WriteToUDP(buf[:n], from)
		}
	}()

	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()

	cfg := config.Resolve(config.Raw{
		Debug:      true,
		MaxFrame:   4096,
		MapTTL:     "30s",
		ReapEvery:  "5s",
		WriteChan:  16,
		MaxClients: 10,
		UDPBindIP:  "127.0.0.1",
	})

	clientCtx, clientCancel := context.WithCancel(context.Background())
	defer clientCancel()

	accepted := make(chan net.Conn, 1)
	go func() {
		conn, err := ln.Accept()
		if err != nil {
			return
		}
		accepted <- conn
		client := &Client{
			Conn: conn,
			Cfg:  cfg,
			SafeGo: func(_ string, fn func()) {
				go fn()
			},
		}
		_ = client.Run(clientCtx)
	}()

	tcpConn, err := net.Dial("tcp", ln.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer tcpConn.Close()

	serverConn := <-accepted

	var dstIP [4]byte
	copy(dstIP[:], echoAddr.IP.To4())
	frame := protocol.BuildRequestFrame(99, 0x07, dstIP, uint16(echoAddr.Port), []byte("ping"))
	if _, err := tcpConn.Write(frame); err != nil {
		t.Fatal(err)
	}

	reply := readOneFrame(t, tcpConn, 5*time.Second)
	connID := binary.BigEndian.Uint16(reply[0:2])
	if connID != 99 {
		t.Fatalf("connID = %d", connID)
	}
	if reply[2] != 0x07 {
		t.Fatalf("x = 0x%02x", reply[2])
	}
	gotData := reply[protocol.MinPayloadLen:]
	if string(gotData) != "ping" {
		t.Fatalf("data = %q", gotData)
	}

	clientCancel()
	_ = serverConn.Close()
	_ = tcpConn.Close()
	echoConn.Close()
	<-echoDone
}

func readOneFrame(t *testing.T, r io.Reader, timeout time.Duration) []byte {
	t.Helper()
	deadline := time.Now().Add(timeout)
	var lenBuf [2]byte
	for time.Now().Before(deadline) {
		if conn, ok := r.(net.Conn); ok {
			_ = conn.SetReadDeadline(time.Now().Add(500 * time.Millisecond))
		}
		if _, err := io.ReadFull(r, lenBuf[:]); err != nil {
			continue
		}
		n := int(binary.LittleEndian.Uint16(lenBuf[:]))
		payload := make([]byte, n)
		if _, err := io.ReadFull(r, payload); err != nil {
			t.Fatal(err)
		}
		return payload
	}
	t.Fatal("timeout waiting for reply frame")
	return nil
}
