package config

import (
	"fmt"
	"log/slog"
	"net"
	"strings"
	"time"
)

const (
	DefaultListen      = "0.0.0.0:7400"
	SocketBufferMax    = 512 * 1024
	WriteChanMax       = 1024
	DefaultMaxClients  = 10000
	DefaultMaxFrame    = 64 * 1024
	MinMaxFrame        = 512
	DefaultMapTTL      = 90 * time.Second
	DefaultReapEvery   = 10 * time.Second
	DefaultIdleTimeout = 2 * time.Minute
)

// Raw holds CLI / file configuration before normalization.
type Raw struct {
	Listen              string
	MaxFrame            int
	Debug               bool
	WriteChan           int
	UDPBindIP           string
	UDPRBuf             int
	UDPWBuf             int
	MapTTL              string
	ReapEvery           string
	IdleTimeout         string
	MaxClientConns      int
	MaxMapEntries       int
	MaxClients          int
	AutoRestartInterval string
	AutoRestartGrace    string
	MetricsListen       string
}

// Config is the resolved runtime configuration.
type Config struct {
	Listen              string
	MaxFrame            int
	Debug               bool
	WriteChan           int
	UDPBindIP           string
	UDPRBuf             int
	UDPWBuf             int
	MapTTL              time.Duration
	ReapEvery           time.Duration
	IdleTimeout         time.Duration
	MaxClientConns      int
	MaxMapEntries       int
	MaxClients          int
	AutoRestartInterval time.Duration
	AutoRestartGrace    time.Duration
	MetricsListen       string
}

// Resolve applies defaults, clamps, and parses durations from raw input.
func Resolve(raw Raw) Config {
	c := Config{
		Listen:         raw.Listen,
		MaxFrame:       raw.MaxFrame,
		Debug:          raw.Debug,
		WriteChan:      raw.WriteChan,
		UDPBindIP:      raw.UDPBindIP,
		UDPRBuf:        raw.UDPRBuf,
		UDPWBuf:        raw.UDPWBuf,
		MaxClientConns: raw.MaxClientConns,
		MaxMapEntries:  raw.MaxMapEntries,
		MaxClients:     raw.MaxClients,
		MetricsListen:  raw.MetricsListen,
	}

	if strings.TrimSpace(c.Listen) == "" {
		c.Listen = DefaultListen
	}
	if c.MaxFrame <= 0 {
		c.MaxFrame = DefaultMaxFrame
	}
	if c.MaxFrame < MinMaxFrame {
		c.MaxFrame = MinMaxFrame
	}

	c.WriteChan = WriteChanMax
	if raw.WriteChan > 0 && raw.WriteChan < WriteChanMax {
		c.WriteChan = raw.WriteChan
	}

	c.UDPRBuf = SocketBufferMax
	if raw.UDPRBuf > 0 && raw.UDPRBuf < SocketBufferMax {
		c.UDPRBuf = raw.UDPRBuf
	}
	c.UDPWBuf = SocketBufferMax
	if raw.UDPWBuf > 0 && raw.UDPWBuf < SocketBufferMax {
		c.UDPWBuf = raw.UDPWBuf
	}

	c.MapTTL = parseDuration(raw.MapTTL, DefaultMapTTL, "map_ttl")
	c.ReapEvery = parseDuration(raw.ReapEvery, DefaultReapEvery, "reap_every")
	c.IdleTimeout = parseDuration(raw.IdleTimeout, DefaultIdleTimeout, "idle_timeout")

	if c.MaxClientConns <= 0 {
		c.MaxClientConns = 10
	}
	if c.MaxMapEntries <= 0 {
		c.MaxMapEntries = 32768
	}
	if c.MaxClients <= 0 {
		c.MaxClients = DefaultMaxClients
	}

	c.AutoRestartInterval = parseAutoRestartInterval(raw.AutoRestartInterval)
	c.AutoRestartGrace = parseAutoRestartGrace(raw.AutoRestartGrace)

	if strings.TrimSpace(c.MetricsListen) == "" {
		c.MetricsListen = "127.0.0.1:9091"
	}

	return c
}

func parseDuration(raw string, def time.Duration, name string) time.Duration {
	if strings.TrimSpace(raw) == "" {
		return def
	}
	d, err := time.ParseDuration(strings.TrimSpace(raw))
	if err != nil {
		slog.Warn("invalid duration, using default", "field", name, "value", raw, "default", def, "err", err)
		return def
	}
	if d <= 0 {
		slog.Warn("non-positive duration, using default", "field", name, "value", raw, "default", def)
		return def
	}
	return d
}

func parseAutoRestartInterval(raw string) time.Duration {
	raw = strings.TrimSpace(raw)
	if raw == "" || raw == "0" || raw == "0s" || strings.EqualFold(raw, "off") || strings.EqualFold(raw, "disabled") {
		return 0
	}
	d, err := time.ParseDuration(raw)
	if err != nil {
		slog.Warn("auto restart disabled: invalid interval", "value", raw, "err", err)
		return 0
	}
	if d < time.Minute {
		slog.Warn("auto restart disabled: interval below minimum", "value", raw, "min", time.Minute)
		return 0
	}
	return d
}

func parseAutoRestartGrace(raw string) time.Duration {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return 2 * time.Second
	}
	d, err := time.ParseDuration(raw)
	if err != nil || d < 0 {
		slog.Warn("auto restart: invalid grace, using 2s", "value", raw)
		return 2 * time.Second
	}
	if d > time.Minute {
		return time.Minute
	}
	return d
}

// Validate returns an error for clearly invalid configuration.
func (c Config) Validate() error {
	if c.MaxFrame < MinMaxFrame {
		return fmt.Errorf("max_frame must be >= %d", MinMaxFrame)
	}
	if c.MaxClients <= 0 {
		return fmt.Errorf("max_clients must be > 0")
	}
	if c.ReapEvery <= 0 {
		return fmt.Errorf("reap_every must be > 0")
	}
	if c.MapTTL <= 0 {
		return fmt.Errorf("map_ttl must be > 0")
	}
	if c.UDPBindIP != "" && net.ParseIP(c.UDPBindIP) == nil {
		return fmt.Errorf("invalid udp_bind IP %q", c.UDPBindIP)
	}
	if c.MetricsListen != "" {
		if _, err := net.ResolveTCPAddr("tcp", c.MetricsListen); err != nil {
			return fmt.Errorf("invalid metrics_listen %q: %w", c.MetricsListen, err)
		}
	}
	return nil
}
