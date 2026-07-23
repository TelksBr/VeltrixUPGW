package session

import (
	"bufio"
	"context"
	"io"
	"log/slog"
	"net"
	"sync"
	"time"

	"github.com/dragoncoressh/udpgw-standalone/internal/config"
	"github.com/dragoncoressh/udpgw-standalone/internal/metrics"
	"github.com/dragoncoressh/udpgw-standalone/internal/protocol"
)

var udpReadBufPool = sync.Pool{
	New: func() any {
		b := make([]byte, protocol.MaxUDPDatagram)
		return &b
	},
}

// Client handles one TCP udpgw client connection.
type Client struct {
	Conn    net.Conn
	Cfg     config.Config
	Metrics *metrics.Metrics
	SafeGo  func(name string, fn func())
}

// Run serves the client until disconnect or error.
func (c *Client) Run(ctx context.Context) error {
	defer c.Conn.Close()
	remote := c.Conn.RemoteAddr().String()
	if c.Cfg.Debug {
		slog.Info("client connected", "remote", remote)
	}
	if tcp, ok := c.Conn.(*net.TCPConn); ok {
		_ = tcp.SetNoDelay(true)
	}

	br := bufio.NewReaderSize(c.Conn, 32*1024)
	sctx, cancel := context.WithCancel(ctx)
	defer cancel()

	var laddr *net.UDPAddr
	if c.Cfg.UDPBindIP != "" {
		ip := net.ParseIP(c.Cfg.UDPBindIP)
		if ip == nil {
			slog.Error("invalid udp_bind IP", "remote", remote, "ip", c.Cfg.UDPBindIP)
			return nil
		}
		laddr = &net.UDPAddr{IP: ip, Port: 0}
	}
	udpConn, err := net.ListenUDP("udp", laddr)
	if err != nil {
		slog.Error("UDP listen failed", "remote", remote, "err", err)
		return err
	}
	defer udpConn.Close()
	_ = udpConn.SetReadBuffer(c.Cfg.UDPRBuf)
	_ = udpConn.SetWriteBuffer(c.Cfg.UDPWBuf)

	writeCh := make(chan []byte, c.Cfg.WriteChan)
	done := make(chan struct{})

	c.SafeGo("client-writer", func() {
		defer close(done)
		for {
			select {
			case <-sctx.Done():
				return
			case b := <-writeCh:
				if len(b) == 0 {
					continue
				}
				_ = c.Conn.SetWriteDeadline(time.Now().Add(30 * time.Second))
				if _, err := c.Conn.Write(b); err != nil {
					cancel()
					return
				}
			}
		}
	})

	destMap := NewDestMap(c.Cfg, time.Now)
	var mapMu sync.Mutex

	c.SafeGo("client-reaper", func() {
		t := time.NewTicker(c.Cfg.ReapEvery)
		defer t.Stop()
		for {
			select {
			case <-sctx.Done():
				return
			case <-t.C:
				mapMu.Lock()
				destMap.Reap()
				if c.Metrics != nil {
					c.Metrics.MappingSize.Set(float64(destMap.Size()))
				}
				mapMu.Unlock()
			}
		}
	})

	c.SafeGo("client-udp-reader", func() {
		bufPtr := udpReadBufPool.Get().(*[]byte)
		buf := *bufPtr
		defer udpReadBufPool.Put(bufPtr)

		for {
			n, from, err := udpConn.ReadFromUDP(buf)
			if err != nil {
				return
			}
			if n <= 0 {
				continue
			}
			ip4 := from.IP.To4()
			if ip4 == nil {
				continue
			}
			key := DestKey{Port: uint16(from.Port)}
			copy(key.IP[:], ip4)

			mapMu.Lock()
			connID, x, ok := destMap.Lookup(key)
			mapMu.Unlock()

			if !ok {
				if c.Cfg.Debug {
					slog.Debug("drop reply: no mapping", "remote", remote, "from", from.String(), "bytes", n)
				}
				if c.Metrics != nil {
					c.Metrics.DroppedReplies.Inc()
				}
				continue
			}

			if !c.tryEnqueue(writeCh, sctx, protocol.BuildFrame(connID, x, key.IP, key.Port, buf[:n]), remote, from.String(), n) {
				continue
			}
			if c.Cfg.Debug {
				slog.Debug("UDP reply routed", "remote", remote, "from", from.String(), "connID", connID, "x", x, "bytes", n)
			}
		}
	})

	for {
		select {
		case <-sctx.Done():
			cancel()
			<-done
			return sctx.Err()
		default:
		}

		if c.Cfg.IdleTimeout > 0 {
			_ = c.Conn.SetReadDeadline(time.Now().Add(c.Cfg.IdleTimeout))
		}
		payload, err := protocol.ReadPayload(br, c.Cfg.MaxFrame)
		if err != nil {
			if ne, ok := err.(net.Error); ok && ne.Timeout() {
				if c.Cfg.Debug {
					slog.Debug("idle timeout", "remote", remote, "timeout", c.Cfg.IdleTimeout)
				}
			} else if err != io.EOF {
				slog.Warn("read error", "remote", remote, "err", err)
				if c.Metrics != nil {
					c.Metrics.ReadErrors.Inc()
				}
			} else if c.Cfg.Debug {
				slog.Debug("client disconnected", "remote", remote)
			}
			cancel()
			_ = c.Conn.Close()
			<-done
			return err
		}

		req, err := protocol.ParseRequest(payload)
		if err != nil {
			if c.Cfg.Debug {
				slog.Debug("invalid payload", "remote", remote, "err", err)
			}
			continue
		}

		if c.Cfg.Debug {
			slog.Debug("RX frame",
				"remote", remote,
				"connID", req.ConnID,
				"dst", net.IP(req.DstIP[:]).String(),
				"port", req.DstPort,
				"x", req.X,
				"len", len(req.Data),
			)
		}

		mapMu.Lock()
		destMap.Update(req.ConnID, req.X, req.DstIP, req.DstPort)
		if c.Metrics != nil {
			c.Metrics.MappingSize.Set(float64(destMap.Size()))
		}
		mapMu.Unlock()

		raddr := &net.UDPAddr{IP: net.IP(req.DstIP[:]), Port: int(req.DstPort)}
		if _, err := udpConn.WriteToUDP(req.Data, raddr); err != nil {
			if c.Cfg.Debug {
				slog.Debug("UDP write failed", "remote", remote, "dst", raddr.String(), "err", err)
			}
			if c.Metrics != nil {
				c.Metrics.UDPWriteErrors.Inc()
			}
			continue
		}
		if c.Cfg.Debug {
			slog.Debug("UDP sent", "remote", remote, "dst", raddr.String(), "bytes", len(req.Data))
		}
	}
}

func (c *Client) tryEnqueue(writeCh chan []byte, ctx context.Context, frame []byte, remote, from string, n int) bool {
	if len(writeCh) == cap(writeCh) {
		if c.Cfg.Debug {
			slog.Debug("drop reply: write queue full", "remote", remote, "from", from, "bytes", n)
		}
		if c.Metrics != nil {
			c.Metrics.DroppedReplies.Inc()
		}
		return false
	}
	select {
	case <-ctx.Done():
		return false
	case writeCh <- frame:
		return true
	default:
		if c.Cfg.Debug {
			slog.Debug("drop reply: enqueue race", "remote", remote, "from", from, "bytes", n)
		}
		if c.Metrics != nil {
			c.Metrics.DroppedReplies.Inc()
		}
		return false
	}
}
