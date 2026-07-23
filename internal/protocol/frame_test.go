package protocol

import (
	"bufio"
	"bytes"
	"encoding/binary"
	"io"
	"testing"
)

func TestBuildFrameRoundTrip(t *testing.T) {
	var ip [4]byte
	copy(ip[:], []byte{10, 0, 0, 1})
	data := []byte("hello")
	frame := BuildFrame(42, 0xAB, ip, 8080, data)

	payloadLen := int(binary.LittleEndian.Uint16(frame[0:2]))
	if payloadLen != MinPayloadLen+len(data) {
		t.Fatalf("payload len = %d, want %d", payloadLen, MinPayloadLen+len(data))
	}
	if got := binary.BigEndian.Uint16(frame[2:4]); got != 42 {
		t.Fatalf("connID = %d", got)
	}
	if frame[4] != 0xAB {
		t.Fatalf("x = 0x%02x", frame[4])
	}
	if !bytes.Equal(frame[5:9], ip[:]) {
		t.Fatalf("ip mismatch")
	}
	if got := binary.BigEndian.Uint16(frame[9:11]); got != 8080 {
		t.Fatalf("port = %d", got)
	}
	if !bytes.Equal(frame[11:], data) {
		t.Fatalf("data mismatch")
	}
}

func TestParseRequest(t *testing.T) {
	var ip [4]byte
	copy(ip[:], []byte{192, 168, 1, 1})
	frame := BuildRequestFrame(1, 0x01, ip, 53, []byte{0xAA})
	payload := frame[2:]
	req, err := ParseRequest(payload)
	if err != nil {
		t.Fatal(err)
	}
	if req.ConnID != 1 || req.X != 0x01 || req.DstPort != 53 || len(req.Data) != 1 {
		t.Fatalf("unexpected request: %+v", req)
	}
}

func TestReadPayloadValid(t *testing.T) {
	var ip [4]byte
	payload := BuildRequestFrame(7, 0, ip, 1234, []byte("x"))[2:]
	var buf bytes.Buffer
	binary.Write(&buf, binary.LittleEndian, uint16(len(payload)))
	buf.Write(payload)

	got, err := ReadPayload(bufio.NewReader(&buf), 1024)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, payload) {
		t.Fatalf("payload mismatch")
	}
}

func TestReadPayloadInvalidLength(t *testing.T) {
	tests := []struct {
		name string
		ln   uint16
	}{
		{"zero", 0},
		{"too_large", 9999},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			var buf bytes.Buffer
			binary.Write(&buf, binary.LittleEndian, tc.ln)
			_, err := ReadPayload(bufio.NewReader(&buf), 64)
			if err == nil {
				t.Fatal("expected error")
			}
		})
	}
}

func TestReadPayloadEOF(t *testing.T) {
	_, err := ReadPayload(bufio.NewReader(bytes.NewReader(nil)), 64)
	if err != io.EOF {
		t.Fatalf("got %v, want EOF", err)
	}
}

func FuzzReadPayload(f *testing.F) {
	f.Add([]byte{0x05, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05})
	f.Fuzz(func(t *testing.T, input []byte) {
		r := bufio.NewReader(bytes.NewReader(input))
		_, _ = ReadPayload(r, 256)
	})
}
