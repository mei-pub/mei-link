package tunnel

import (
	"context"
	"fmt"
	"log"
	"path/filepath"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/meilink/desktop-sidecar/internal/config"
	"github.com/meilink/desktop-sidecar/internal/frpc"
)

const (
	maxConsecutiveFailuresBeforeRecovery = 3
	recoveryCooldown                     = 20 * time.Second
	maxEventLogSize                      = 100
)

// Manager orchestrates frpc process, admin API, and tunnel CRUD. It mirrors
// the macOS Swift TunnelManager: status polling, remote reachability probing,
// automatic reconnect, and an event log surfaced via the Web UI.
type Manager struct {
	cfg      *config.Manager
	frpc     *frpc.Process
	adminAPI *frpc.AdminAPI
	probe    *frpc.ReachabilityProbe

	mu       sync.RWMutex
	tunnels  []config.Tunnel
	settings *config.AppSettings
	events   []config.EventLog

	logger *log.Logger
	ctx    context.Context
	cancel context.CancelFunc

	// runtime state
	isFrpcRunning bool
	isConnected   bool
	ownsFrpc      bool

	statusTimer             *time.Ticker
	lastReachabilityProbeAt time.Time
	isPollingStatus         bool
	isRecovering            bool
	consecutiveFailures     int
	lastRecoveryAt          time.Time
}

// NewManager creates a new tunnel manager.
func NewManager(cfgDir string) (*Manager, error) {
	ctx, cancel := context.WithCancel(context.Background())
	cfgMgr, err := config.NewManager(cfgDir)
	if err != nil {
		cancel()
		return nil, err
	}

	s, _ := cfgMgr.LoadSettings()
	if s == nil {
		s = &config.AppSettings{AutoStart: true, StatusPollingInterval: 3.0, RemoteReachabilityInterval: 60.0, MenuBarIconStyle: "portal"}
	}

	tunnels, _ := cfgMgr.LoadTunnels()
	if tunnels == nil {
		tunnels = []config.Tunnel{}
	}
	if err := cfgMgr.NormalizeTunnelsFile(); err != nil {
		log.Printf("warning: could not normalize tunnels.json: %v", err)
	}
	for i := range tunnels {
		if tunnels[i].Enabled {
			tunnels[i].RuntimeStatus = string(config.StatusClosed)
		}
	}

	m := &Manager{
		cfg:      cfgMgr,
		frpc:     frpc.NewProcess(""),
		probe:    frpc.NewReachabilityProbe(),
		tunnels:  tunnels,
		settings: s,
		logger:   log.Default(),
		ctx:      ctx,
		cancel:   cancel,
	}

	// Desktop bundles pass the exact frpc path through MEILINK_FRPC_BIN. Use
	// it before the legacy download fallback so saving settings never depends
	// on GitHub access (particularly important for packaged Windows builds).
	if bundledPath := frpc.ResolveBinPath(); bundledPath != "" {
		m.frpc = frpc.NewProcess(bundledPath)
	} else {
		dl := frpc.NewDownloader()
		// 使用配置管理器的实际数据目录（macOS 上可能是 Application Support）
		dataDir := filepath.Dir(m.cfg.FrpcConfigPath())
		binPath, err := dl.EnsureFrpc(dataDir)
		if err != nil {
			log.Printf("warning: could not ensure frpc binary: %v", err)
		} else {
			m.frpc = frpc.NewProcess(binPath)
		}
	}

	// Wire frpc process callbacks. OnTermination triggers automatic recovery
	// when frpc exits abnormally (non-zero status); OnOutput forwards each
	// stdout/stderr line into the event log as "frpc: <line>". Mirrors Swift
	// FrpcProcess.onTermination / onOutput.
	m.frpc.OnOutput = func(line string) {
		m.addEvent("frpc: "+line, "info")
	}
	m.frpc.OnTermination = func(status int, intentional bool) {
		m.mu.Lock()
		m.isFrpcRunning = false
		m.isConnected = false
		m.ownsFrpc = false
		m.stopStatusPolling()
		for i := range m.tunnels {
			if m.tunnels[i].Enabled {
				m.tunnels[i].RuntimeStatus = string(config.StatusClosed)
				m.tunnels[i].ErrorMessage = fmt.Sprintf("frpc 进程已退出，状态码: %d", status)
			}
		}
		m.mu.Unlock()
		// 主动停止（Stop/StopImmediately/recoverConnection 内的 kill）不算崩溃：
		// 被终止信号杀掉的进程状态码非 0，但那只是信号值，不应触发自动恢复，
		// 否则会形成 kill→恢复→kill 死循环。与 Swift 实现对齐。
		isCrash := !intentional && status != 0
		level := "info"
		if isCrash {
			level = "error"
		}
		m.addEvent(fmt.Sprintf("frpc 进程已退出，状态码: %d", status), level)

		// Auto-recover only on a genuine crash (non-intentional && status != 0).
		// An intentional stop (status carries a signal value) must not recover.
		if isCrash {
			go func() {
				time.Sleep(2 * time.Second) // 防抖，与 Swift 对齐
				m.recoverConnection(fmt.Sprintf("frpc 异常退出（状态码 %d），正在自动重启", status))
			}()
		}
	}

	return m, nil
}

