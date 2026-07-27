//go:build linux

package autostart

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

const systemdUnit = "meilink-client.service"

// unitPath returns the systemd user unit path.
func unitPath() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	dir := filepath.Join(home, ".config", "systemd", "user")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	return filepath.Join(dir, systemdUnit), nil
}

func writeUnit(path, exePath string) error {
	unit := fmt.Sprintf(`[Unit]
Description=Meilink frp client
After=network.target

[Service]
Type=simple
ExecStart=%s serve
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
`, exePath)
	return os.WriteFile(path, []byte(unit), 0o644)
}

func enable() error {
	unit, err := unitPath()
	if err != nil {
		return err
	}
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	if err := writeUnit(unit, exe); err != nil {
		return fmt.Errorf("write systemd unit: %w", err)
	}
	// systemctl --user daemon-reload + enable
	for _, args := range [][]string{
		{"--user", "daemon-reload"},
		{"--user", "enable", systemdUnit},
	} {
		out, err := exec.Command("systemctl", args...).CombinedOutput()
		if err != nil {
			return fmt.Errorf("systemctl %s: %s: %w", strings.Join(args, " "), strings.TrimSpace(string(out)), err)
		}
	}
	return nil
}

func disable() error {
	out, err := exec.Command("systemctl", "--user", "disable", systemdUnit).CombinedOutput()
	if err != nil {
		// Ignore "not loaded" errors — unit file may have been removed already.
		if !strings.Contains(strings.ToLower(string(out)), "no unit") {
			// Continue to remove the unit file anyway.
		}
	}
	unit, err := unitPath()
	if err == nil {
		_ = os.Remove(unit)
	}
	// Best-effort daemon-reload; ignore errors.
	_, _ = exec.Command("systemctl", "--user", "daemon-reload").CombinedOutput()
	_ = out
	return nil
}

func isEnabled() bool {
	out, err := exec.Command("systemctl", "--user", "is-enabled", systemdUnit).CombinedOutput()
	if err != nil {
		return false
	}
	return strings.TrimSpace(string(out)) == "enabled"
}
