//go:build !windows

package main

import "syscall"

// Unix 下让自己成为新进程组首（pgid = own pid），这样 frpc（本进程的子进程）
// 继承同一进程组。Tauri 退出时用 kill -TERM/-KILL -<pgid> 杀整组，
// 保证 frpc 不被孤儿化（即便 HTTP /api/control/stop 失败）。
func setProcessGroup() {
	// 非致命：失败则退化为单进程 kill（与旧行为一致）
	_ = syscall.Setpgid(0, 0)
}
