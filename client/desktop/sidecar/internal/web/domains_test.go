package web

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/meilink/desktop-sidecar/internal/config"
	"github.com/meilink/desktop-sidecar/internal/tunnel"
)

// TestDomainsAPIProxy 验证 sidecar 的 /api/domains 端点正确代理到服务端管理页。
// 起 mock 管理页，配置 sidecar server.json 指向它，验证代理链路 + token 认证 + fallback。
func TestDomainsAPIProxy(t *testing.T) {
	// mock 管理页：要求 Bearer token，返回域名目录
	mockHit := false
	mockSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/domains" {
			http.NotFound(w, r)
			return
		}
		if r.Header.Get("Authorization") != "Bearer testtoken" {
			http.Error(w, `{"error":"token 无效"}`, http.StatusUnauthorized)
			return
		}
		mockHit = true
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"domains":[{"domain":"meichuanxue.com","kind":"primary"},{"domain":"*.meichuanxue.com","kind":"wildcard"}]}`))
	}))
	defer mockSrv.Close()

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
	// 写入 server.json，配置管理页地址 + token
	serverCfg := &config.ServerConfig{
		ServerAddr:     "127.0.0.1",
		ServerPort:     7000,
		AuthToken:      "tok",
		ManagementURL:  mockSrv.URL,
		DomainAPIToken: "testtoken",
	}
	if err := manager.SaveServerConfig(serverCfg); err != nil {
		t.Fatal(err)
	}

	server := NewServer(manager, cfgMgr, "127.0.0.1:0")
	handler := server.buildMux()

	// 1. 正确 token → 200 + domains，且 mock 被命中
	req := httptest.NewRequest(http.MethodGet, "/api/domains", nil)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	if !mockHit {
		t.Fatal("mock management server was not hit")
	}
	var resp struct {
		Domains []struct {
			Domain string `json:"domain"`
			Kind   string `json:"kind"`
		} `json:"domains"`
		Error string `json:"error"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	if len(resp.Domains) != 2 || resp.Domains[0].Domain != "meichuanxue.com" {
		t.Fatalf("unexpected domains: %+v", resp.Domains)
	}
	if resp.Error != "" {
		t.Fatalf("unexpected error: %s", resp.Error)
	}
}

// TestDomainsAPIFallback 验证未配置管理页时返回 fallback（domains 空 + error）。
func TestDomainsAPIFallback(t *testing.T) {
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
	// 不配置 managementURL / token
	server := NewServer(manager, cfgMgr, "127.0.0.1:0")
	handler := server.buildMux()

	req := httptest.NewRequest(http.MethodGet, "/api/domains", nil)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if rec.Code != 200 {
		t.Fatalf("expected 200 (fallback), got %d", rec.Code)
	}
	var resp struct {
		Domains []interface{} `json:"domains"`
		Error   string        `json:"error"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	if len(resp.Domains) != 0 {
		t.Fatalf("expected empty domains in fallback, got %+v", resp.Domains)
	}
	if resp.Error == "" {
		t.Fatal("expected non-empty error in fallback")
	}
}
