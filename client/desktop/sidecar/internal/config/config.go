package config

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

// ServerConfig mirrors the macOS native ServerConfig model. JSON tags use
// camelCase to match Swift Codable's default, so both apps share the same
// config.json. The Manager's load methods also accept legacy snake_case.
type ServerConfig struct {
	ServerAddr    string `json:"serverAddr"`
	ServerPort    int    `json:"serverPort"`
	AuthToken     string `json:"authToken"`
	SubDomainHost string `json:"subDomainHost"`
	TLSEnabled    bool   `json:"tlsEnabled"`
	AdminPort     int    `json:"adminPort"`
	AdminUser     string `json:"adminUser"`
	AdminPassword string `json:"adminPassword"`
	// ManagementURL 是服务端管理页地址（如 http://vps:17500），用于拉取域名目录。
	// 与 frps 连接无关；留空则隧道编辑走手填模式。
	ManagementURL string `json:"managementURL"`
	// DomainAPIToken 是拉取 GET /api/domains 用的 Bearer token
	// （对应服务端 MEILINK_DOMAIN_API_TOKEN），与管理页登录账号独立。留空则不拉取。
	DomainAPIToken string `json:"domainAPIToken"`
}

// TunnelType represents a tunnel proxy type.
type TunnelType string

const (
	TunnelTCP   TunnelType = "tcp"
	TunnelUDP   TunnelType = "udp"
	TunnelHTTP  TunnelType = "http"
	TunnelHTTPS TunnelType = "https"
)

// TunnelStatus mirrors the frpc working-status phase. Values map to frp's
// internal phase strings (lowercased for storage).
type TunnelStatus string

const (
	StatusNew         TunnelStatus = "new"
	StatusWaitStart   TunnelStatus = "wait_start"
	StatusStartError  TunnelStatus = "start_error"
	StatusRunning     TunnelStatus = "running"
	StatusCheckFailed TunnelStatus = "check_failed"
	StatusClosed      TunnelStatus = "closed"
)

// StatusFromFrpcPhase converts an frpc status phase string (as returned by
// /api/status) into a TunnelStatus. Mirrors Swift TunnelStatus(frpcPhase:).
func StatusFromFrpcPhase(phase string) TunnelStatus {
	switch strings.ToLower(strings.TrimSpace(phase)) {
	case "new":
		return StatusNew
	case "wait start":
		return StatusWaitStart
	case "start error":
		return StatusStartError
	case "running":
		return StatusRunning
	case "check failed":
		return StatusCheckFailed
	case "closed":
		return StatusClosed
	default:
		return StatusNew
	}
}

// DisplayName returns the Chinese display label for the status.
func (s TunnelStatus) DisplayName() string {
	switch s {
	case StatusNew:
		return "新建"
	case StatusWaitStart:
		return "连接中"
	case StatusStartError:
		return "启动失败"
	case StatusRunning:
		return "运行中"
	case StatusCheckFailed:
		return "检查失败"
	case StatusClosed:
		return "已关闭"
	default:
		return string(s)
	}
}

// Tunnel is a persisted tunnel definition. RuntimeStatus maps to Swift's
// persisted "status" field when saved, and accepts either "status" or legacy
// "runtimeStatus" when loaded.
type Tunnel struct {
	ID                string     `json:"id"`
	Name              string     `json:"name"`
	Type              TunnelType `json:"type"`
	LocalIP           string     `json:"localIP"`
	LocalPort         int        `json:"localPort"`
	RemotePort        int        `json:"remotePort,omitempty"`
	Subdomain         string     `json:"subdomain,omitempty"`
	CustomDomains     []string   `json:"customDomains,omitempty"`
	HTTPUser          string     `json:"httpUser,omitempty"`
	HTTPPassword      string     `json:"httpPassword,omitempty"`
	HostHeaderRewrite string     `json:"hostHeaderRewrite,omitempty"`
	Enabled           bool       `json:"enabled"`
	CreatedAt         time.Time  `json:"createdAt"`
	UpdatedAt         time.Time  `json:"updatedAt"`

	// Runtime fields (not persisted).
	RuntimeStatus string `json:"runtimeStatus,omitempty"`
	RemoteAddr    string `json:"remoteAddr,omitempty"`
	ErrorMessage  string `json:"errorMessage,omitempty"`
}

