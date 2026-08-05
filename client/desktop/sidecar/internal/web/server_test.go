package web

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/meilink/desktop-sidecar/internal/config"
	"github.com/meilink/desktop-sidecar/internal/tunnel"
)

func TestTunnelAPIUsesSwiftCompatiblePersistenceAcrossCRUD(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("HOME", t.TempDir())
	if err := os.WriteFile(filepath.Join(dir, "frpc"), []byte("#!/bin/sh\nsleep 60\n"), 0o755); err != nil {
		t.Fatal(err)
	}

	manager, err := tunnel.NewManager(dir)
	if err != nil {
		t.Fatal(err)
	}
	cfgMgr, err := config.NewManager(dir)
	if err != nil {
		t.Fatal(err)
	}
	server := NewServer(manager, cfgMgr, "127.0.0.1:0")
	handler := server.buildMux()

	doJSON := func(method, path string, body string) *httptest.ResponseRecorder {
		req := httptest.NewRequest(method, path, bytes.NewBufferString(body))
		req.Header.Set("Content-Type", "application/json")
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		return rec
	}

	serverConfig := `{
		"serverAddr":"tunnel.example.test",
		"serverPort":7000,
		"authToken":"token",
		"subDomainHost":"tunnel.example.test",
		"tlsEnabled":true,
		"adminPort":7400,
		"adminUser":"admin",
		"adminPassword":"admin"
	}`
	if rec := doJSON(http.MethodPost, "/api/server-config", serverConfig); rec.Code != http.StatusCreated {
		t.Fatalf("POST /api/server-config status = %d body=%s", rec.Code, rec.Body.String())
	}

	newTunnel := `{
		"name":"web",
		"type":"http",
		"localIP":"127.0.0.1",
		"localPort":3000,
		"subdomain":"web",
		"enabled":true
	}`
	if rec := doJSON(http.MethodPost, "/api/tunnels", newTunnel); rec.Code != http.StatusCreated {
		t.Fatalf("POST /api/tunnels status = %d body=%s", rec.Code, rec.Body.String())
	}

	rec := doJSON(http.MethodGet, "/api/tunnels", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /api/tunnels status = %d body=%s", rec.Code, rec.Body.String())
	}
	var tunnels []config.Tunnel
	if err := json.Unmarshal(rec.Body.Bytes(), &tunnels); err != nil {
		t.Fatal(err)
	}
	if len(tunnels) != 1 {
		t.Fatalf("tunnel count = %d, want 1", len(tunnels))
	}
	id := tunnels[0].ID
	if got := tunnels[0].RuntimeStatus; got != string(config.StatusWaitStart) {
		t.Fatalf("created tunnel status = %q, want wait_start", got)
	}

	if rec := doJSON(http.MethodPost, "/api/tunnels/"+id+"/toggle", `{"enabled":false}`); rec.Code != http.StatusOK {
		t.Fatalf("POST toggle false status = %d body=%s", rec.Code, rec.Body.String())
	}
	updated := `{
		"id":"` + id + `",
		"name":"web-renamed",
		"type":"http",
		"localIP":"127.0.0.1",
		"localPort":3001,
		"subdomain":"web-renamed",
		"enabled":false,
		"status":"closed",
		"createdAt":"` + tunnels[0].CreatedAt.Format("2006-01-02T15:04:05Z07:00") + `",
		"updatedAt":"` + tunnels[0].UpdatedAt.Format("2006-01-02T15:04:05Z07:00") + `"
	}`
	if rec := doJSON(http.MethodPut, "/api/tunnels", updated); rec.Code != http.StatusOK {
		t.Fatalf("PUT /api/tunnels status = %d body=%s", rec.Code, rec.Body.String())
	}

	data, err := os.ReadFile(filepath.Join(dir, "tunnels.json"))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(data), "runtimeStatus") {
		t.Fatalf("tunnels.json persisted runtimeStatus: %s", data)
	}
	// Per SDD 05-data-contract §2.1, runtime fields (status, errorMessage,
	// remoteAddr) must NOT be persisted — the Swift native client treats them
	// as transient values overwritten by pollStatus. Persisting them makes
	// Swift read stale "closed" status on launch.
	for _, field := range []string{`"status"`, `"errorMessage"`, `"remoteAddr"`} {
		if strings.Contains(string(data), field) {
			t.Fatalf("tunnels.json persisted runtime field %s: %s", field, data)
		}
	}
	if !strings.Contains(string(data), `"customDomains": []`) {
		t.Fatalf("tunnels.json missing customDomains (Swift non-optional): %s", data)
	}
	if !strings.Contains(string(data), `"name": "web-renamed"`) {
		t.Fatalf("tunnels.json missing update: %s", data)
	}

	if rec := doJSON(http.MethodDelete, "/api/tunnels?id="+id, ""); rec.Code != http.StatusOK {
		t.Fatalf("DELETE /api/tunnels status = %d body=%s", rec.Code, rec.Body.String())
	}
	data, err = os.ReadFile(filepath.Join(dir, "tunnels.json"))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(data), "web-renamed") {
		t.Fatalf("deleted tunnel remains in tunnels.json: %s", data)
	}
}

