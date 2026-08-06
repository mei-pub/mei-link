//go:build windows

package main

// Windows 无进程组 / Setpgid 概念，退出时依赖 kill ProcessTree（taskkill /T）
// 或 HTTP /api/control/stop 兜底。
func setProcessGroup() {}
