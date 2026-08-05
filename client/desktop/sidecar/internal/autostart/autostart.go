// Package autostart provides cross-platform "launch at login" support.
//
// macOS writes a LaunchAgent plist under ~/Library/LaunchAgents and loads it
// via launchctl (mirrors the Swift SMAppService.mainApp behavior).
// Linux writes a systemd user unit under ~/.config/systemd/user/.
// Windows writes HKCU\Software\Microsoft\Windows\CurrentVersion\Run.
//
// All platform implementations expose the same Enable/Disable/IsEnabled/
// Available surface so the web layer can consume them uniformly.
package autostart

import (
	"errors"
	"os/exec"
	"runtime"
)

// ErrUnsupported is returned by Enable/Disable on platforms without an
// implementation. IsEnabled returns false in that case.
var ErrUnsupported = errors.New("autostart: unsupported platform")

// Available reports whether the current platform has an autostart
// implementation. macOS / Linux / Windows return true; others return false.
func Available() bool {
	switch runtime.GOOS {
	case "darwin", "linux", "windows":
		return true
	default:
		return false
	}
}

// Enable registers the app to start at login. Returns ErrUnsupported on
// platforms without an implementation.
func Enable() error {
	return enable()
}

// Disable removes the autostart registration. Returns ErrUnsupported on
// platforms without an implementation.
func Disable() error {
	return disable()
}

// IsEnabled reports whether autostart is currently registered. Returns
// false (without error) on unsupported platforms.
func IsEnabled() bool {
	return isEnabled()
}

// launchctlCmd is a tiny helper used by the darwin implementation to locate
// launchctl without shadowing exec.LookPath in tests.
func launchctlLookPath() string {
	p, err := exec.LookPath("launchctl")
	if err != nil {
		return "/bin/launchctl"
	}
	return p
}
