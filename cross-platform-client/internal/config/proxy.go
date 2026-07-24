package config

import "strings"

// ProxyDefinition is the nested payload shape that frpc's Store API expects.
// Mirrors Swift ProxyDefinition.swift and the frp v0.70 source at
// client/http/model/proxy_definition.go.
type ProxyDefinition struct {
	Name  string             `json:"name"`
	Type  string             `json:"type"`
	TCP   *TCPProxyConfig    `json:"tcp,omitempty"`
	UDP   *UDPProxyConfig    `json:"udp,omitempty"`
	HTTP  *HTTPProxyConfig   `json:"http,omitempty"`
	HTTPS *HTTPSProxyConfig  `json:"https,omitempty"`
}

type TCPProxyConfig struct {
	LocalIP    string `json:"localIP"`
	LocalPort  int    `json:"localPort"`
	RemotePort int    `json:"remotePort"`
}

type UDPProxyConfig struct {
	LocalIP    string `json:"localIP"`
	LocalPort  int    `json:"localPort"`
	RemotePort int    `json:"remotePort"`
}

type HTTPProxyConfig struct {
	LocalIP           string            `json:"localIP"`
	LocalPort         int               `json:"localPort"`
	Subdomain         string            `json:"subdomain,omitempty"`
	CustomDomains     []string          `json:"customDomains,omitempty"`
	Locations         []string          `json:"locations,omitempty"`
	HTTPUser          string            `json:"httpUser,omitempty"`
	HTTPPassword      string            `json:"httpPassword,omitempty"`
	HostHeaderRewrite string            `json:"hostHeaderRewrite,omitempty"`
	RequestHeaders    map[string]string `json:"requestHeaders,omitempty"`
	ResponseHeaders   map[string]string `json:"responseHeaders,omitempty"`
}

type HTTPSProxyConfig struct {
	LocalIP       string   `json:"localIP"`
	LocalPort     int      `json:"localPort"`
	Subdomain     string   `json:"subdomain,omitempty"`
	CustomDomains []string `json:"customDomains,omitempty"`
}

// SubdomainNormalize strips a trailing ".{baseHost}" suffix from subdomain so
// that frpc gets just the prefix (e.g. "app" instead of "app.tunnel.example.com").
// Mirrors Swift SubdomainNormalizer.normalize.
func SubdomainNormalize(subdomain, baseHost string) string {
	v := strings.TrimSpace(subdomain)
	if v == "" {
		return ""
	}
	host := strings.TrimSpace(baseHost)
	if host == "" {
		return v
	}
	suffix := "." + host
	if strings.HasSuffix(v, suffix) {
		prefix := strings.TrimSuffix(v, suffix)
		if prefix == "" {
			return ""
		}
		return prefix
	}
	return v
}

// ToProxyDefinition converts a persisted Tunnel into the nested ProxyDefinition
// payload the frpc Store API requires. Mirrors Swift Tunnel.toProxyDefinition().
func (t Tunnel) ToProxyDefinition(serverCfg *ServerConfig) ProxyDefinition {
	var baseHost string
	if serverCfg != nil {
		baseHost = serverCfg.SubDomainHost
	}
	normalized := SubdomainNormalize(t.Subdomain, baseHost)

	switch t.Type {
	case TunnelTCP:
		return ProxyDefinition{
			Name: t.Name,
			Type: "tcp",
			TCP: &TCPProxyConfig{
				LocalIP:    t.LocalIP,
				LocalPort:  t.LocalPort,
				RemotePort: t.RemotePort,
			},
		}
	case TunnelUDP:
		return ProxyDefinition{
			Name: t.Name,
			Type: "udp",
			UDP: &UDPProxyConfig{
				LocalIP:    t.LocalIP,
				LocalPort:  t.LocalPort,
				RemotePort: t.RemotePort,
			},
		}
	case TunnelHTTP:
		hc := &HTTPProxyConfig{
			LocalIP:           t.LocalIP,
			LocalPort:         t.LocalPort,
			Locations:         []string{"/"},
			HostHeaderRewrite: t.HostHeaderRewrite,
			HTTPUser:          t.HTTPUser,
			HTTPPassword:      t.HTTPPassword,
		}
		if normalized != "" {
			hc.Subdomain = normalized
		}
		if len(t.CustomDomains) > 0 {
			hc.CustomDomains = t.CustomDomains
		}
		return ProxyDefinition{Name: t.Name, Type: "http", HTTP: hc}
	case TunnelHTTPS:
		hc := &HTTPSProxyConfig{
			LocalIP:   t.LocalIP,
			LocalPort: t.LocalPort,
		}
		if normalized != "" {
			hc.Subdomain = normalized
		}
		if len(t.CustomDomains) > 0 {
			hc.CustomDomains = t.CustomDomains
		}
		return ProxyDefinition{Name: t.Name, Type: "https", HTTPS: hc}
	}
	return ProxyDefinition{Name: t.Name, Type: string(t.Type)}
}

// ProxyListResponse mirrors the {"proxies":[...]} wrapper from GET /api/store/proxies.
type ProxyListResponse struct {
	Proxies []ProxyDefinition `json:"proxies"`
}