// IsConfigured returns true if a server config exists.
func (m *Manager) IsConfigured() bool { return m.cfg.IsConfigured() }

// IsRunning returns whether frpc is currently running.
func (m *Manager) IsRunning() bool {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.isFrpcRunning
}

// IsConnected returns whether tunnels are healthy (mirrors Swift isConnected).
func (m *Manager) IsConnected() bool {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.isConnected
}

// PID returns the current frpc process ID, or 0 if not running.
func (m *Manager) PID() int { return m.frpc.PID() }

// Settings returns the current app settings.
func (m *Manager) Settings() *config.AppSettings {
	m.mu.RLock()
	defer m.mu.RUnlock()
	cp := *m.settings
	return &cp
}

// SaveSettings persists app settings.
func (m *Manager) SaveSettings(s *config.AppSettings) error {
	m.mu.Lock()
	m.settings = s
	m.mu.Unlock()
	if err := m.cfg.SaveSettings(s); err != nil {
		return err
	}
	// If polling is active, restart with the new interval.
	if m.IsRunning() {
		m.restartStatusPolling()
	}
	return nil
}

// SaveServerConfig persists and regenerates frpc.toml.
func (m *Manager) SaveServerConfig(serverCfg *config.ServerConfig) error {
	if err := m.cfg.SaveServerConfig(serverCfg); err != nil {
		return err
	}
	m.regenerateFrpcConfig()
	return nil
}

// GetTunnels returns a copy of all tunnels (with runtime status).
func (m *Manager) GetTunnels() []config.Tunnel {
	m.mu.RLock()
	defer m.mu.RUnlock()
	result := make([]config.Tunnel, len(m.tunnels))
	copy(result, m.tunnels)
	return result
}

// GetEvents returns a copy of the recent event log (newest first).
func (m *Manager) GetEvents() []config.EventLog {
	m.mu.RLock()
	defer m.mu.RUnlock()
	result := make([]config.EventLog, len(m.events))
	copy(result, m.events)
	return result
}

func (m *Manager) addEvent(message, level string) {
	if level == "" {
		level = "info"
	}
	m.mu.Lock()
	evt := config.EventLog{ID: uuid.NewString(), Timestamp: time.Now(), Message: message, Level: level}
	m.events = append([]config.EventLog{evt}, m.events...)
	if len(m.events) > maxEventLogSize {
		m.events = m.events[:maxEventLogSize]
	}
	m.mu.Unlock()
	m.logger.Printf("[%s] %s", level, message)
}

// AddEvent records a user-visible event from API/UI orchestration layers.
func (m *Manager) AddEvent(message, level string) {
	m.addEvent(message, level)
}

