package frpc

import (
	"fmt"
	"net"
	"strconv"
	"strings"
	"time"

	"github.com/meilink/client/internal/config"
)

// ReachabilityProbe performs a short TCP dial against a tunnel's remote
// endpoint to verify it is externally reachable. Mirrors Swift
// TunnelReachabilityProbe. UDP is skipped (returns Reachable).
type ReachabilityProbe struct {
	tcpTimeout time.Duration
}

// ReachabilityResult is the outcome of one probe.
type ReachabilityResult int

const (
	ReachabilityReachable ReachabilityResult = iota
	ReachabilityUnreachable
	ReachabilitySkipped
)

// NewReachabilityProbe creates a probe with a 4-second TCP timeout.
func NewReachabilityProbe() *ReachabilityProbe {
	return &ReachabilityProbe{tcpTimeout: 4 * time.Second}
}

// Check probes a tunnel using its runtime remoteAddr (from /api/status).
func (p *ReachabilityProbe) Check(t config.Tunnel) ReachabilityResult {
	if !t.Enabled || t.RuntimeStatus != config.StatusRunningStr {
		return ReachabilitySkipped
	}

	switch t.Type {
	case config.TunnelHTTP:
		host, port, ok := endpointFor(t.RemoteAddr, 80)
		if !ok {
			return ReachabilitySkipped
		}
		return p.checkTCP(host, port)
	case config.TunnelHTTPS:
		host, port, ok := endpointFor(t.RemoteAddr, 443)
		if !ok {
			return ReachabilitySkipped
		}
		return p.checkTCP(host, port)
	case config.TunnelTCP:
		defaultPort := t.RemotePort
		host, port, ok := endpointFor(t.RemoteAddr, defaultPort)
		if !ok {
			return ReachabilitySkipped
		}
		return p.checkTCP(host, port)
	case config.TunnelUDP:
		return ReachabilitySkipped
	}
	return ReachabilitySkipped
}

// endpointFor parses a frpc remoteAddr (e.g. "1.2.3.4:6000") into host/port,
// falling back to defaultPort if the address lacks a port.
func endpointFor(remoteAddr string, defaultPort int) (string, int, bool) {
	addr := strings.TrimSpace(remoteAddr)
	if addr == "" {
		return "", 0, false
	}
	if host, portStr, err := net.SplitHostPort(addr); err == nil {
		if port, err := strconv.Atoi(portStr); err == nil && port > 0 {
			return host, port, true
		}
		return host, defaultPort, true
	}
	if defaultPort <= 0 {
		return "", 0, false
	}
	return addr, defaultPort, true
}

func (p *ReachabilityProbe) checkTCP(host string, port int) ReachabilityResult {
	conn, err := net.DialTimeout("tcp", net.JoinHostPort(host, fmt.Sprintf("%d", port)), p.tcpTimeout)
	if err != nil {
		return ReachabilityUnreachable
	}
	conn.Close()
	return ReachabilityReachable
}

// TestConnection probes an arbitrary host:port via TCP with a 5-second timeout.
// Mirrors Swift NetworkHelper.testConnection. Returns (ok, errMessage).
// Used by the "测试连接" button in settings/setup to verify VPS reachability
// before saving the server config.
func TestConnection(host string, port int) (bool, string) {
	if host == "" || port <= 0 {
		return false, "地址或端口无效"
	}
	addr := net.JoinHostPort(host, fmt.Sprintf("%d", port))
	conn, err := net.DialTimeout("tcp", addr, 5*time.Second)
	if err != nil {
		return false, err.Error()
	}
	conn.Close()
	return true, ""
}
