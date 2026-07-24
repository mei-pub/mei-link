package config

import (
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"
)

func TestNewManagerOnMacOSUsesNativeApplicationSupportDir(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("macOS-specific data sharing")
	}

	home := t.TempDir()
	t.Setenv("HOME", home)
	nativeDir := filepath.Join(home, "Library", "Application Support", "Meilink")
	if err := os.MkdirAll(nativeDir, 0o700); err != nil {
		t.Fatal(err)
	}

	m, err := NewManager(filepath.Join(home, ".meilink"))
	if err != nil {
		t.Fatal(err)
	}

	if got := filepath.Dir(m.FrpcConfigPath()); got != nativeDir {
		t.Fatalf("data dir = %q, want native dir %q", got, nativeDir)
	}
}

func TestLoadSettingsReadsNativeShowInDockAndMenuIconDefaults(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	dir := filepath.Join(home, ".meilink")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "settings.json"), []byte(`{
		"autoStart": true,
		"launchAtLogin": false,
		"showInDock": false,
		"statusPollingInterval": 4,
		"remoteReachabilityInterval": 90,
		"menuBarIconStyle": "relay"
	}`), 0o600); err != nil {
		t.Fatal(err)
	}

	m, err := NewManager(dir)
	if err != nil {
		t.Fatal(err)
	}
	settings, err := m.LoadSettings()
	if err != nil {
		t.Fatal(err)
	}

	if settings.ShowInDock {
		t.Fatal("ShowInDock should preserve the native app's false value")
	}
	if settings.MenuBarIconStyle != "relay" {
		t.Fatalf("MenuBarIconStyle = %q, want relay", settings.MenuBarIconStyle)
	}
}

func TestLoadSettingsNormalizesSwiftMenuBarIconStyle(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	dir := filepath.Join(home, ".meilink")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "settings.json"), []byte(`{
		"menuBarIconStyle": "arrowRing"
	}`), 0o600); err != nil {
		t.Fatal(err)
	}

	m, err := NewManager(dir)
	if err != nil {
		t.Fatal(err)
	}
	settings, err := m.LoadSettings()
	if err != nil {
		t.Fatal(err)
	}

	if settings.MenuBarIconStyle != "arrowRing" {
		t.Fatalf("MenuBarIconStyle = %q, want Swift value arrowRing", settings.MenuBarIconStyle)
	}
}

func TestLoadTunnelsAcceptsSwiftStatusNames(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	dir := filepath.Join(home, ".meilink")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "tunnels.json"), []byte(`[{
		"id": "11111111-1111-1111-1111-111111111111",
		"name": "web",
		"type": "http",
		"localIP": "127.0.0.1",
		"localPort": 3000,
		"enabled": true,
		"status": "waitStart",
		"createdAt": "2026-07-24T00:00:00Z",
		"updatedAt": "2026-07-24T00:00:00Z"
	}]`), 0o600); err != nil {
		t.Fatal(err)
	}

	m, err := NewManager(dir)
	if err != nil {
		t.Fatal(err)
	}
	tunnels, err := m.LoadTunnels()
	if err != nil {
		t.Fatal(err)
	}

	if got := tunnels[0].RuntimeStatus; got != string(StatusWaitStart) {
		t.Fatalf("RuntimeStatus = %q, want %q", got, StatusWaitStart)
	}
}

func TestLoadTunnelsDefaultsDisabledNativeTunnelToClosed(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	dir := filepath.Join(home, ".meilink")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "tunnels.json"), []byte(`[{
		"id": "22222222-2222-2222-2222-222222222222",
		"name": "disabled-web",
		"type": "http",
		"localIP": "127.0.0.1",
		"localPort": 3000,
		"enabled": false,
		"createdAt": "2026-07-24T00:00:00Z",
		"updatedAt": "2026-07-24T00:00:00Z"
	}]`), 0o600); err != nil {
		t.Fatal(err)
	}

	m, err := NewManager(dir)
	if err != nil {
		t.Fatal(err)
	}
	tunnels, err := m.LoadTunnels()
	if err != nil {
		t.Fatal(err)
	}

	if got := tunnels[0].RuntimeStatus; got != string(StatusClosed) {
		t.Fatalf("RuntimeStatus = %q, want %q", got, StatusClosed)
	}
}

func TestSaveTunnelsWritesSwiftStatusField(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	dir := filepath.Join(home, ".meilink")

	m, err := NewManager(dir)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Date(2026, 7, 24, 0, 0, 0, 0, time.UTC)
	if err := m.SaveTunnels([]Tunnel{{
		ID:            "33333333-3333-3333-3333-333333333333",
		Name:          "web",
		Type:          TunnelHTTP,
		LocalIP:       "127.0.0.1",
		LocalPort:     3000,
		Subdomain:     "web",
		Enabled:       true,
		CreatedAt:     now,
		UpdatedAt:     now,
		RuntimeStatus: string(StatusWaitStart),
	}}); err != nil {
		t.Fatal(err)
	}

	data, err := os.ReadFile(filepath.Join(dir, "tunnels.json"))
	if err != nil {
		t.Fatal(err)
	}
	var raw []map[string]interface{}
	if err := json.Unmarshal(data, &raw); err != nil {
		t.Fatal(err)
	}
	if _, ok := raw[0]["runtimeStatus"]; ok {
		t.Fatalf("tunnels.json should not persist runtimeStatus: %s", data)
	}
	if got := raw[0]["status"]; got != "waitStart" {
		t.Fatalf("status = %v, want waitStart in Swift Codable format; json=%s", got, data)
	}
}

func TestNormalizeTunnelsFileMigratesLegacyRuntimeStatus(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	dir := filepath.Join(home, ".meilink")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "tunnels.json"), []byte(`[{
		"id": "44444444-4444-4444-4444-444444444444",
		"name": "legacy",
		"type": "http",
		"localIP": "127.0.0.1",
		"localPort": 3000,
		"subdomain": "legacy",
		"enabled": true,
		"createdAt": "2026-07-24T00:00:00Z",
		"updatedAt": "2026-07-24T00:00:00Z",
		"runtimeStatus": "wait_start"
	}]`), 0o600); err != nil {
		t.Fatal(err)
	}

	m, err := NewManager(dir)
	if err != nil {
		t.Fatal(err)
	}
	if err := m.NormalizeTunnelsFile(); err != nil {
		t.Fatal(err)
	}

	data, err := os.ReadFile(filepath.Join(dir, "tunnels.json"))
	if err != nil {
		t.Fatal(err)
	}
	if string(data) == "" {
		t.Fatal("tunnels.json should not be empty")
	}
	var raw []map[string]interface{}
	if err := json.Unmarshal(data, &raw); err != nil {
		t.Fatal(err)
	}
	if _, ok := raw[0]["runtimeStatus"]; ok {
		t.Fatalf("legacy runtimeStatus should be migrated away: %s", data)
	}
	if got := raw[0]["status"]; got != "waitStart" {
		t.Fatalf("status = %v, want waitStart after migration; json=%s", got, data)
	}
}
