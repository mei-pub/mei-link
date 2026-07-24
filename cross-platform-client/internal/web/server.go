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

	"github.com/meilink/client/internal/config"
	"github.com/meilink/client/internal/tunnel"
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
	mux.HandleFunc("/api/tunnels", s.handleTunnels)
	mux.HandleFunc("/api/tunnels/", s.handleTunnelAction)
	mux.HandleFunc("/api/control/", s.handleControl)
	mux.HandleFunc("/api/events", s.handleEvents)
	mux.HandleFunc("/api/settings", s.handleSettings)
	return mux
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

func formatSeconds(v float64) string {
	if v == float64(int64(v)) {
		return strconv.FormatInt(int64(v), 10)
	}
	return strconv.FormatFloat(v, 'f', -1, 64)
}