func TestTunnelAPIPreservesDisabledCreate(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("HOME", t.TempDir())
	if err := os.WriteFile(filepath.Join(dir, "frpc"), []byte("#!/bin/sh\nsleep 60\n"), 0o755); err != nil {
		t.Fatal(err)
	}

	manager, err := tunnel.NewManager(dir)
	if err != nil {
		t.Fatal(err)
	}
	cfgMgr, err := config.NewManager(dir)
	if err != nil {
		t.Fatal(err)
	}
	if err := cfgMgr.SaveServerConfig(&config.ServerConfig{
		ServerAddr:    "tunnel.example.test",
		ServerPort:    7000,
		AuthToken:     "token",
		SubDomainHost: "tunnel.example.test",
		TLSEnabled:    true,
		AdminPort:     7400,
		AdminUser:     "admin",
		AdminPassword: "admin",
	}); err != nil {
		t.Fatal(err)
	}

	server := NewServer(manager, cfgMgr, "127.0.0.1:0")
	req := httptest.NewRequest(http.MethodPost, "/api/tunnels", bytes.NewBufferString(`{
		"name":"disabled-web",
		"type":"http",
		"localIP":"127.0.0.1",
		"localPort":3000,
		"subdomain":"disabled-web",
		"enabled":false
	}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	server.buildMux().ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("POST /api/tunnels status = %d body=%s", rec.Code, rec.Body.String())
	}

	tunnels := manager.GetTunnels()
	if len(tunnels) != 1 {
		t.Fatalf("tunnel count = %d, want 1", len(tunnels))
	}
	if tunnels[0].Enabled {
		t.Fatal("disabled create should preserve enabled=false")
	}
	if got := tunnels[0].RuntimeStatus; got != string(config.StatusClosed) {
		t.Fatalf("disabled create status = %q, want closed", got)
	}
}

func TestTunnelAPINormalizesFullSubdomainBeforePersistence(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("HOME", t.TempDir())
	if err := os.WriteFile(filepath.Join(dir, "frpc"), []byte("#!/bin/sh\nsleep 60\n"), 0o755); err != nil {
		t.Fatal(err)
	}

	manager, err := tunnel.NewManager(dir)
	if err != nil {
		t.Fatal(err)
	}
	cfgMgr, err := config.NewManager(dir)
	if err != nil {
		t.Fatal(err)
	}
	if err := cfgMgr.SaveServerConfig(&config.ServerConfig{
		ServerAddr:    "frp.example.test",
		ServerPort:    7000,
		AuthToken:     "token",
		SubDomainHost: "tunnel.example.test",
		TLSEnabled:    true,
		AdminPort:     7400,
		AdminUser:     "admin",
		AdminPassword: "admin",
	}); err != nil {
		t.Fatal(err)
	}

	server := NewServer(manager, cfgMgr, "127.0.0.1:0")
	handler := server.buildMux()
	doJSON := func(method, path string, body string) *httptest.ResponseRecorder {
		req := httptest.NewRequest(method, path, bytes.NewBufferString(body))
		req.Header.Set("Content-Type", "application/json")
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		return rec
	}

	if rec := doJSON(http.MethodPost, "/api/tunnels", `{
		"name":"full-host",
		"type":"http",
		"localIP":"127.0.0.1",
		"localPort":3000,
		"subdomain":" full-host.tunnel.example.test ",
		"enabled":false
	}`); rec.Code != http.StatusCreated {
		t.Fatalf("POST /api/tunnels status = %d body=%s", rec.Code, rec.Body.String())
	}

	tunnels := manager.GetTunnels()
	if len(tunnels) != 1 {
		t.Fatalf("tunnel count = %d, want 1", len(tunnels))
	}
	if got := tunnels[0].Subdomain; got != "full-host" {
		t.Fatalf("created tunnel subdomain = %q, want full-host", got)
	}

	updated := tunnels[0]
	updated.Subdomain = "renamed.tunnel.example.test"
	updated.Name = "renamed"
	body, err := json.Marshal(updated)
	if err != nil {
		t.Fatal(err)
	}
	if rec := doJSON(http.MethodPut, "/api/tunnels", string(body)); rec.Code != http.StatusOK {
		t.Fatalf("PUT /api/tunnels status = %d body=%s", rec.Code, rec.Body.String())
	}
	tunnels = manager.GetTunnels()
	if got := tunnels[0].Subdomain; got != "renamed" {
		t.Fatalf("updated tunnel subdomain = %q, want renamed", got)
	}

	data, err := os.ReadFile(filepath.Join(dir, "tunnels.json"))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(data), "tunnel.example.test") {
		t.Fatalf("full base host should not persist in tunnels.json: %s", data)
	}
}

func TestSettingsAndServerConfigAPILogUserVisibleEvents(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("HOME", t.TempDir())
	if err := os.WriteFile(filepath.Join(dir, "frpc"), []byte("#!/bin/sh\nsleep 60\n"), 0o755); err != nil {
		t.Fatal(err)
	}

	manager, err := tunnel.NewManager(dir)
	if err != nil {
		t.Fatal(err)
	}
	cfgMgr, err := config.NewManager(dir)
	if err != nil {
		t.Fatal(err)
	}
	server := NewServer(manager, cfgMgr, "127.0.0.1:0")
	handler := server.buildMux()
	doJSON := func(method, path string, body string) *httptest.ResponseRecorder {
		req := httptest.NewRequest(method, path, bytes.NewBufferString(body))
		req.Header.Set("Content-Type", "application/json")
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		return rec
	}

	if rec := doJSON(http.MethodPost, "/api/server-config", `{
		"serverAddr":"tunnel.example.test",
		"serverPort":7000,
		"authToken":"token",
		"subDomainHost":"tunnel.example.test",
		"tlsEnabled":true,
		"adminPort":7400,
		"adminUser":"admin",
		"adminPassword":"admin"
	}`); rec.Code != http.StatusCreated {
		t.Fatalf("POST /api/server-config status = %d body=%s", rec.Code, rec.Body.String())
	}

	if rec := doJSON(http.MethodPost, "/api/settings", `{
		"autoStart": true,
		"launchAtLogin": false,
		"showInDock": false,
		"statusPollingInterval": 3,
		"remoteReachabilityInterval": 90,
		"menuBarIconStyle": "arrowRing"
	}`); rec.Code != http.StatusOK {
		t.Fatalf("POST /api/settings status = %d body=%s", rec.Code, rec.Body.String())
	}

	rec := doJSON(http.MethodGet, "/api/events", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /api/events status = %d body=%s", rec.Code, rec.Body.String())
	}
	var events []config.EventLog
	if err := json.Unmarshal(rec.Body.Bytes(), &events); err != nil {
		t.Fatal(err)
	}
	messages := make([]string, 0, len(events))
	for _, event := range events {
		messages = append(messages, event.Message)
	}
	joined := strings.Join(messages, "\n")
	if !strings.Contains(joined, "服务器配置已保存") {
		t.Fatalf("events missing server config save entry: %#v", messages)
	}
	if !strings.Contains(joined, "菜单栏图标已更新为 arrowRing") {
		t.Fatalf("events missing menu icon save entry: %#v", messages)
	}
	if !strings.Contains(joined, "远程探测间隔已更新为 90 秒") {
		t.Fatalf("events missing probe interval entry: %#v", messages)
	}
}
