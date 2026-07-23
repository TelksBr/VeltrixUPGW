package metrics

import (
	"github.com/prometheus/client_golang/prometheus"
)

// Metrics holds Prometheus instruments for the UDP gateway.
type Metrics struct {
	reg              *prometheus.Registry
	ActiveClients    prometheus.Gauge
	ClientsTotal     prometheus.Counter
	ClientsRejected  prometheus.Counter
	DroppedReplies   prometheus.Counter
	ReadErrors       prometheus.Counter
	UDPWriteErrors   prometheus.Counter
	PanicsTotal      prometheus.Counter
	MappingSize      prometheus.Gauge
}

// New creates metrics registered on a new Prometheus registry.
func New() *Metrics {
	reg := prometheus.NewRegistry()
	return NewWith(reg)
}

// NewWith registers metrics on the provided registry (for tests and custom handlers).
func NewWith(reg *prometheus.Registry) *Metrics {
	m := &Metrics{reg: reg}
	m.ActiveClients = prometheus.NewGauge(prometheus.GaugeOpts{
		Name: "udpgw_active_clients",
		Help: "Number of connected TCP clients.",
	})
	m.ClientsTotal = prometheus.NewCounter(prometheus.CounterOpts{
		Name: "udpgw_clients_total",
		Help: "Total accepted TCP clients.",
	})
	m.ClientsRejected = prometheus.NewCounter(prometheus.CounterOpts{
		Name: "udpgw_clients_rejected_total",
		Help: "Clients rejected due to max_clients cap.",
	})
	m.DroppedReplies = prometheus.NewCounter(prometheus.CounterOpts{
		Name: "udpgw_dropped_replies_total",
		Help: "UDP replies dropped due to backpressure or missing mapping.",
	})
	m.ReadErrors = prometheus.NewCounter(prometheus.CounterOpts{
		Name: "udpgw_read_errors_total",
		Help: "TCP read errors from clients.",
	})
	m.UDPWriteErrors = prometheus.NewCounter(prometheus.CounterOpts{
		Name: "udpgw_udp_write_errors_total",
		Help: "Failed UDP writes to destinations.",
	})
	m.PanicsTotal = prometheus.NewCounter(prometheus.CounterOpts{
		Name: "udpgw_panics_total",
		Help: "Recovered panics in goroutines.",
	})
	m.MappingSize = prometheus.NewGauge(prometheus.GaugeOpts{
		Name: "udpgw_mapping_size",
		Help: "Destination mapping entries for the last observed client update.",
	})
	reg.MustRegister(
		m.ActiveClients,
		m.ClientsTotal,
		m.ClientsRejected,
		m.DroppedReplies,
		m.ReadErrors,
		m.UDPWriteErrors,
		m.PanicsTotal,
		m.MappingSize,
	)
	return m
}

// Registry returns the Prometheus registry backing these metrics.
func (m *Metrics) Registry() *prometheus.Registry {
	return m.reg
}
