package engine

import (
	"github.com/fatedier/frp/pkg/config/v1"

	"github.com/meilink/desktop-sidecar/internal/config"
)

// TunnelToConfigurer converts a Meilink Tunnel to an frp ProxyConfigurer.
// This replaces the JSON round-trip through the Admin API Store endpoint —
// the engine applies proxies directly via the in-process config source.
func TunnelToConfigurer(t config.Tunnel, serverCfg *config.ServerConfig) v1.ProxyConfigurer {
	localIP := t.LocalIP
	if localIP == "" {
		localIP = "127.0.0.1"
	}
	subdomain := config.SubdomainNormalize(t.Subdomain, serverCfg.SubDomainHost)

	base := v1.ProxyBaseConfig{
		Name: t.Name,
		Type: string(t.Type),
		ProxyBackend: v1.ProxyBackend{
			LocalIP:   localIP,
			LocalPort: t.LocalPort,
		},
	}

	switch t.Type {
	case config.TunnelTCP:
		return &v1.TCPProxyConfig{
			ProxyBaseConfig: base,
			RemotePort:      t.RemotePort,
		}
	case config.TunnelUDP:
		return &v1.UDPProxyConfig{
			ProxyBaseConfig: base,
			RemotePort:      t.RemotePort,
		}
	case config.TunnelHTTP:
		hc := &v1.HTTPProxyConfig{
			ProxyBaseConfig: base,
			HTTPUser:         t.HTTPUser,
			HTTPPassword:     t.HTTPPassword,
			HostHeaderRewrite: t.HostHeaderRewrite,
			Locations:        []string{"/"},
		}
		if subdomain != "" {
			hc.SubDomain = subdomain
		}
		if len(t.CustomDomains) > 0 {
			hc.CustomDomains = t.CustomDomains
		}
		// Locations default to ["/"] (matches Swift/Go ToProxyDefinition).
		return hc
	case config.TunnelHTTPS:
		hc := &v1.HTTPSProxyConfig{
			ProxyBaseConfig: base,
		}
		if subdomain != "" {
			hc.SubDomain = subdomain
		}
		if len(t.CustomDomains) > 0 {
			hc.CustomDomains = t.CustomDomains
		}
		return hc
	default:
		// Fallback: treat unknown types as TCP.
		return &v1.TCPProxyConfig{
			ProxyBaseConfig: base,
			RemotePort:      t.RemotePort,
		}
	}
}

// TunnelsToConfigurers converts a slice of Meilink Tunnels (only enabled ones)
// to frp ProxyConfigurers.
func TunnelsToConfigurers(tunnels []config.Tunnel, serverCfg *config.ServerConfig) []v1.ProxyConfigurer {
	result := make([]v1.ProxyConfigurer, 0, len(tunnels))
	for _, t := range tunnels {
		if !t.Enabled {
			continue
		}
		result = append(result, TunnelToConfigurer(t, serverCfg))
	}
	return result
}
