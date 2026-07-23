package server

import (
	"log/slog"
)

func safeGo(s *Server, name string, fn func()) {
	go func() {
		defer func() {
			if r := recover(); r != nil {
				slog.Error("panic in goroutine", "name", name, "panic", r)
				if s.metrics != nil {
					s.metrics.PanicsTotal.Inc()
				}
			}
		}()
		fn()
	}()
}
