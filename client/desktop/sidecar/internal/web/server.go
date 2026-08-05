package web

import (
	"context"
	"embed"
	"encoding/json"
	"html/template"
	"log"
	"net"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/meilink/desktop-sidecar/internal/autostart"
	"github.com/meilink/desktop-sidecar/internal/config"
	"github.com/meilink/desktop-sidecar/internal/frpc"
	"github.com/meilink/desktop-sidecar/internal/tunnel"
)

//go:embed templates/*
var templateFS embed.FS

// Server is the embedded web management UI.
type Server struct {
	manager  *tunnel.Manager
	cfg      *config.Manager
	server   *http.Server
	listener net.Listener
}

func (s *Server) buildMux() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/", s.handleIndex)
	mux.HandleFunc("/api/status", s.handleStatus)
	mux.HandleFunc("/api/server-config", s.handleServerConfig)
	mux.HandleFunc("/api/test-connection", s.handleTestConnection)
	mux.HandleFunc("/api/autostart", s.handleAutostart)
	mux.HandleFunc("/api/tunnels", s.handleTunnels)
	mux.HandleFunc("/api/tunnels/", s.handleTunnelAction)
	mux.HandleFunc("/api/control/", s.handleControl)
	mux.HandleFunc("/api/events", s.handleEvents)
	mux.HandleFunc("/api/settings", s.handleSettings)
	mux.HandleFunc("/api/domains", s.handleDomains)
	mux.HandleFunc("/api/bootstrap", s.handleBootstrap)
	// Wrap the mux in a CORS middleware. The sidecar listens on 127.0.0.1 only,
	// so cross-origin access from the Tauri webview (tauri://) or the Vite dev
	// server (http://localhost:17420) needs explicit CORS headers. Without
	// these, the browser's "Failed to fetch" error blocks the frontend from
	// reaching the sidecar even when apiBase is correctly resolved.
	return corsMiddleware(mux)
}

// corsMiddleware adds permissive CORS headers for localhost origins. The
// sidecar is bound to 127.0.0.1 so the risk of allowing all origins is
// minimal; this primarily unblocks the Vite dev server and the Tauri
// webview when Tauri's own CSP isn't enough (e.g. during development).
func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// NewServer creates a new web server.
func NewServer(manager *tunnel.Manager, cfg *config.Manager, listenAddr string) *Server {
	s := &Server{manager: manager, cfg: cfg}
	s.server = &http.Server{Addr: listenAddr, Handler: s.buildMux(), ReadHeaderTimeout: 5 * time.Second}
	return s
}

// NewServerWithListener creates a web server bound to a pre-existing listener
// (used by the sidecar mode, where the port is chosen by the OS).
func NewServerWithListener(manager *tunnel.Manager, cfg *config.Manager, ln net.Listener) *Server {
	s := &Server{manager: manager, cfg: cfg, listener: ln}
	s.server = &http.Server{Handler: s.buildMux(), ReadHeaderTimeout: 5 * time.Second}
	return s
}

// Start launches the web server.
func (s *Server) Start() error {
	go func() {
		var err error
		if s.listener != nil {
			err = s.server.Serve(s.listener)
		} else {
			log.Printf("Web UI listening on %s", s.server.Addr)
			err = s.server.ListenAndServe()
		}
		if err != nil && err != http.ErrServerClosed {
			log.Printf("web server error: %v", err)
		}
	}()
	return nil
}

// Stop gracefully shuts down the web server.
func (s *Server) Stop(ctx context.Context) error { return s.server.Shutdown(ctx) }

func (s *Server) handleIndex(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	tmpl, err := template.ParseFS(templateFS, "templates/index.html")
	if err != nil {
		http.Error(w, "template error", 500)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	tmpl.Execute(w, map[string]interface{}{"title": "Meilink"})
}

func (s *Server) handleStatus(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"configured": s.manager.IsConfigured(),
		"running":    s.manager.IsRunning(),
		"connected":  s.manager.IsConnected(),
		"pid":        s.manager.PID(),
	})
}