func (t *Tunnel) UnmarshalJSON(data []byte) error {
	type tunnelAlias Tunnel
	var aux struct {
		tunnelAlias
		Status string `json:"status,omitempty"`
	}
	if err := json.Unmarshal(data, &aux); err != nil {
		return err
	}
	*t = Tunnel(aux.tunnelAlias)
	t.RuntimeStatus = normalizeStoredStatus(t.RuntimeStatus)
	if t.RuntimeStatus == "" {
		t.RuntimeStatus = normalizeStoredStatus(aux.Status)
	}
	if !t.Enabled && t.RuntimeStatus == "" {
		t.RuntimeStatus = string(StatusClosed)
	}
	return nil
}

// MarshalJSON emits the full tunnel shape including runtime fields
// (RuntimeStatus / ErrorMessage / RemoteAddr) so the HTTP API can return
// them to the frontend. Persistence is handled separately by SaveTunnels,
// which strips runtime fields before writing to tunnels.json (see SDD
// 05-data-contract §2.1 — those are transient values that must not be
// persisted, otherwise the Swift native client reads stale "closed" status
// on launch).
func (t Tunnel) MarshalJSON() ([]byte, error) {
	type tunnelJSON struct {
		ID                string     `json:"id"`
		Name              string     `json:"name"`
		Type              TunnelType `json:"type"`
		LocalIP           string     `json:"localIP"`
		LocalPort         int        `json:"localPort"`
		RemotePort        int        `json:"remotePort,omitempty"`
		Subdomain         string     `json:"subdomain,omitempty"`
		CustomDomains     []string   `json:"customDomains"`
		HTTPUser          string     `json:"httpUser,omitempty"`
		HTTPPassword      string     `json:"httpPassword,omitempty"`
		HostHeaderRewrite string     `json:"hostHeaderRewrite,omitempty"`
		Enabled           bool       `json:"enabled"`
		Status            string     `json:"status"`
		ErrorMessage      string     `json:"errorMessage,omitempty"`
		RemoteAddr        string     `json:"remoteAddr,omitempty"`
		CreatedAt         time.Time  `json:"createdAt"`
		UpdatedAt         time.Time  `json:"updatedAt"`
	}
	aux := tunnelJSON{
		ID:                t.ID,
		Name:              t.Name,
		Type:              t.Type,
		LocalIP:           t.LocalIP,
		LocalPort:         t.LocalPort,
		RemotePort:        t.RemotePort,
		Subdomain:         t.Subdomain,
		CustomDomains:     t.CustomDomains,
		HTTPUser:          t.HTTPUser,
		HTTPPassword:      t.HTTPPassword,
		HostHeaderRewrite: t.HostHeaderRewrite,
		Enabled:           t.Enabled,
		Status:            swiftStatusName(t.RuntimeStatus),
		ErrorMessage:      t.ErrorMessage,
		RemoteAddr:        t.RemoteAddr,
		CreatedAt:         t.CreatedAt,
		UpdatedAt:         t.UpdatedAt,
	}
	if aux.CustomDomains == nil {
		aux.CustomDomains = []string{}
	}
	if aux.Status == "" {
		aux.Status = "new"
	}
	return json.Marshal(aux)
}

// persistentTunnel is the on-disk shape. It omits runtime fields so the
// Swift native client (which declares status/errorMessage/remoteAddr as
// transient) never reads stale values from tunnels.json.
type persistentTunnel struct {
	ID                string     `json:"id"`
	Name              string     `json:"name"`
	Type              TunnelType `json:"type"`
	LocalIP           string     `json:"localIP"`
	LocalPort         int        `json:"localPort"`
	RemotePort        int        `json:"remotePort,omitempty"`
	Subdomain         string     `json:"subdomain,omitempty"`
	CustomDomains     []string   `json:"customDomains"`
	HTTPUser          string     `json:"httpUser,omitempty"`
	HTTPPassword      string     `json:"httpPassword,omitempty"`
	HostHeaderRewrite string     `json:"hostHeaderRewrite,omitempty"`
	Enabled           bool       `json:"enabled"`
	CreatedAt         time.Time  `json:"createdAt"`
	UpdatedAt         time.Time  `json:"updatedAt"`
}

