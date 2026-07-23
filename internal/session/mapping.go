package session

import (
	"time"

	"github.com/dragoncoressh/udpgw-standalone/internal/config"
)

// DestKey identifies a destination IPv4:port for reply routing.
type DestKey struct {
	IP   [4]byte
	Port uint16
}

type mapVal struct {
	ConnID uint16
	X      byte
	Exp    time.Time
}

// DestMap tracks destination-to-session mappings and connID activity.
type DestMap struct {
	cfg            config.Config
	now            func() time.Time
	destToConn     map[DestKey]mapVal
	connIDLastSeen map[uint16]time.Time
}

// NewDestMap creates a destination map. now defaults to time.Now when nil.
func NewDestMap(cfg config.Config, now func() time.Time) *DestMap {
	if now == nil {
		now = time.Now
	}
	return &DestMap{
		cfg:            cfg,
		now:            now,
		destToConn:     make(map[DestKey]mapVal),
		connIDLastSeen: make(map[uint16]time.Time),
	}
}

// Size returns the number of destination mappings.
func (m *DestMap) Size() int {
	return len(m.destToConn)
}

// Reap removes expired entries (called periodically).
func (m *DestMap) Reap() {
	now := m.now()
	for k, v := range m.destToConn {
		if now.After(v.Exp) {
			delete(m.destToConn, k)
		}
	}
	for id, lastSeen := range m.connIDLastSeen {
		if now.Sub(lastSeen) > m.cfg.MapTTL {
			delete(m.connIDLastSeen, id)
		}
	}
}

// Lookup returns routing info for a reply from key, or false if missing/expired.
func (m *DestMap) Lookup(key DestKey) (connID uint16, x byte, ok bool) {
	v, ok := m.destToConn[key]
	if !ok || m.now().After(v.Exp) {
		return 0, 0, false
	}
	return v.ConnID, v.X, true
}

// Update records a new outbound datagram and returns the destination key.
func (m *DestMap) Update(connID uint16, x byte, dstIP [4]byte, dstPort uint16) DestKey {
	key := DestKey{IP: dstIP, Port: dstPort}
	now := m.now()

	for id, lastSeen := range m.connIDLastSeen {
		if now.Sub(lastSeen) > m.cfg.MapTTL {
			delete(m.connIDLastSeen, id)
		}
	}

	if _, known := m.connIDLastSeen[connID]; !known && m.cfg.MaxClientConns > 0 && len(m.connIDLastSeen) >= m.cfg.MaxClientConns {
		var oldestID uint16
		var oldestTime time.Time
		first := true
		for id, lastSeen := range m.connIDLastSeen {
			if first || lastSeen.Before(oldestTime) {
				oldestID = id
				oldestTime = lastSeen
				first = false
			}
		}
		delete(m.connIDLastSeen, oldestID)
	}
	m.connIDLastSeen[connID] = now

	if m.cfg.MaxMapEntries > 0 && len(m.destToConn) >= m.cfg.MaxMapEntries {
		for dk, dv := range m.destToConn {
			if now.After(dv.Exp) {
				delete(m.destToConn, dk)
			}
		}
		if len(m.destToConn) >= m.cfg.MaxMapEntries {
			evict := (len(m.destToConn) - m.cfg.MaxMapEntries) + 1
			for dk := range m.destToConn {
				delete(m.destToConn, dk)
				evict--
				if evict <= 0 {
					break
				}
			}
		}
	}

	m.destToConn[key] = mapVal{
		ConnID: connID,
		X:      x,
		Exp:    now.Add(m.cfg.MapTTL),
	}
	return key
}
