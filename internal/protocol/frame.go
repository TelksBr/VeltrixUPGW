// Package protocol implements the BadVPN udpgw wire format.
//
// The protocol is IPv4-only: outbound requests carry a 4-byte destination
// address and reply frames embed a 4-byte source address. IPv6 replies are
// not representable in this framing.
package protocol

import (
	"bufio"
	"encoding/binary"
	"fmt"
	"io"
)

const (
	// MinPayloadLen is the minimum request/reply payload size:
	// connID(2) + x(1) + ipv4(4) + port(2).
	MinPayloadLen = 2 + 1 + 4 + 2

	// MaxUDPDatagram is the largest UDP payload we read from the kernel.
	MaxUDPDatagram = 65535
)

// Request holds a parsed client-to-server udpgw payload.
type Request struct {
	ConnID uint16
	X      byte
	DstIP  [4]byte
	DstPort uint16
	Data   []byte
}

// ParseRequest parses payload bytes after ReadPayload.
func ParseRequest(payload []byte) (Request, error) {
	if len(payload) < MinPayloadLen {
		return Request{}, fmt.Errorf("udpgw: payload too short: %d", len(payload))
	}
	var req Request
	req.ConnID = binary.BigEndian.Uint16(payload[0:2])
	req.X = payload[2]
	copy(req.DstIP[:], payload[3:7])
	req.DstPort = binary.BigEndian.Uint16(payload[7:9])
	req.Data = payload[9:]
	return req, nil
}

// ReadPayload reads a length-prefixed payload from r. The length prefix is
// little-endian uint16. Payloads larger than max cause an error.
func ReadPayload(r *bufio.Reader, max int) ([]byte, error) {
	var lenBuf [2]byte
	if _, err := io.ReadFull(r, lenBuf[:]); err != nil {
		return nil, err
	}
	n := int(binary.LittleEndian.Uint16(lenBuf[:]))
	if n <= 0 || n > max {
		return nil, fmt.Errorf("udpgw: invalid frame length %d", n)
	}
	b := make([]byte, n)
	if _, err := io.ReadFull(r, b); err != nil {
		return nil, err
	}
	return b, nil
}

// BuildFrame constructs a reply frame: little-endian length prefix, then
// connID (big endian), x byte, source IPv4, source port, and data.
func BuildFrame(connID uint16, x byte, ip [4]byte, port uint16, data []byte) []byte {
	payloadLen := MinPayloadLen + len(data)
	out := make([]byte, 2+payloadLen)
	binary.LittleEndian.PutUint16(out[0:2], uint16(payloadLen))
	binary.BigEndian.PutUint16(out[2:4], connID)
	out[4] = x
	copy(out[5:9], ip[:])
	binary.BigEndian.PutUint16(out[9:11], port)
	copy(out[11:], data)
	return out
}

// BuildRequestFrame builds a client request frame (same layout as reply).
func BuildRequestFrame(connID uint16, x byte, ip [4]byte, port uint16, data []byte) []byte {
	return BuildFrame(connID, x, ip, port, data)
}