// ClearEvents empties the event log.
func (m *Manager) ClearEvents() {
	m.mu.Lock()
	m.events = nil
	m.mu.Unlock()
}

// AddTunnel adds a new tunnel.
func (m *Manager) AddTunnel(t config.Tunnel) error {
	m.mu.Lock()
	if t.ID == "" {
		t.ID = uuid.NewString()
	}
	now := time.Now()
	t.CreatedAt = now
	t.UpdatedAt = now
	serverCfg := m.loadServerConfigLocked()
	t.Subdomain = config.SubdomainNormalize(t.Subdomain, serverSubdomainHost(serverCfg))
	if t.Enabled {
		t.RuntimeStatus = string(config.StatusWaitStart)
	} else {
		t.RuntimeStatus = string(config.StatusClosed)
		t.ErrorMessage = ""
	}
	m.tunnels = append(m.tunnels, t)
	if err := m.cfg.SaveTunnels(m.tunnels); err != nil {
		m.mu.Unlock()
		return err
	}
	m.mu.Unlock()

	m.regenerateFrpcConfig()
	if t.Enabled && m.adminAPI != nil && m.IsRunning() {
		if err := m.adminAPI.CreateProxy(m.ctx, t.ToProxyDefinition(serverCfg)); err != nil {
			m.addEvent(fmt.Sprintf("创建隧道 %q 失败: %v", t.Name, err), "error")
			return err
		}
		m.adminAPI.Reload(m.ctx)
	}
	m.addEvent(fmt.Sprintf("隧道 %q 已创建", t.Name), "info")
	return nil
}

// UpdateTunnel updates an existing tunnel.
func (m *Manager) UpdateTunnel(t config.Tunnel) error {
	m.mu.Lock()
	oldName := ""
	oldEnabled := false
	found := false
	serverCfg := m.loadServerConfigLocked()
	t.Subdomain = config.SubdomainNormalize(t.Subdomain, serverSubdomainHost(serverCfg))
	for i, existing := range m.tunnels {
		if existing.ID == t.ID {
			oldName = existing.Name
			oldEnabled = existing.Enabled
			found = true
			t.UpdatedAt = time.Now()
			m.tunnels[i] = t
			break
		}
	}
	if !found {
		m.mu.Unlock()
		return fmt.Errorf("tunnel not found: %s", t.ID)
	}
	if err := m.cfg.SaveTunnels(m.tunnels); err != nil {
		m.mu.Unlock()
		return err
	}
	m.mu.Unlock()

	m.regenerateFrpcConfig()
	if m.adminAPI != nil && m.IsRunning() {
		if !t.Enabled {
			if oldEnabled {
				m.adminAPI.DeleteProxy(m.ctx, oldName)
				m.adminAPI.Reload(m.ctx)
			}
			m.addEvent(fmt.Sprintf("隧道 %q 已更新", t.Name), "info")
			return nil
		}
		if oldEnabled && oldName != "" && oldName == t.Name {
			if err := m.adminAPI.UpdateProxy(m.ctx, t.ToProxyDefinition(serverCfg)); err != nil {
				m.addEvent(fmt.Sprintf("更新隧道 %q 失败: %v", t.Name, err), "error")
				return err
			}
		} else {
			if oldEnabled && oldName != "" && oldName != t.Name {
				m.adminAPI.DeleteProxy(m.ctx, oldName)
			}
			if err := m.adminAPI.CreateProxy(m.ctx, t.ToProxyDefinition(serverCfg)); err != nil {
				if !frpc.IsHTTPConflict(err) {
					m.addEvent(fmt.Sprintf("更新隧道 %q 失败: %v", t.Name, err), "error")
					return err
				}
			}
		}
		if err := m.adminAPI.Reload(m.ctx); err != nil {
			m.addEvent(fmt.Sprintf("重载隧道配置失败: %v", err), "warning")
		}
	}
	m.addEvent(fmt.Sprintf("隧道 %q 已更新", t.Name), "info")
	return nil
}