// toPersistent converts a Tunnel to its on-disk shape (no runtime fields).
func (t Tunnel) toPersistent() persistentTunnel {
	p := persistentTunnel{
		ID:                t.ID,
		Name:              t.Name,
		Type:              t.Type,
		LocalIP:           t.LocalIP,
		LocalPort:         t.LocalPort,
		RemotePort:        t.RemotePort,
		Subdomain:         t.Subdomain,
		CustomDomains:     t.CustomDomains,
		HTTPUser:          t.HTTPUser,
		HTTPPassword:      t.HTTPPassword,
		HostHeaderRewrite: t.HostHeaderRewrite,
		Enabled:           t.Enabled,
		CreatedAt:         t.CreatedAt,
		UpdatedAt:         t.UpdatedAt,
	}
	if p.CustomDomains == nil {
		p.CustomDomains = []string{}
	}
	return p
}

func normalizeStoredStatus(status string) string {
	switch strings.TrimSpace(status) {
	case "":
		return ""
	case "new":
		return string(StatusNew)
	case "waitStart", "wait_start", "wait start":
		return string(StatusWaitStart)
	case "startError", "start_error", "start error":
		return string(StatusStartError)
	case "running":
		return string(StatusRunning)
	case "checkFailed", "check_failed", "check failed":
		return string(StatusCheckFailed)
	case "closed":
		return string(StatusClosed)
	default:
		return status
	}
}

func swiftStatusName(status string) string {
	switch normalizeStoredStatus(status) {
	case string(StatusNew):
		return "new"
	case string(StatusWaitStart):
		return "waitStart"
	case string(StatusStartError):
		return "startError"
	case string(StatusRunning):
		return "running"
	case string(StatusCheckFailed):
		return "checkFailed"
	case string(StatusClosed):
		return "closed"
	default:
		return status
	}
}

// (Tunnel uses camelCase JSON tags; the Manager load methods handle legacy
// snake_case via dualUnmarshal.)

// RuntimeStatusRunning is a small helper alias so frpc/reachability.go can
// reference the running status without importing the string literal directly.
const (
	StatusRunningStr = string(StatusRunning)
)

// EventLog is a timestamped log entry surfaced in the Web UI.
type EventLog struct {
	ID        string    `json:"id"`
	Timestamp time.Time `json:"timestamp"`
	Message   string    `json:"message"`
	Level     string    `json:"level"` // info | warning | error
}

// AppSettings stores user preferences. JSON uses camelCase to match Swift.
type AppSettings struct {
	AutoStart                  bool    `json:"autoStart"`
	LaunchAtLogin              bool    `json:"launchAtLogin"`
	ShowInDock                 bool    `json:"showInDock"`
	StatusPollingInterval      float64 `json:"statusPollingInterval"`
	RemoteReachabilityInterval float64 `json:"remoteReachabilityInterval"`
	MenuBarIconStyle           string  `json:"menuBarIconStyle,omitempty"`
}

// Manager handles all persistent configuration files.
type Manager struct {
	dataDir string
}

// NewManager creates a new config manager. On macOS, if the native app's
// Application Support directory exists, it is used so configs are shared
// between the Swift native app and the cross-platform client.
func NewManager(dataDir string) (*Manager, error) {
	// On macOS, prefer the native app's data dir for config sharing.
	if runtime.GOOS == "darwin" {
		if nativeDir := macNativeDataDir(); nativeDir != "" {
			if _, err := os.Stat(filepath.Join(nativeDir, "config.json")); err == nil {
				dataDir = nativeDir
			} else if _, err := os.Stat(nativeDir); err == nil {
				// Native dir exists but no config yet — still use it so we
				// write to the shared location from the start.
				dataDir = nativeDir
			}
		}
	}
	if err := os.MkdirAll(dataDir, 0o700); err != nil {
		return nil, fmt.Errorf("create data dir: %w", err)
	}
	return &Manager{dataDir: dataDir}, nil
}

