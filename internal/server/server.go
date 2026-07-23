package server

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"sync"
	"time"

	"github.com/dragoncoressh/udpgw-standalone/internal/config"
	"github.com/dragoncoressh/udpgw-standalone/internal/metrics"
	"github.com/dragoncoressh/udpgw-standalone/internal/session"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// Server manages the UDP gateway listener and client lifecycle.
type Server struct {
	cfg     config.Config
	metrics *metrics.Metrics

	mu              sync.Mutex
	ln              net.Listener
	clients         map[net.Conn]struct{}
	clientLimit     int
	clientsRejected int64
	running         bool

	rootCtx    context.Context
	rootCancel context.CancelFunc
	autoCancel context.CancelFunc
	wg         sync.WaitGroup

	metricsSrv *http.Server
}

// New creates a server. metrics may be nil to disable instrumentation.
func New(cfg config.Config, m *metrics.Metrics) *Server {
	return &Server{
		cfg:     cfg,
		metrics: m,
		clients: make(map[net.Conn]struct{}),
	}
}

// Start binds the TCP listener and begins accepting clients.
func (s *Server) Start() error {
	if err := s.cfg.Validate(); err != nil {
		return err
	}

	s.mu.Lock()
	if s.running {
		s.mu.Unlock()
		return fmt.Errorf("udpgw: already running")
	}
	s.rootCtx, s.rootCancel = context.WithCancel(context.Background())
	s.mu.Unlock()

	if err := s.startListener(); err != nil {
		s.stopLocked()
		return err
	}
	s.startMetrics()
	s.startAutoRestart()
	return nil
}

// Stop shuts down the listener, metrics endpoint, clients, and auto-restart.
func (s *Server) Stop() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.stopLocked()
}

func (s *Server) stopLocked() {
	if s.autoCancel != nil {
		s.autoCancel()
		s.autoCancel = nil
	}
	if s.metricsSrv != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		_ = s.metricsSrv.Shutdown(ctx)
		cancel()
		s.metricsSrv = nil
	}
	if s.ln != nil {
		_ = s.ln.Close()
		s.ln = nil
	}
	for conn := range s.clients {
		_ = conn.Close()
		delete(s.clients, conn)
	}
	if s.metrics != nil {
		s.metrics.ActiveClients.Set(0)
	}
	s.running = false
	if s.rootCancel != nil {
		s.rootCancel()
		s.rootCancel = nil
	}
	s.wg.Wait()
}

// Running reports whether the listener is active.
func (s *Server) Running() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.running
}

func (s *Server) startListener() error {
	ln, err := net.Listen("tcp", s.cfg.Listen)
	if err != nil {
		return fmt.Errorf("udpgw: listen failed on %s: %w", s.cfg.Listen, err)
	}

	s.mu.Lock()
	if s.ln != nil {
		_ = s.ln.Close()
	}
	s.ln = ln
	s.clientLimit = s.cfg.MaxClients
	s.running = true
	s.mu.Unlock()

	if s.cfg.Debug {
		slog.Info("listening", "addr", s.cfg.Listen)
	}

	s.wg.Add(1)
	safeGo(s, "accept-loop", func() {
		defer s.wg.Done()
		s.acceptLoop(ln)
	})
	return nil
}

func (s *Server) acceptLoop(ln net.Listener) {
	for {
		conn, err := ln.Accept()
		if err != nil {
			if errors.Is(err, net.ErrClosed) {
				return
			}
			slog.Warn("accept error", "err", err)
			continue
		}
		if !s.registerClient(conn) {
			continue
		}
		clientConn := conn
		safeGo(s, "client-handler", func() {
			defer s.unregisterClient(clientConn)
			client := &session.Client{
				Conn:    clientConn,
				Cfg:     s.cfg,
				Metrics: s.metrics,
				SafeGo: func(name string, fn func()) {
					safeGo(s, name, fn)
				},
			}
			_ = client.Run(s.rootCtx)
		})
	}
}

func (s *Server) registerClient(conn net.Conn) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.ln == nil {
		_ = conn.Close()
		return false
	}
	if s.clientLimit > 0 && len(s.clients) >= s.clientLimit {
		s.clientsRejected++
		rejected := s.clientsRejected
		_ = conn.Close()
		if s.metrics != nil {
			s.metrics.ClientsRejected.Inc()
		}
		if rejected == 1 || rejected%1000 == 0 {
			slog.Warn("client cap reached", "limit", s.clientLimit, "rejected", rejected)
		}
		return false
	}
	s.clients[conn] = struct{}{}
	if s.metrics != nil {
		s.metrics.ClientsTotal.Inc()
		s.metrics.ActiveClients.Set(float64(len(s.clients)))
	}
	return true
}

func (s *Server) unregisterClient(conn net.Conn) {
	s.mu.Lock()
	delete(s.clients, conn)
	if s.metrics != nil {
		s.metrics.ActiveClients.Set(float64(len(s.clients)))
	}
	s.mu.Unlock()
}

func (s *Server) stopInstance() {
	s.mu.Lock()
	if s.ln != nil {
		_ = s.ln.Close()
		s.ln = nil
	}
	for conn := range s.clients {
		_ = conn.Close()
		delete(s.clients, conn)
	}
	if s.metrics != nil {
		s.metrics.ActiveClients.Set(0)
	}
	s.mu.Unlock()
}

func (s *Server) startMetrics() {
	if s.cfg.MetricsListen == "" {
		return
	}
	mux := http.NewServeMux()
	mux.Handle("/metrics", promhttp.HandlerFor(s.metrics.Registry(), promhttp.HandlerOpts{}))
	s.metricsSrv = &http.Server{
		Addr:    s.cfg.MetricsListen,
		Handler: mux,
	}
	s.wg.Add(1)
	safeGo(s, "metrics-server", func() {
		defer s.wg.Done()
		slog.Info("metrics listening", "addr", s.cfg.MetricsListen)
		if err := s.metricsSrv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			slog.Error("metrics server error", "err", err)
		}
	})
}

func (s *Server) startAutoRestart() {
	if s.cfg.AutoRestartInterval <= 0 {
		return
	}
	ctx, cancel := context.WithCancel(s.rootCtx)
	s.autoCancel = cancel

	s.wg.Add(1)
	safeGo(s, "auto-restart", func() {
		defer s.wg.Done()
		t := time.NewTicker(s.cfg.AutoRestartInterval)
		defer t.Stop()
		slog.Info("auto restart enabled",
			"interval", s.cfg.AutoRestartInterval,
			"grace", s.cfg.AutoRestartGrace,
			"mode", "hard",
		)
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				slog.Info("auto restart: stopping listener and clients")
				s.stopInstance()
				if !sleepOrContextDone(ctx, s.cfg.AutoRestartGrace) {
					return
				}
				for attempt := 1; ; attempt++ {
					if err := s.startListener(); err != nil {
						slog.Error("auto restart start failed", "attempt", attempt, "err", err)
						if !sleepOrContextDone(ctx, 10*time.Second) {
							return
						}
						continue
					}
					slog.Info("auto restart: listener restarted")
					break
				}
			}
		}
	})
}

func sleepOrContextDone(ctx context.Context, d time.Duration) bool {
	if d <= 0 {
		select {
		case <-ctx.Done():
			return false
		default:
			return true
		}
	}
	select {
	case <-ctx.Done():
		return false
	case <-time.After(d):
		return true
	}
}