// DeleteTunnel removes a tunnel by ID.
func (m *Manager) DeleteTunnel(id string) error {
	m.mu.Lock()
	var name string
	for i, t := range m.tunnels {
		if t.ID == id {
			name = t.Name
			m.tunnels = append(m.tunnels[:i], m.tunnels[i+1:]...)
			break
		}
	}
	if err := m.cfg.SaveTunnels(m.tunnels); err != nil {
		m.mu.Unlock()
		return err
	}
	m.mu.Unlock()

	if name == "" {
		return nil
	}
	m.regenerateFrpcConfig()
	if m.adminAPI != nil && m.IsRunning() {
		m.adminAPI.DeleteProxy(m.ctx, name)
		m.adminAPI.Reload(m.ctx)
	}
	m.addEvent(fmt.Sprintf("隧道 %q 已删除", name), "info")
	return nil
}

// ToggleTunnel enables or disables a tunnel.
func (m *Manager) ToggleTunnel(id string, enabled bool) error {
	m.mu.Lock()
	var t config.Tunnel
	found := false
	for i, existing := range m.tunnels {
		if existing.ID == id {
			m.tunnels[i].Enabled = enabled
			m.tunnels[i].UpdatedAt = time.Now()
			if enabled {
				m.tunnels[i].RuntimeStatus = string(config.StatusWaitStart)
			} else {
				m.tunnels[i].RuntimeStatus = string(config.StatusClosed)
				m.tunnels[i].ErrorMessage = ""
			}
			t = m.tunnels[i]
			found = true
			break
		}
	}
	if err := m.cfg.SaveTunnels(m.tunnels); err != nil {
		m.mu.Unlock()
		return err
	}
	serverCfg := m.loadServerConfigLocked()
	m.mu.Unlock()

	if !found {
		return fmt.Errorf("tunnel not found: %s", id)
	}
	m.regenerateFrpcConfig()
	if m.adminAPI != nil && m.IsRunning() {
		if enabled {
			m.adminAPI.CreateProxy(m.ctx, t.ToProxyDefinition(serverCfg))
			m.addEvent(fmt.Sprintf("隧道 %q 已启用", t.Name), "info")
		} else {
			m.adminAPI.DeleteProxy(m.ctx, t.Name)
			m.addEvent(fmt.Sprintf("隧道 %q 已禁用", t.Name), "info")
		}
		m.adminAPI.Reload(m.ctx)
	}
	return nil
}

func (m *Manager) loadServerConfigLocked() *config.ServerConfig {
	cfg, err := m.cfg.LoadServerConfig()
	if err != nil {
		return nil
	}
	return cfg
}

func serverSubdomainHost(cfg *config.ServerConfig) string {
	if cfg == nil {
		return ""
	}
	return cfg.SubDomainHost
}

