package tunnel

import (
	"fmt"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/meilink/client/internal/config"
)

func TestStartAttachesToExistingAdminAPIWithoutStartingFrpc(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("HOME", t.TempDir())

	fakeFrpcPath := filepath.Join(dir, "frpc")
	if err := os.WriteFile(fakeFrpcPath, []byte("#!/bin/sh\nsleep 60\n"), 0o755); err != nil {
		t.Fatal(err)
	}

	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	adminPort := ln.Addr().(*net.TCPAddr).Port

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	mux.HandleFunc("/api/status", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, `{}`)
	})
	stopCalls := 0
	mux.HandleFunc("/api/stop", func(w http.ResponseWriter, r *http.Request) {
		stopCalls++
		w.WriteHeader(http.StatusOK)
	})
	server := &http.Server{Handler: mux}
	go server.Serve(ln)
	defer server.Close()

	cfgMgr, err := config.NewManager(dir)
	if err != nil {
		t.Fatal(err)
	}
	if err := cfgMgr.SaveServerConfig(&config.ServerConfig{
		ServerAddr:    "example.test",
		ServerPort:    7000,
		AuthToken:     "token",
		SubDomainHost: "example.test",
		TLSEnabled:    true,
		AdminPort:     adminPort,
		AdminUser:     "admin",
		AdminPassword: "admin",
	}); err != nil {
		t.Fatal(err)
	}

	mgr, err := NewManager(dir)
	if err != nil {
		t.Fatal(err)
	}
	defer mgr.Stop()

	if err := mgr.Start(); err != nil {
		t.Fatal(err)
	}
	if !mgr.IsRunning() {
		t.Fatal("manager should report running after attaching to existing admin API")
	}
	if got := mgr.PID(); got != 0 {
		t.Fatalf("PID = %d, want 0 for externally managed frpc", got)
	}

	mgr.Stop()
	if stopCalls != 1 {
		t.Fatalf("external frpc stop calls = %d, want 1", stopCalls)
	}
}

func TestStartDoesNotWarnForTransientWaitStartStatus(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("HOME", t.TempDir())

	fakeFrpcPath := filepath.Join(dir, "frpc")
	if err := os.WriteFile(fakeFrpcPath, []byte("#!/bin/sh\nsleep 60\n"), 0o755); err != nil {
		t.Fatal(err)
	}

	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	adminPort := ln.Addr().(*net.TCPAddr).Port

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	mux.HandleFunc("/api/status", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, `{"http":[{"name":"admin","type":"http","status":"wait start"}]}`)
	})
	mux.HandleFunc("/api/stop", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	server := &http.Server{Handler: mux}
	go server.Serve(ln)
	defer server.Close()

	cfgMgr, err := config.NewManager(dir)
	if err != nil {
		t.Fatal(err)
	}
	if err := cfgMgr.SaveServerConfig(&config.ServerConfig{
		ServerAddr:    "example.test",
		ServerPort:    7000,
		AuthToken:     "token",
		SubDomainHost: "example.test",
		TLSEnabled:    true,
		AdminPort:     adminPort,
		AdminUser:     "admin",
		AdminPassword: "admin",
	}); err != nil {
		t.Fatal(err)
	}
	if err := cfgMgr.SaveTunnels([]config.Tunnel{{
		ID:            "11111111-1111-1111-1111-111111111111",
		Name:          "admin",
		Type:          config.TunnelHTTP,
		LocalIP:       "127.0.0.1",
		LocalPort:     5173,
		Subdomain:     "admin",
		Enabled:       true,
		RuntimeStatus: string(config.StatusWaitStart),
	}}); err != nil {
		t.Fatal(err)
	}

	mgr, err := NewManager(dir)
	if err != nil {
		t.Fatal(err)
	}
	defer mgr.Stop()

	if err := mgr.Start(); err != nil {
		t.Fatal(err)
	}
	if mgr.IsConnected() {
		t.Fatal("wait start should not be reported as connected")
	}
	time.Sleep(50 * time.Millisecond)
	for _, event := range mgr.GetEvents() {
		if event.Level == "warning" {
			t.Fatalf("wait start should not emit warning event: %#v", event)
		}
	}
}

func TestUpdateDisabledTunnelDoesNotTouchAdminAPI(t *testing.T) {
	mgr, counters := newRunningManagerWithStoreAPI(t, []config.Tunnel{{
		ID:            "11111111-1111-1111-1111-111111111111",
		Name:          "disabled",
		Type:          config.TunnelHTTP,
		LocalIP:       "127.0.0.1",
		LocalPort:     3000,
		Subdomain:     "disabled",
		Enabled:       false,
		RuntimeStatus: string(config.StatusClosed),
	}})
	defer mgr.Stop()
	counters.reset()

	err := mgr.UpdateTunnel(config.Tunnel{
		ID:            "11111111-1111-1111-1111-111111111111",
		Name:          "disabled-renamed",
		Type:          config.TunnelHTTP,
		LocalIP:       "127.0.0.1",
		LocalPort:     3001,
		Subdomain:     " disabled-renamed.example.test ",
		Enabled:       false,
		RuntimeStatus: string(config.StatusClosed),
	})
	if err != nil {
		t.Fatal(err)
	}
	if got := counters.storeCalls(); got != 0 {
		t.Fatalf("disabled update should not touch frpc store API, calls = %d", got)
	}
	tunnels := mgr.GetTunnels()
	if got := tunnels[0].Subdomain; got != "disabled-renamed" {
		t.Fatalf("updated subdomain = %q, want disabled-renamed", got)
	}
}

