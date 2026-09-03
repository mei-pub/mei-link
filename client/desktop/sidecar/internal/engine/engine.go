package engine

import (
	"context"
	"fmt"
	"sync"

	"github.com/fatedier/frp/client"
	"github.com/fatedier/frp/pkg/config/v1"
	"github.com/fatedier/frp/pkg/config/source"
	"github.com/samber/lo"
)

// Engine wraps frp's client.Service as an in-process library, eliminating the
// need for a separate frpc binary that antivirus software may quarantine.
//
// The engine accepts Meilink's own config types (ServerConfig + Tunnel) and
// translates them to frp's v1 config structs internally. Callers (desktop
// sidecar, meilink-tunnel standalone binary) interact only with Engine, never
// touching frp types directly.
type Engine struct {
	mu       sync.Mutex
	svc      *client.Service
	cancel   context.CancelFunc
	doneCh   chan struct{}
	running  bool

	// Engine configuration (copied from EngineConfig in New).
	serverAddr    string
	serverPort    int
	authToken     string
	tlsEnabled    bool
	adminAddr     string
	adminPort     int
	adminUser     string
	adminPassword string
	logLevel      string

	// configSource holds the proxy/visitor configs that frp loads at startup
	// and reloads on UpdateProxies.
	configSource *source.ConfigSource
	aggregator   *source.Aggregator

	// storePath is the file path for frp's store.json (persisted proxy state).
	storePath string
	storeSource *source.StoreSource

	// OnLog is called for informational log lines from the engine.
	OnLog func(msg string)
	// OnError is called for error-level log lines.
	OnError func(msg string)
}

// EngineConfig holds the parameters needed to create and start an Engine.
type EngineConfig struct {
	ServerAddr    string
	ServerPort    int
	AuthToken     string
	TLSEnabled    bool
	AdminAddr     string // default "127.0.0.1"
	AdminPort     int    // 0 = no admin API
	AdminUser     string
	AdminPassword string
	StorePath     string // path to store.json for proxy persistence
	LogLevel      string // "trace"|"debug"|"info"|"warn"|"error", default "info"
}

// New creates an Engine from the given config. The engine is not started;
// call Start to launch it.
func New(cfg EngineConfig) *Engine {
	cs := source.NewConfigSource()
	agg := source.NewAggregator(cs)
	var storeSrc *source.StoreSource
	if cfg.StorePath != "" {
		ss, err := source.NewStoreSource(source.StoreSourceConfig{Path: cfg.StorePath})
		if err == nil {
			storeSrc = ss
			agg.SetStoreSource(ss)
		}
	}
	adminAddr := cfg.AdminAddr
	if adminAddr == "" {
		adminAddr = "127.0.0.1"
	}
	logLevel := cfg.LogLevel
	if logLevel == "" {
		logLevel = "info"
	}
	return &Engine{
		configSource:  cs,
		aggregator:    agg,
		storePath:     cfg.StorePath,
		storeSource:   storeSrc,
		serverAddr:    cfg.ServerAddr,
		serverPort:    cfg.ServerPort,
		authToken:     cfg.AuthToken,
		tlsEnabled:    cfg.TLSEnabled,
		adminAddr:     adminAddr,
		adminPort:     cfg.AdminPort,
		adminUser:     cfg.AdminUser,
		adminPassword: cfg.AdminPassword,
		logLevel:      logLevel,
	}
}