// Start starts frpc with current configuration (mirrors Swift start()).
func (m *Manager) Start() error {
	if m.IsRunning() {
		return nil
	}
	if !m.IsConfigured() {
		return fmt.Errorf("server not configured")
	}

	serverCfg, err := m.cfg.LoadServerConfig()
	if err != nil {
		return fmt.Errorf("no server config: %w", err)
	}

	m.adminAPI = frpc.NewAdminAPI(serverCfg)
	if ok, _ := m.adminAPI.HealthCheck(m.ctx); ok {
		m.mu.Lock()
		m.isFrpcRunning = true
		m.ownsFrpc = false
		m.mu.Unlock()
		m.startStatusPolling()
		m.addEvent("检测到已有 frpc Admin API，已接管状态监控", "info")
		return nil
	}

	m.mu.Lock()
	m.isConnected = false
	m.mu.Unlock()

	m.addEvent("正在启动隧道管理器...", "info")

	if err := m.cfg.GenerateFrpcToml(serverCfg, m.copyTunnelsLocked()); err != nil {
		return err
	}
	configPath := m.cfg.FrpcConfigPath()
	if err := m.frpc.Start(m.ctx, configPath); err != nil {
		m.addEvent(fmt.Sprintf("启动 frpc 失败: %v", err), "error")
		return err
	}

	m.mu.Lock()
	m.isFrpcRunning = true
	m.ownsFrpc = true
	m.mu.Unlock()

	if err := m.waitForAdminAPI(); err != nil {
		m.addEvent(fmt.Sprintf("Admin API 未就绪，启动未完成: %v", err), "error")
		m.frpc.StopImmediately()
		m.mu.Lock()
		m.isFrpcRunning = false
		m.ownsFrpc = false
		m.mu.Unlock()
		return err
	}

	// Restore proxies.
	m.mu.RLock()
	tunnels := make([]config.Tunnel, len(m.tunnels))
	copy(tunnels, m.tunnels)
	m.mu.RUnlock()

	restored := false
	var failures []string
	for _, t := range tunnels {
		if !t.Enabled {
			continue
		}
		if err := m.adminAPI.CreateProxy(m.ctx, t.ToProxyDefinition(serverCfg)); err != nil {
			if frpc.IsHTTPConflict(err) {
				restored = true
				continue
			}
			failures = append(failures, t.Name)
			m.addEvent(fmt.Sprintf("恢复隧道 %q 失败: %v", t.Name, err), "warning")
		} else {
			restored = true
		}
	}
	if restored {
		if err := m.adminAPI.Reload(m.ctx); err != nil {
			m.addEvent(fmt.Sprintf("重载隧道配置失败: %v", err), "warning")
		}
	}
	if len(failures) > 0 {
		m.addEvent(fmt.Sprintf("部分隧道恢复失败，等待自动重连: %s", joinNames(failures)), "warning")
	}

	m.startStatusPolling()
	m.addEvent("隧道管理器已启动，正在检测外部可达性", "info")
	return nil
}

// Stop stops frpc and polling.
func (m *Manager) Stop() {
	m.stopStatusPolling()
	m.mu.RLock()
	ownsFrpc := m.ownsFrpc
	wasRunning := m.isFrpcRunning
	adminAPI := m.adminAPI
	m.mu.RUnlock()
	if wasRunning {
		if ownsFrpc && m.frpc.IsRunning() {
			m.frpc.Stop(5 * time.Second)
		} else if !ownsFrpc && adminAPI != nil {
			if err := adminAPI.StopFrpc(m.ctx); err != nil {
				m.addEvent(fmt.Sprintf("停止外部 frpc 失败: %v", err), "warning")
			}
		}
	}
	m.mu.Lock()
	m.isFrpcRunning = false
	m.isConnected = false
	m.ownsFrpc = false
	for i := range m.tunnels {
		if m.tunnels[i].Enabled {
			m.tunnels[i].RuntimeStatus = string(config.StatusClosed)
		}
	}
	m.mu.Unlock()
	m.addEvent("隧道管理器已停止", "info")
}

// StopImmediately kills frpc without waiting.
func (m *Manager) StopImmediately() {
	m.stopStatusPolling()
	m.mu.RLock()
	ownsFrpc := m.ownsFrpc
	m.mu.RUnlock()
	if ownsFrpc {
		m.frpc.StopImmediately()
	}
	m.mu.Lock()
	m.isFrpcRunning = false
	m.isConnected = false
	m.ownsFrpc = false
	m.mu.Unlock()
}

// Restart stops then starts frpc.
func (m *Manager) Restart() error {
	m.Stop()
	time.Sleep(1 * time.Second)
	return m.Start()
}

func (m *Manager) waitForAdminAPI() error {
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if ok, _ := m.adminAPI.HealthCheck(m.ctx); ok {
			return nil
		}
		time.Sleep(500 * time.Millisecond)
	}
	return fmt.Errorf("admin API not ready")
}

