//go:build darwin

package autostart

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

const launchdLabel = "com.meilink.client"

// plistPath returns the LaunchAgent plist path. We use a stable label so
// loading/unloading is idempotent across runs.
func plistPath() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	dir := filepath.Join(home, "Library", "LaunchAgents")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	return filepath.Join(dir, launchdLabel+".plist"), nil
}

// currentExecutable returns the absolute path to the running binary. On
// macOS the .app bundle's main executable is what we want to launch.
func currentExecutable() (string, error) {
	exe, err := os.Executable()
	if err != nil {
		return "", err
	}
	// Resolve the .app bundle's MacOS/Meilink if we are a sidecar inside the
	// bundle (e.g. Contents/MacOS/meilink-bin -> Contents/MacOS/Meilink).
	dir := filepath.Dir(exe)
	if info, err := os.Stat(filepath.Join(dir, "Meilink")); err == nil && !info.IsDir() {
		return filepath.Join(dir, "Meilink"), nil
	}
	return exe, nil
}

func writePlist(path, exePath string) error {
	plist := `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>` + launchdLabel + `</string>
    <key>ProgramArguments</key>
    <array>
        <string>` + exePath + `</string>
        <string>serve</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><false/>
</dict>
</plist>
`
	return os.WriteFile(path, []byte(plist), 0o644)
}

func enable() error {
	plist, err := plistPath()
	if err != nil {
		return err
	}
	exe, err := currentExecutable()
	if err != nil {
		return err
	}
	if err := writePlist(plist, exe); err != nil {
		return fmt.Errorf("write launch agent: %w", err)
	}
	// Best-effort load; ignore "already loaded" errors.
	out, err := exec.Command(launchctlLookPath(), "load", plist).CombinedOutput()
	if err != nil && !strings.Contains(strings.ToLower(string(out)), "already") {
		return fmt.Errorf("launchctl load: %s: %w", strings.TrimSpace(string(out)), err)
	}
	return nil
}

func disable() error {
	plist, err := plistPath()
	if err != nil {
		return err
	}
	// Best-effort unload; ignore "not loaded" errors.
	out, err := exec.Command(launchctlLookPath(), "unload", plist).CombinedOutput()
	if err != nil && !strings.Contains(strings.ToLower(string(out)), "could not find specified service") {
		// Continue to remove the plist anyway.
	}
	_ = os.Remove(plist)
	_ = out
	return nil
}

func isEnabled() bool {
	plist, err := plistPath()
	if err != nil {
		return false
	}
	if _, err := os.Stat(plist); err != nil {
		return false
	}
	// Cross-check with launchctl list for an extra level of certainty.
	out, err := exec.Command(launchctlLookPath(), "list").CombinedOutput()
	if err != nil {
		return true // plist exists; assume enabled
	}
	return strings.Contains(string(out), launchdLabel)
}