// Start launches the frp client service in a background goroutine.
// It returns once the service is created; the actual login to frps happens
// asynchronously inside frp. Call IsRunning to check connection state.
func (e *Engine) Start(ctx context.Context) error {
	e.mu.Lock()
	if e.running {
		e.mu.Unlock()
		return fmt.Errorf("engine already running")
	}
	e.mu.Unlock()

	common := e.buildCommonConfig()

	svc, err := client.NewService(client.ServiceOptions{
		Common:                 &common,
		ConfigSourceAggregator: e.aggregator,
	})
	if err != nil {
		return fmt.Errorf("create frp service: %w", err)
	}

	childCtx, cancel := context.WithCancel(ctx)
	doneCh := make(chan struct{})

	e.mu.Lock()
	e.svc = svc
	e.cancel = cancel
	e.doneCh = doneCh
	e.running = true
	e.mu.Unlock()

	go func() {
		defer close(doneCh)
		if err := svc.Run(childCtx); err != nil {
			e.logError(fmt.Sprintf("frp service exited: %v", err))
		}
		e.mu.Lock()
		e.running = false
		e.svc = nil
		e.cancel = nil
		e.mu.Unlock()
	}()

	return nil
}

// Stop gracefully shuts down the engine.
func (e *Engine) Stop() {
	e.mu.Lock()
	svc := e.svc
	cancel := e.cancel
	doneCh := e.doneCh
	e.mu.Unlock()

	if svc == nil || cancel == nil {
		return
	}
	svc.Close()
	cancel()
	if doneCh != nil {
		<-doneCh
	}
}

// IsRunning returns true if the frp service is active.
func (e *Engine) IsRunning() bool {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.running
}

// UpdateProxies replaces all proxy configurations atomically. The frp service
// picks up the new config immediately without restart.
func (e *Engine) UpdateProxies(proxies []v1.ProxyConfigurer) error {
	e.mu.Lock()
	svc := e.svc
	e.mu.Unlock()

	if svc == nil {
		return fmt.Errorf("engine not running")
	}
	return svc.UpdateAllConfigurer(proxies, nil)
}

// SetProxies replaces all proxies in the config source (used before Start or
// for pre-loading proxies that will be picked up on the next reload).
func (e *Engine) SetProxies(proxies []v1.ProxyConfigurer) error {
	return e.configSource.ReplaceAll(proxies, nil)
}

// GetProxyStatus returns the working status of a proxy by name.
func (e *Engine) GetProxyStatus(name string) (status string, err string, ok bool) {
	e.mu.Lock()
	svc := e.svc
	e.mu.Unlock()

	if svc == nil {
		return "", "", false
	}
	exporter := svc.StatusExporter()
	s, found := exporter.GetProxyStatus(name)
	if !found {
		return "", "", false
	}
	return s.Phase, s.Err, true
}

// Done returns a channel that is closed when the engine stops.
func (e *Engine) Done() <-chan struct{} {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.doneCh
}

// buildCommonConfig converts EngineConfig to frp's ClientCommonConfig.
func (e *Engine) buildCommonConfig() v1.ClientCommonConfig {
	tlsEnable := lo.ToPtr(e.tlsEnabled)
	tcpMux := lo.ToPtr(true)

	cfg := v1.ClientCommonConfig{
		Auth: v1.AuthClientConfig{
			Method: v1.AuthMethod("token"),
			Token:  e.authToken,
		},
		ServerAddr:    e.serverAddr,
		ServerPort:    e.serverPort,
		LoginFailExit: lo.ToPtr(false),
		Log: v1.LogConfig{
			To:    "console",
			Level: e.logLevel,
		},
		WebServer: v1.WebServerConfig{
			Addr:     e.adminAddr,
			Port:     e.adminPort,
			User:     e.adminUser,
			Password: e.adminPassword,
		},
		Transport: v1.ClientTransportConfig{
			PoolCount:               5,
			TCPMux:                  tcpMux,
			TCPMuxKeepaliveInterval: 30,
			TLS: v1.TLSClientConfig{
				Enable: tlsEnable,
			},
		},
	}

	if e.storePath != "" {
		cfg.Metadatas = map[string]string{}
	}

	cfg.Complete()
	return cfg
}

func (e *Engine) logInfo(msg string) {
	if e.OnLog != nil {
		e.OnLog(msg)
	}
}

func (e *Engine) logError(msg string) {
	if e.OnError != nil {
		e.OnError(msg)
	}
}
