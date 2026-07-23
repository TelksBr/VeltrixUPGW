package session

import (
	"testing"
	"time"

	"github.com/dragoncoressh/udpgw-standalone/internal/config"
)

func TestDestMapUpdateLookup(t *testing.T) {
	now := time.Date(2026, 1, 1, 12, 0, 0, 0, time.UTC)
	m := NewDestMap(config.Config{
		MapTTL:         time.Minute,
		MaxClientConns: 10,
		MaxMapEntries:  100,
	}, func() time.Time { return now })

	var ip [4]byte
	copy(ip[:], []byte{8, 8, 8, 8})
	key := m.Update(1, 0x02, ip, 53)
	connID, x, ok := m.Lookup(key)
	if !ok || connID != 1 || x != 0x02 {
		t.Fatalf("lookup failed: ok=%v connID=%d x=%d", ok, connID, x)
	}
}

func TestDestMapExpired(t *testing.T) {
	start := time.Date(2026, 1, 1, 12, 0, 0, 0, time.UTC)
	current := start
	m := NewDestMap(config.Config{MapTTL: time.Second}, func() time.Time { return current })

	var ip [4]byte
	copy(ip[:], []byte{1, 1, 1, 1})
	key := m.Update(5, 0, ip, 1234)

	current = start.Add(2 * time.Second)
	if _, _, ok := m.Lookup(key); ok {
		t.Fatal("expected expired mapping")
	}
}

func TestDestMapConnIDCap(t *testing.T) {
	now := time.Now()
	m := NewDestMap(config.Config{
		MapTTL:         time.Hour,
		MaxClientConns: 2,
		MaxMapEntries:  100,
	}, func() time.Time { return now })

	var ip [4]byte
	m.Update(1, 0, ip, 1)
	m.Update(2, 0, ip, 2)
	m.Update(3, 0, ip, 3)

	if len(m.connIDLastSeen) > 2 {
		t.Fatalf("connID map size = %d, want <= 2", len(m.connIDLastSeen))
	}
}

func TestDestMapReap(t *testing.T) {
	start := time.Date(2026, 1, 1, 12, 0, 0, 0, time.UTC)
	current := start
	m := NewDestMap(config.Config{MapTTL: time.Minute}, func() time.Time { return current })

	var ip [4]byte
	m.Update(1, 0, ip, 80)
	current = start.Add(2 * time.Minute)
	m.Reap()
	if m.Size() != 0 {
		t.Fatalf("expected empty map after reap, size=%d", m.Size())
	}
}