func (s *Server) handleServerConfig(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	switch r.Method {
	case http.MethodGet:
		cfg, err := s.cfg.LoadServerConfig()
		if err != nil {
			json.NewEncoder(w).Encode(map[string]interface{}{"configured": false})
			return
		}
		json.NewEncoder(w).Encode(cfg)
	case http.MethodPost:
		var cfg config.ServerConfig
		if err := json.NewDecoder(r.Body).Decode(&cfg); err != nil {
			http.Error(w, err.Error(), 400)
			return
		}
		if err := s.manager.SaveServerConfig(&cfg); err != nil {
			s.manager.AddEvent("保存配置失败: "+err.Error(), "error")
			http.Error(w, err.Error(), 500)
			return
		}
		s.manager.AddEvent("服务器配置已保存", "info")
		w.WriteHeader(http.StatusCreated)
	default:
		http.Error(w, "method not allowed", 405)
	}
}

func (s *Server) handleTunnels(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	switch r.Method {
	case http.MethodGet:
		json.NewEncoder(w).Encode(s.manager.GetTunnels())
	case http.MethodPost:
		var t config.Tunnel
		if err := json.NewDecoder(r.Body).Decode(&t); err != nil {
			http.Error(w, err.Error(), 400)
			return
		}
		if err := s.manager.AddTunnel(t); err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		w.WriteHeader(http.StatusCreated)
	case http.MethodPut:
		var t config.Tunnel
		if err := json.NewDecoder(r.Body).Decode(&t); err != nil {
			http.Error(w, err.Error(), 400)
			return
		}
		if err := s.manager.UpdateTunnel(t); err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		w.WriteHeader(http.StatusOK)
	case http.MethodDelete:
		id := r.URL.Query().Get("id")
		if id == "" {
			http.Error(w, "missing id", 400)
			return
		}
		if err := s.manager.DeleteTunnel(id); err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		w.WriteHeader(http.StatusOK)
	default:
		http.Error(w, "method not allowed", 405)
	}
}

// handleTunnelAction routes /api/tunnels/{id}/{action} (action = toggle).
func (s *Server) handleTunnelAction(w http.ResponseWriter, r *http.Request) {
	parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/api/tunnels/"), "/")
	if len(parts) != 2 {
		http.NotFound(w, r)
		return
	}
	id, action := parts[0], parts[1]
	switch action {
	case "toggle":
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", 405)
			return
		}
		var body struct {
			Enabled bool `json:"enabled"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			http.Error(w, err.Error(), 400)
			return
		}
		if err := s.manager.ToggleTunnel(id, body.Enabled); err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		w.WriteHeader(http.StatusOK)
	default:
		http.NotFound(w, r)
	}
}

// handleControl routes /api/control/{start|stop|restart}.
func (s *Server) handleControl(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", 405)
		return
	}
	action := strings.TrimPrefix(r.URL.Path, "/api/control/")
	switch action {
	case "start":
		if err := s.manager.Start(); err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
	case "stop":
		s.manager.Stop()
	case "restart":
		if err := s.manager.Restart(); err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
	default:
		http.NotFound(w, r)
		return
	}
	w.WriteHeader(http.StatusOK)
}

func (s *Server) handleTestConnection(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", 405)
		return
	}
	var body struct {
		Addr string `json:"addr"`
		Port int    `json:"port"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, err.Error(), 400)
		return
	}
	ok, msg := frpc.TestConnection(body.Addr, body.Port)
	resp := map[string]interface{}{"ok": ok}
	if !ok {
		resp["err"] = msg
	}
	json.NewEncoder(w).Encode(resp)
}