func TestUpdateTunnelCreatesProxyWhenEnablingDisabledTunnel(t *testing.T) {
	mgr, counters := newRunningManagerWithStoreAPI(t, []config.Tunnel{{
		ID:            "22222222-2222-2222-2222-222222222222",
		Name:          "was-disabled",
		Type:          config.TunnelHTTP,
		LocalIP:       "127.0.0.1",
		LocalPort:     3000,
		Subdomain:     "was-disabled",
		Enabled:       false,
		RuntimeStatus: string(config.StatusClosed),
	}})
	defer mgr.Stop()
	counters.reset()

	err := mgr.UpdateTunnel(config.Tunnel{
		ID:            "22222222-2222-2222-2222-222222222222",
		Name:          "was-disabled",
		Type:          config.TunnelHTTP,
		LocalIP:       "127.0.0.1",
		LocalPort:     3000,
		Subdomain:     "was-disabled",
		Enabled:       true,
		RuntimeStatus: string(config.StatusWaitStart),
	})
	if err != nil {
		t.Fatal(err)
	}
	if got := counters.post.Load(); got != 1 {
		t.Fatalf("enable via update should create proxy, POST calls = %d", got)
	}
	if got := counters.put.Load(); got != 0 {
		t.Fatalf("enable via update should not PUT missing proxy, PUT calls = %d", got)
	}
}

func TestUpdateEnabledTunnelRenameDeletesThenCreatesProxy(t *testing.T) {
	mgr, counters := newRunningManagerWithStoreAPI(t, []config.Tunnel{{
		ID:            "33333333-3333-3333-3333-333333333333",
		Name:          "old-name",
		Type:          config.TunnelHTTP,
		LocalIP:       "127.0.0.1",
		LocalPort:     3000,
		Subdomain:     "old-name",
		Enabled:       true,
		RuntimeStatus: string(config.StatusWaitStart),
	}})
	defer mgr.Stop()
	counters.reset()

	err := mgr.UpdateTunnel(config.Tunnel{
		ID:            "33333333-3333-3333-3333-333333333333",
		Name:          "new-name",
		Type:          config.TunnelHTTP,
		LocalIP:       "127.0.0.1",
		LocalPort:     3000,
		Subdomain:     "new-name",
		Enabled:       true,
		RuntimeStatus: string(config.StatusWaitStart),
	})
	if err != nil {
		t.Fatal(err)
	}
	if got := counters.delete.Load(); got != 1 {
		t.Fatalf("rename should delete old proxy, DELETE calls = %d", got)
	}
	if got := counters.post.Load(); got != 1 {
		t.Fatalf("rename should create new proxy, POST calls = %d", got)
	}
	if got := counters.put.Load(); got != 0 {
		t.Fatalf("rename should not PUT a missing new proxy, PUT calls = %d", got)
	}
}

type storeAPICounters struct {
	post   atomic.Int32
	put    atomic.Int32
	delete atomic.Int32
	reload atomic.Int32
}

func (c *storeAPICounters) reset() {
	c.post.Store(0)
	c.put.Store(0)
	c.delete.Store(0)
	c.reload.Store(0)
}

func (c *storeAPICounters) storeCalls() int32 {
	return c.post.Load() + c.put.Load() + c.delete.Load()
}

func newRunningManagerWithStoreAPI(t *testing.T, tunnels []config.Tunnel) (*Manager, *storeAPICounters) {
	t.Helper()
	dir := t.TempDir()
	t.Setenv("HOME", t.TempDir())
	if err := os.WriteFile(filepath.Join(dir, "frpc"), []byte("#!/bin/sh\nsleep 60\n"), 0o755); err != nil {
		t.Fatal(err)
	}

	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { ln.Close() })
	adminPort := ln.Addr().(*net.TCPAddr).Port

	counters := &storeAPICounters{}
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	mux.HandleFunc("/api/status", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, `{}`)
	})
	mux.HandleFunc("/api/reload", func(w http.ResponseWriter, r *http.Request) {
		counters.reload.Add(1)
		w.WriteHeader(http.StatusOK)
	})
	mux.HandleFunc("/api/stop", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	mux.HandleFunc("/api/store/proxies", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Errorf("unexpected %s %s", r.Method, r.URL.Path)
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		counters.post.Add(1)
		w.WriteHeader(http.StatusOK)
	})
	mux.HandleFunc("/api/store/proxies/", func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodPut:
			counters.put.Add(1)
			w.WriteHeader(http.StatusOK)
		case http.MethodDelete:
			counters.delete.Add(1)
			if strings.HasSuffix(r.URL.Path, "/old-name") {
				w.WriteHeader(http.StatusOK)
				return
			}
			w.WriteHeader(http.StatusOK)
		default:
			t.Errorf("unexpected %s %s", r.Method, r.URL.Path)
			w.WriteHeader(http.StatusMethodNotAllowed)
		}
	})
	server := &http.Server{Handler: mux}
	go server.Serve(ln)
	t.Cleanup(func() { server.Close() })

	cfgMgr, err := config.NewManager(dir)
	if err != nil {
		t.Fatal(err)
	}
	if err := cfgMgr.SaveServerConfig(&config.ServerConfig{
		ServerAddr:    "frp.example.test",
		ServerPort:    7000,
		AuthToken:     "token",
		SubDomainHost: "example.test",
		TLSEnabled:    true,
		AdminPort:     adminPort,
		AdminUser:     "admin",
		AdminPassword: "admin",
	}); err != nil {
		t.Fatal(err)
	}
	if err := cfgMgr.SaveTunnels(tunnels); err != nil {
		t.Fatal(err)
	}

	mgr, err := NewManager(dir)
	if err != nil {
		t.Fatal(err)
	}
	if err := mgr.Start(); err != nil {
		t.Fatal(err)
	}
	return mgr, counters
}