func (m *Manager) regenerateFrpcConfig() {
	if !m.IsConfigured() {
		return
	}
	serverCfg, err := m.cfg.LoadServerConfig()
	if err != nil {
		return
	}
	m.cfg.GenerateFrpcToml(serverCfg, m.copyTunnelsLocked())
}

func (m *Manager) copyTunnelsLocked() []config.Tunnel {
	cp := make([]config.Tunnel, len(m.tunnels))
	copy(cp, m.tunnels)
	return cp
}

// --- Status polling, probe, recovery (mirrors Swift pollStatus/recover) ---

func (m *Manager) startStatusPolling() {
	m.stopStatusPolling()
	interval := clampInterval(m.settings.StatusPollingInterval, 3, 30)
	ticker := time.NewTicker(time.Duration(interval) * time.Second)
	m.statusTimer = ticker
	go func() {
		m.pollStatus()
		for range ticker.C {
			m.pollStatus()
		}
	}()
}

func (m *Manager) restartStatusPolling() {
	if m.statusTimer != nil {
		m.startStatusPolling()
	}
}

func (m *Manager) stopStatusPolling() {
	if m.statusTimer != nil {
		m.statusTimer.Stop()
		m.statusTimer = nil
	}
}

func (m *Manager) pollStatus() {
	m.mu.Lock()
	if m.isPollingStatus {
		m.mu.Unlock()
		return
	}
	m.isPollingStatus = true
	m.mu.Unlock()
	defer func() {
		m.mu.Lock()
		m.isPollingStatus = false
		m.mu.Unlock()
	}()

	if m.adminAPI == nil {
		m.recordConnectivityFailure("Admin API 未初始化")
		return
	}
	m.mu.RLock()
	ownsFrpc := m.ownsFrpc
	m.mu.RUnlock()
	if ownsFrpc && !m.frpc.IsRunning() {
		m.mu.Lock()
		m.isFrpcRunning = false
		m.mu.Unlock()
		m.recordConnectivityFailure("frpc 进程已退出")
		return
	}

	statusResp, err := m.adminAPI.GetStatus(m.ctx)
	if err != nil {
		m.recordConnectivityFailure(fmt.Sprintf("状态检测失败: %v", err))
		return
	}

	// Update each tunnel's runtime status from the response.
	m.mu.Lock()
	for i := range m.tunnels {
		t := m.tunnels[i]
		if statuses, ok := statusResp[string(t.Type)]; ok {
			for _, ps := range statuses {
				if ps.Name == t.Name {
					m.tunnels[i].RuntimeStatus = string(config.StatusFromFrpcPhase(ps.Status))
					if ps.Err != "" {
						m.tunnels[i].ErrorMessage = ps.Err
					} else {
						m.tunnels[i].ErrorMessage = ""
					}
					m.tunnels[i].RemoteAddr = ps.RemoteAddr
					break
				}
			}
		} else if t.Enabled {
			m.tunnels[i].RuntimeStatus = string(config.StatusCheckFailed)
			m.tunnels[i].ErrorMessage = "frpc 未返回该隧道状态"
		}
	}
	// Snapshot enabled tunnels for health evaluation.
	tunnelsCopy := make([]config.Tunnel, len(m.tunnels))
	copy(tunnelsCopy, m.tunnels)
	m.mu.Unlock()

	enabled := filterEnabled(tunnelsCopy)
	var unhealthy []string
	var transitional []string
	for _, t := range enabled {
		if isTransitionalStatus(t.RuntimeStatus) && t.ErrorMessage == "" {
			transitional = append(transitional, t.Name)
			continue
		}
		if t.RuntimeStatus != string(config.StatusRunning) || t.ErrorMessage != "" {
			unhealthy = append(unhealthy, t.Name)
		}
	}
	if len(transitional) > 0 && len(unhealthy) == 0 {
		m.mu.Lock()
		m.isFrpcRunning = true
		m.isConnected = false
		m.mu.Unlock()
		return
	}
	if len(unhealthy) > 0 {
		m.recordConnectivityFailure(fmt.Sprintf("隧道状态异常: %s", joinNames(unhealthy)))
		return
	}

	if m.shouldProbeReachability() {
		failed := m.probeReachability(enabled)
		m.mu.Lock()
		m.lastReachabilityProbeAt = time.Now()
		m.mu.Unlock()
		if len(failed) > 0 {
			m.recordConnectivityFailure(fmt.Sprintf("外网探活失败: %s", joinNames(failed)))
			return
		}
	}

	m.mu.Lock()
	m.consecutiveFailures = 0
	m.isFrpcRunning = true
	m.isConnected = true
	m.mu.Unlock()
}