func (s *Server) handleAutostart(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	switch r.Method {
	case http.MethodGet:
		enabled, available := autostart.IsEnabled(), autostart.Available()
		json.NewEncoder(w).Encode(map[string]interface{}{
			"enabled":   enabled,
			"available": available,
		})
	case http.MethodPost:
		var body struct {
			Enabled bool `json:"enabled"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			http.Error(w, err.Error(), 400)
			return
		}
		if !autostart.Available() {
			http.Error(w, "当前平台不支持开机自启动", 501)
			return
		}
		var err error
		if body.Enabled {
			err = autostart.Enable()
		} else {
			err = autostart.Disable()
		}
		if err != nil {
			s.manager.AddEvent("设置自启动失败: "+err.Error(), "error")
			http.Error(w, err.Error(), 500)
			return
		}
		s.manager.AddEvent("开机自启动已"+map[bool]string{true: "启用", false: "禁用"}[body.Enabled], "info")
		w.WriteHeader(http.StatusOK)
	default:
		http.Error(w, "method not allowed", 405)
	}
}

func (s *Server) handleEvents(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method == http.MethodDelete {
		s.manager.ClearEvents()
		w.WriteHeader(http.StatusOK)
		return
	}
	json.NewEncoder(w).Encode(s.manager.GetEvents())
}

func (s *Server) handleSettings(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	switch r.Method {
	case http.MethodGet:
		json.NewEncoder(w).Encode(s.manager.Settings())
	case http.MethodPost:
		var st config.AppSettings
		if err := json.NewDecoder(r.Body).Decode(&st); err != nil {
			http.Error(w, err.Error(), 400)
			return
		}
		if err := s.manager.SaveSettings(&st); err != nil {
			s.manager.AddEvent("保存应用设置失败: "+err.Error(), "error")
			http.Error(w, err.Error(), 500)
			return
		}
		if st.MenuBarIconStyle != "" {
			s.manager.AddEvent("菜单栏图标已更新为 "+st.MenuBarIconStyle, "info")
		}
		if st.RemoteReachabilityInterval > 0 {
			s.manager.AddEvent(
				"远程探测间隔已更新为 "+formatSeconds(st.RemoteReachabilityInterval)+" 秒",
				"info",
			)
		}
		w.WriteHeader(http.StatusOK)
	default:
		http.Error(w, "method not allowed", 405)
	}
}

// handleDomains 代理客户端到服务端管理页的域名目录拉取。
// 读 server config 的 managementURL + domainAPIToken，调 tunnel.FetchDomains。
// 前端 GET /api/domains 调用此端点，不用知道管理页地址/token（由 sidecar 持有）。
// 失败返回 200 + {domains: [], error: "..."}，前端据 error 字段 fallback 到手填。
func (s *Server) handleDomains(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", 405)
		return
	}
	cfg, err := s.cfg.LoadServerConfig()
	if err != nil || cfg == nil {
		json.NewEncoder(w).Encode(map[string]interface{}{"domains": []interface{}{}, "error": "未配置服务器"})
		return
	}
	domains, err := tunnel.FetchDomains(cfg.ManagementURL, cfg.DomainAPIToken)
	if err != nil {
		json.NewEncoder(w).Encode(map[string]interface{}{"domains": []interface{}{}, "error": err.Error()})
		return
	}
	json.NewEncoder(w).Encode(map[string]interface{}{"domains": domains})
}

// handleBootstrap 代理客户端到服务端管理页的启动信息拉取。
// 前端 GET /api/bootstrap 调用此端点拉取 frps 连接信息，让 SetupView 只填管理页地址+token。
func (s *Server) handleBootstrap(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", 405)
		return
	}
	cfg, err := s.cfg.LoadServerConfig()
	if err != nil || cfg == nil {
		json.NewEncoder(w).Encode(map[string]interface{}{"error": "未配置服务器"})
		return
	}
	info, err := tunnel.FetchBootstrap(cfg.ManagementURL, cfg.DomainAPIToken)
	if err != nil {
		json.NewEncoder(w).Encode(map[string]interface{}{"error": err.Error()})
		return
	}
	json.NewEncoder(w).Encode(info)
}

func formatSeconds(v float64) string {
	if v == float64(int64(v)) {
		return strconv.FormatInt(int64(v), 10)
	}
	return strconv.FormatFloat(v, 'f', -1, 64)
}
