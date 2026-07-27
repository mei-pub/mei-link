//go:build !windows

package frpc

import "os/exec"

// applyPlatformAttrs is a no-op on non-Windows platforms. Unix frpc inherits
// the parent's process group (no console window to hide).
func applyPlatformAttrs(_ *exec.Cmd) {}