func isTransitionalStatus(status string) bool {
	return status == string(config.StatusNew) || status == string(config.StatusWaitStart)
}

func (m *Manager) shouldProbeReachability() bool {
	m.mu.RLock()
	defer m.mu.RUnlock()
	interval := time.Duration(clampInterval(m.settings.RemoteReachabilityInterval, 30, 600)) * time.Second
	return time.Since(m.lastReachabilityProbeAt) >= interval
}

func (m *Manager) probeReachability(tunnels []config.Tunnel) []string {
	var failed []string
	for _, t := range tunnels {
		switch m.probe.Check(t) {
		case frpc.ReachabilityReachable, frpc.ReachabilitySkipped:
			continue
		case frpc.ReachabilityUnreachable:
			m.mu.Lock()
			for i := range m.tunnels {
				if m.tunnels[i].ID == t.ID {
					m.tunnels[i].RuntimeStatus = string(config.StatusCheckFailed)
					m.tunnels[i].ErrorMessage = "外网探活失败：无法连接远程地址"
					break
				}
			}
			m.mu.Unlock()
			failed = append(failed, t.Name)
		}
	}
	return failed
}

func (m *Manager) recordConnectivityFailure(reason string) {
	m.mu.Lock()
	m.consecutiveFailures++
	m.isConnected = false
	shouldRecover := m.consecutiveFailures >= maxConsecutiveFailuresBeforeRecovery
	m.mu.Unlock()

	if m.consecutiveFailures == 1 {
		m.addEvent(fmt.Sprintf("连接检测失败: %s", reason), "warning")
	}
	if shouldRecover {
		m.recoverConnection(reason)
	}
}

func (m *Manager) recoverConnection(reason string) {
	m.mu.Lock()
	if m.isRecovering {
		m.mu.Unlock()
		return
	}
	if time.Since(m.lastRecoveryAt) < recoveryCooldown {
		m.mu.Unlock()
		return
	}
	m.isRecovering = true
	m.lastRecoveryAt = time.Now()
	m.mu.Unlock()

	defer func() {
		m.mu.Lock()
		m.isRecovering = false
		m.mu.Unlock()
	}()

	m.addEvent(fmt.Sprintf("连接连续异常，正在自动重连: %s", reason), "warning")
	m.stopStatusPolling()
	m.mu.RLock()
	ownsFrpc := m.ownsFrpc
	m.mu.RUnlock()
	if ownsFrpc {
		m.frpc.StopImmediately()
	}
	m.mu.Lock()
	m.isFrpcRunning = false
	m.isConnected = false
	m.ownsFrpc = false
	m.consecutiveFailures = 0
	m.mu.Unlock()
	time.Sleep(1 * time.Second)
	if err := m.Start(); err != nil {
		m.addEvent(fmt.Sprintf("自动重连失败: %v", err), "error")
	}
}

func joinNames(names []string) string {
	out := ""
	for i, n := range names {
		if i > 0 {
			out += ", "
		}
		out += n
	}
	return out
}

func filterEnabled(tunnels []config.Tunnel) []config.Tunnel {
	var out []config.Tunnel
	for _, t := range tunnels {
		if t.Enabled {
			out = append(out, t)
		}
	}
	return out
}

func clampInterval(v, min, max float64) float64 {
	if v < min {
		return min
	}
	if v > max {
		return max
	}
	return v
}
