package server

import (
	"testing"
	"time"

	"github.com/dragoncoressh/udpgw-standalone/internal/config"
	"github.com/dragoncoressh/udpgw-standalone/internal/metrics"
)

func TestServerStartStop(t *testing.T) {
	cfg := config.Resolve(config.Raw{
		Listen:        "127.0.0.1:0",
		MaxClients:    10,
		MetricsListen: "127.0.0.1:0",
	})
	// Use ephemeral metrics port by resolving after start would fail validation;
	// disable metrics for this test.
	cfg.MetricsListen = ""

	m := metrics.New()
	srv := New(cfg, m)
	if err := srv.Start(); err != nil {
		t.Fatal(err)
	}
	if !srv.Running() {
		t.Fatal("expected running")
	}
	time.Sleep(50 * time.Millisecond)
	srv.Stop()
	if srv.Running() {
		t.Fatal("expected stopped")
	}
}