// macNativeDataDir returns ~/Library/Application Support/Meilink (Swift native).
func macNativeDataDir() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(home, "Library", "Application Support", "Meilink")
}

func (m *Manager) serverConfigPath() string { return filepath.Join(m.dataDir, "config.json") }
func (m *Manager) tunnelsPath() string      { return filepath.Join(m.dataDir, "tunnels.json") }
func (m *Manager) settingsPath() string     { return filepath.Join(m.dataDir, "settings.json") }

// IsConfigured returns true if a valid server config has been saved.
func (m *Manager) IsConfigured() bool {
	data, err := os.ReadFile(m.serverConfigPath())
	if err != nil {
		return false
	}
	var cfg ServerConfig
	if dualUnmarshal(data, &cfg) != nil {
		return false
	}
	return cfg.ServerAddr != "" && cfg.AuthToken != ""
}

// SaveServerConfig persists the server configuration.
func (m *Manager) SaveServerConfig(cfg *ServerConfig) error {
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(m.serverConfigPath(), data, 0o600)
}

// LoadServerConfig loads the saved server configuration.
func (m *Manager) LoadServerConfig() (*ServerConfig, error) {
	data, err := os.ReadFile(m.serverConfigPath())
	if err != nil {
		return nil, err
	}
	var cfg ServerConfig
	if err := dualUnmarshal(data, &cfg); err != nil {
		return nil, err
	}
	return &cfg, nil
}

