//go:build !darwin && !linux && !windows

package autostart

// Stub implementations for unsupported platforms (BSD, etc.). Enable/Disable
// return ErrUnsupported; IsEnabled returns false.

func enable() error  { return ErrUnsupported }
func disable() error { return ErrUnsupported }

func isEnabled() bool { return false }
