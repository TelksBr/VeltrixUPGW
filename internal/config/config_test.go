package config

import (
	"testing"
	"time"
)

func TestResolveDefaults(t *testing.T) {
	c := Resolve(Raw{})
	if c.Listen != DefaultListen {
		t.Fatalf("listen = %q", c.Listen)
	}
	if c.MaxFrame != DefaultMaxFrame {
		t.Fatalf("maxFrame = %d", c.MaxFrame)
	}
	if c.MaxClients != DefaultMaxClients {
		t.Fatalf("maxClients = %d", c.MaxClients)
	}
	if c.WriteChan != WriteChanMax {
		t.Fatalf("writeChan = %d", c.WriteChan)
	}
	if c.MapTTL != DefaultMapTTL {
		t.Fatalf("mapTTL = %s", c.MapTTL)
	}
}

func TestResolveClampsWriteChan(t *testing.T) {
	c := Resolve(Raw{WriteChan: 99999})
	if c.WriteChan != WriteChanMax {
		t.Fatalf("writeChan = %d, want clamp %d", c.WriteChan, WriteChanMax)
	}
	c = Resolve(Raw{WriteChan: 32})
	if c.WriteChan != 32 {
		t.Fatalf("writeChan = %d", c.WriteChan)
	}
}

func TestValidate(t *testing.T) {
	c := Resolve(Raw{})
	if err := c.Validate(); err != nil {
		t.Fatal(err)
	}
	bad := c
	bad.UDPBindIP = "not-an-ip"
	if err := bad.Validate(); err == nil {
		t.Fatal("expected validation error")
	}
}

func TestAutoRestartInterval(t *testing.T) {
	c := Resolve(Raw{AutoRestartInterval: "24h"})
	if c.AutoRestartInterval != 24*time.Hour {
		t.Fatalf("interval = %s", c.AutoRestartInterval)
	}
	c = Resolve(Raw{AutoRestartInterval: "30s"})
	if c.AutoRestartInterval != 0 {
		t.Fatalf("expected disabled interval")
	}
}