// SaveTunnels persists all tunnels.
func (m *Manager) SaveTunnels(tunnels []Tunnel) error {
	// Write the persistent shape (no runtime fields) so the Swift native
	// client can decode tunnels.json without reading stale status/errorMessage
	// values (see SDD 05-data-contract §2.1).
	persistent := make([]persistentTunnel, len(tunnels))
	for i := range tunnels {
		persistent[i] = tunnels[i].toPersistent()
	}
	data, err := json.MarshalIndent(persistent, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(m.tunnelsPath(), data, 0o600)
}

// LoadTunnels loads all tunnels.
func (m *Manager) LoadTunnels() ([]Tunnel, error) {
	data, err := os.ReadFile(m.tunnelsPath())
	if err != nil {
		if os.IsNotExist(err) {
			return []Tunnel{}, nil
		}
		return nil, err
	}
	var tunnels []Tunnel
	if err := dualUnmarshal(data, &tunnels); err != nil {
		return nil, err
	}
	return tunnels, nil
}

// NormalizeTunnelsFile rewrites tunnels.json using the Swift Codable-compatible
// schema. It migrates older cross-platform files that persisted runtimeStatus.
func (m *Manager) NormalizeTunnelsFile() error {
	tunnels, err := m.LoadTunnels()
	if err != nil {
		return err
	}
	if len(tunnels) == 0 {
		return nil
	}
	return m.SaveTunnels(tunnels)
}

// SaveSettings persists app settings.
func (m *Manager) SaveSettings(s *AppSettings) error {
	data, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(m.settingsPath(), data, 0o600)
}

// LoadSettings loads app settings with defaults.
func (m *Manager) LoadSettings() (*AppSettings, error) {
	s := &AppSettings{
		AutoStart:                  true,
		LaunchAtLogin:              false,
		ShowInDock:                 false,
		StatusPollingInterval:      3.0,
		RemoteReachabilityInterval: 60.0,
		MenuBarIconStyle:           "portal",
	}
	data, err := os.ReadFile(m.settingsPath())
	if err != nil {
		return s, nil
	}
	if err := dualUnmarshal(data, s); err != nil {
		return s, nil
	}
	return s, nil
}

// FrpcConfigPath returns the generated frpc.toml path.
func (m *Manager) FrpcConfigPath() string {
	return filepath.Join(m.dataDir, "frpc.toml")
}

// GenerateFrpcToml generates a frpc.toml from server config and active tunnels.
func (m *Manager) GenerateFrpcToml(serverCfg *ServerConfig, tunnels []Tunnel) error {
	var sb strings.Builder

	sb.WriteString("# Auto-generated by Meilink\n")
	sb.WriteString(fmt.Sprintf("serverAddr = %s\n", tomlString(serverCfg.ServerAddr)))
	sb.WriteString(fmt.Sprintf("serverPort = %d\n\n", serverCfg.ServerPort))

	sb.WriteString("auth.method = \"token\"\n")
	sb.WriteString(fmt.Sprintf("auth.token = %s\n\n", tomlString(serverCfg.AuthToken)))

	sb.WriteString(fmt.Sprintf("transport.tls.enable = %t\n", serverCfg.TLSEnabled))
	sb.WriteString("transport.poolCount = 5\n")
	sb.WriteString("transport.tcpMux = true\n")
	sb.WriteString("transport.tcpMuxKeepaliveInterval = 30\n\n")

	sb.WriteString("webServer.addr = \"127.0.0.1\"\n")
	sb.WriteString(fmt.Sprintf("webServer.port = %d\n", serverCfg.AdminPort))
	sb.WriteString(fmt.Sprintf("webServer.user = %s\n", tomlString(serverCfg.AdminUser)))
	sb.WriteString(fmt.Sprintf("webServer.password = %s\n\n", tomlString(serverCfg.AdminPassword)))

	sb.WriteString("[store]\n")
	sb.WriteString(fmt.Sprintf("path = %s\n\n", tomlString(filepath.Join(m.dataDir, "store.json"))))
	sb.WriteString("# Proxies are managed dynamically via Store API\n")

	return os.WriteFile(m.FrpcConfigPath(), []byte(sb.String()), 0o600)
}

// tomlString uses JSON's compatible basic-string escaping, which is valid
// TOML and keeps Windows backslashes from being interpreted as escapes.
func tomlString(value string) string {
	encoded, _ := json.Marshal(value)
	return string(encoded)
}

// dualUnmarshal decodes JSON into v, accepting both camelCase (Swift native)
// and snake_case (legacy Go) keys. It first tries a direct decode; if that
// fails (missing fields due to snake_case), it normalizes all keys to
// camelCase and retries. Since the structs have no custom UnmarshalJSON,
// there is no recursion risk.
func dualUnmarshal(data []byte, v interface{}) error {
	// First try direct decode (camelCase tags match).
	if err := json.Unmarshal(data, v); err == nil {
		return nil
	}
	// Fallback: normalize snake_case keys to camelCase, then decode.
	converted := snakeToCamelJSON(data)
	return json.Unmarshal(converted, v)
}

// snakeToCamelJSON walks a raw JSON byte slice and rewrites all map keys from
// snake_case to camelCase. It handles nested objects and arrays.
func snakeToCamelJSON(data []byte) []byte {
	var raw interface{}
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.UseNumber()
	if err := dec.Decode(&raw); err != nil {
		return data
	}
	transformed := transformKeys(raw)
	out, err := json.Marshal(transformed)
	if err != nil {
		return data
	}
	return out
}

// toCamel converts a snake_case string to camelCase.
func toCamel(s string) string {
	parts := strings.Split(s, "_")
	if len(parts) == 1 {
		return s
	}
	result := parts[0]
	for _, p := range parts[1:] {
		if len(p) > 0 {
			result += strings.ToUpper(p[:1]) + p[1:]
		}
	}
	return result
}

// transformKeys recursively converts all map keys in a decoded JSON value
// from snake_case to camelCase.
func transformKeys(v interface{}) interface{} {
	switch val := v.(type) {
	case map[string]interface{}:
		result := make(map[string]interface{}, len(val))
		for k, vv := range val {
			result[toCamel(k)] = transformKeys(vv)
		}
		return result
	case []interface{}:
		for i, item := range val {
			val[i] = transformKeys(item)
		}
		return val
	default:
		return v
	}
}
