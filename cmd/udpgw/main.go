package main

import (
	"flag"
	"fmt"
	"log"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"github.com/dragoncoressh/udpgw-standalone/internal/config"
	"github.com/dragoncoressh/udpgw-standalone/internal/metrics"
	"github.com/dragoncoressh/udpgw-standalone/internal/server"
)

// version is set at build time via -ldflags "-X main.version=...".
var version = "dev"

func main() {
	showVersion := flag.Bool("version", false, "print version and exit")
	listen := flag.String("listen", "", "TCP listen address (default 0.0.0.0:7400)")
	debug := flag.Bool("debug", false, "enable debug logging")
	maxFrame := flag.Int("max-frame", 0, "max frame size (bytes)")
	writeChan := flag.Int("write-chan", 0, "write channel size")
	udpBind := flag.String("udp-bind", "", "UDP bind IP for per-client sockets")
	udpRbuf := flag.Int("udp-rbuf", 0, "UDP socket read buffer bytes")
	udpWbuf := flag.Int("udp-wbuf", 0, "UDP socket write buffer bytes")
	mapTTL := flag.String("map-ttl", "", "map TTL duration (e.g. 90s)")
	reapEvery := flag.String("reap-every", "", "reap interval (e.g. 10s)")
	idleTimeout := flag.String("idle-timeout", "", "idle timeout (e.g. 2m)")
	maxClientConns := flag.Int("max-client-conns", 0, "max logical connIDs per client")
	maxMapEntries := flag.Int("max-map-entries", 0, "max mapping entries per client")
	maxClients := flag.Int("max-clients", 0, "max concurrent TCP clients")
	autoInterval := flag.String("auto-restart-interval", "", "auto restart interval (e.g. 24h)")
	autoGrace := flag.String("auto-restart-grace", "", "auto restart grace (e.g. 2s)")
	metricsListen := flag.String("metrics-listen", "", "Prometheus metrics listen address (default 127.0.0.1:9091)")
	flag.Parse()

	if *showVersion {
		fmt.Println(version)
		return
	}

	level := slog.LevelInfo
	if *debug {
		level = slog.LevelDebug
	}
	slog.SetDefault(slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: level})))

	raw := config.Raw{
		Listen:              *listen,
		MaxFrame:            *maxFrame,
		Debug:               *debug,
		WriteChan:           *writeChan,
		UDPBindIP:           *udpBind,
		UDPRBuf:             *udpRbuf,
		UDPWBuf:             *udpWbuf,
		MapTTL:              *mapTTL,
		ReapEvery:           *reapEvery,
		IdleTimeout:         *idleTimeout,
		MaxClientConns:      *maxClientConns,
		MaxMapEntries:       *maxMapEntries,
		MaxClients:          *maxClients,
		AutoRestartInterval: *autoInterval,
		AutoRestartGrace:    *autoGrace,
		MetricsListen:       *metricsListen,
	}
	cfg := config.Resolve(raw)
	if err := cfg.Validate(); err != nil {
		log.Fatalf("invalid config: %v", err)
	}

	m := metrics.New()
	srv := server.New(cfg, m)
	if err := srv.Start(); err != nil {
		log.Fatalf("failed to start udpgw: %v", err)
	}
	slog.Info("udpgw started", "listen", cfg.Listen, "metrics", cfg.MetricsListen)

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	<-sig
	slog.Info("shutting down")
	srv.Stop()
}
