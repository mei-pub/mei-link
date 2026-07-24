// Package main implements the Meilink frps server deployment & maintenance tool.
//
// It manages MULTIPLE frps instances — one per domain/token pair — so that
// different machines can tunnel into the server with isolated credentials.
// Each profile gets its own:
//   - /etc/meilink/frps-<name>.toml configuration
//   - frps-<name>.service systemd unit (auto-enabled, auto-restart)
//   - auto-assigned bind port (from 7000 upward) to avoid conflicts
//
// Run with no arguments for an interactive menu, or use subcommands directly.
package main

import (
	"archive/tar"
	"bufio"
	"compress/gzip"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"

	"github.com/spf13/cobra"
)

const (
	defaultFrpVersion  = "v0.70.0"
	githubBase         = "https://github.com/fatedier/frp/releases/download"
	configDir          = "/etc/meilink"
	serverConfigPath   = "/etc/meilink/server.json"
	defaultFrpsBinPath = "/usr/local/bin/frps"
	defaultBindPort    = 7000
	defaultHTTPPort    = 8080
	defaultHTTPSPort   = 8443
)

// Profile is one domain+token frps instance. Each profile maps to an isolated
// frps process so different machines can use distinct credentials.
type Profile struct {
	Name           string `json:"name"`
	Domain         string `json:"domain"`          // subDomainHost
	Token          string `json:"token"`           // auth.token
	BindPort       int    `json:"bind_port"`       // client connection port
	VhostHTTPPort  int    `json:"vhost_http_port"` // HTTP vhost port
	VhostHTTPSPort int    `json:"vhost_https_port"`
}

// ServerState is the persisted state of the deployment tool.
type ServerState struct {
	FrpVersion string    `json:"frp_version"`
	FrpsPath   string    `json:"frps_path"`
	Profiles   []Profile `json:"profiles"`
}

var reader = bufio.NewReader(os.Stdin)

func main() {
	rootCmd := &cobra.Command{
		Use:   "meilink-setup",
		Short: "Meilink frps server deployment & maintenance tool",
		Long: `Manages multiple frps instances (one per domain/token) for multi-machine tunneling.

Each profile = one domain + one token + one frps systemd service.
Run with no arguments for an interactive menu.`,
		RunE: func(cmd *cobra.Command, args []string) error {
			return interactiveMenu()
		},
	}

	rootCmd.AddCommand(menuCmd, setupCmd, addCmd, editCmd, removeCmd, listCmd, startCmd, stopCmdS, restartCmdS, statusCmdS, installFrpsCmd, upgradeCmd)

	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}

var menuCmd = &cobra.Command{Use: "menu", Short: "Interactive menu", RunE: func(c *cobra.Command, a []string) error { return interactiveMenu() }}

var setupCmd = &cobra.Command{Use: "setup", Short: "First-time initialization wizard", RunE: func(c *cobra.Command, a []string) error { return runSetup() }}
var addCmd = &cobra.Command{Use: "add", Short: "Add a new profile (domain+token)", RunE: func(c *cobra.Command, a []string) error { return runAdd() }}
var editCmd = &cobra.Command{Use: "edit [name]", Short: "Edit an existing profile", RunE: func(c *cobra.Command, a []string) error { return runEdit(a) }}
var removeCmd = &cobra.Command{Use: "remove [name]", Short: "Remove a profile and its service", RunE: func(c *cobra.Command, a []string) error { return runRemove(a) }}
var listCmd = &cobra.Command{Use: "list", Short: "List all profiles", RunE: func(c *cobra.Command, a []string) error { return runList() }}
var startCmd = &cobra.Command{Use: "start [name]", Short: "Start one or all frps instances", RunE: func(c *cobra.Command, a []string) error { return runStart(a) }}
var stopCmdS = &cobra.Command{Use: "stop [name]", Short: "Stop one or all frps instances", RunE: func(c *cobra.Command, a []string) error { return runStop(a) }}
var restartCmdS = &cobra.Command{Use: "restart [name]", Short: "Restart one or all frps instances", RunE: func(c *cobra.Command, a []string) error { return runRestart(a) }}
var statusCmdS = &cobra.Command{Use: "status [name]", Short: "Show status of one or all frps instances", RunE: func(c *cobra.Command, a []string) error { return runStatus(a) }}
var installFrpsCmd = &cobra.Command{Use: "install-frps", Short: "Download and install/upgrade the frps binary", RunE: func(c *cobra.Command, a []string) error { return runInstallFrps() }}
var upgradeCmd = &cobra.Command{Use: "upgrade", Short: "Upgrade frps binary and restart all instances", RunE: func(c *cobra.Command, a []string) error { return runUpgrade() }}

// ---------------------------------------------------------------------------
// Platform / privilege helpers
// ---------------------------------------------------------------------------

func mustBeLinux() {
	if runtime.GOOS != "linux" {
		fmt.Println("This deployment tool is designed for Linux servers (systemd).")
		fmt.Printf("Current platform: %s. Exiting.\n", runtime.GOOS)
		os.Exit(0)
	}
}

func requireRoot(action string) bool {
	if os.Geteuid() == 0 {
		return true
	}
	fmt.Printf("✗ Running '%s' requires root (sudo).\n", action)
	fmt.Println("  Re-run with: sudo meilink-setup " + action)
	return false
}

func systemctlAvailable() bool {
	_, err := exec.LookPath("systemctl")
	return err == nil
}

// ---------------------------------------------------------------------------
// State persistence
// ---------------------------------------------------------------------------

func loadState() *ServerState {
	data, err := os.ReadFile(serverConfigPath)
	if err != nil {
		return &ServerState{FrpVersion: defaultFrpVersion, FrpsPath: defaultFrpsBinPath, Profiles: []Profile{}}
	}
	var s ServerState
	if json.Unmarshal(data, &s) != nil {
		return &ServerState{FrpVersion: defaultFrpVersion, FrpsPath: defaultFrpsBinPath, Profiles: []Profile{}}
	}
	if s.FrpVersion == "" {
		s.FrpVersion = defaultFrpVersion
	}
	if s.FrpsPath == "" {
		s.FrpsPath = defaultFrpsBinPath
	}
	if s.Profiles == nil {
		s.Profiles = []Profile{}
	}
	return &s
}

func saveState(s *ServerState) error {
	if err := os.MkdirAll(configDir, 0o755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(serverConfigPath, data, 0o600)
}

func (s *ServerState) findProfile(name string) (*Profile, int) {
	for i := range s.Profiles {
		if s.Profiles[i].Name == name {
			return &s.Profiles[i], i
		}
	}
	return nil, -1
}

// nextBindPort returns the next free bind port (default 7000, then 7001...).
func (s *ServerState) nextBindPort() int {
	maxPort := defaultBindPort - 1
	used := map[int]bool{}
	for _, p := range s.Profiles {
		used[p.BindPort] = true
		if p.BindPort > maxPort {
			maxPort = p.BindPort
		}
	}
	// Find first gap starting at defaultBindPort.
	for p := defaultBindPort; p <= 65535; p++ {
		if !used[p] {
			return p
		}
	}
	return maxPort + 1
}

// ---------------------------------------------------------------------------
// Interactive menu
// ---------------------------------------------------------------------------

func interactiveMenu() error {
	mustBeLinux()
	for {
		s := loadState()
		fmt.Println()
		fmt.Println("============================================")
		fmt.Println("  Meilink frps 服务端管理")
		fmt.Println("============================================")
		fmt.Printf("  frps 版本: %s  路径: %s\n", s.FrpVersion, s.FrpsPath)
		fmt.Printf("  配置文件:  %s\n", serverConfigPath)
		fmt.Printf("  Profile 数量: %d\n", len(s.Profiles))
		fmt.Println()
		if len(s.Profiles) > 0 {
			fmt.Println("  当前 Profile:")
			for _, p := range s.Profiles {
				fmt.Printf("    - %-12s  域名: %-30s  端口: %d\n", p.Name, p.Domain, p.BindPort)
			}
			fmt.Println()
		}
		fmt.Println("  操作:")
		fmt.Println("    1) 初始化 / 安装 frps (setup)")
		fmt.Println("    2) 添加 profile (add)")
		fmt.Println("    3) 编辑 profile (edit)")
		fmt.Println("    4) 删除 profile (remove)")
		fmt.Println("    5) 列出 profile (list)")
		fmt.Println("    6) 启动 (start)")
		fmt.Println("    7) 停止 (stop)")
		fmt.Println("    8) 重启 (restart)")
		fmt.Println("    9) 状态 (status)")
		fmt.Println("    u) 升级 frps (upgrade)")
		fmt.Println("    q) 退出")
		fmt.Println()
		fmt.Print("请选择: ")
		choice := strings.TrimSpace(readLine())

		var err error
		switch choice {
		case "1":
			err = runSetup()
		case "2":
			err = runAdd()
		case "3":
			err = runEdit(nil)
		case "4":
			err = runRemove(nil)
		case "5":
			err = runList()
		case "6":
			err = runStart(nil)
		case "7":
			err = runStop(nil)
		case "8":
			err = runRestart(nil)
		case "9":
			err = runStatus(nil)
		case "u", "U":
			err = runUpgrade()
		case "q", "Q", "":
			fmt.Println("Bye.")
			return nil
		default:
			fmt.Println("无效选择")
		}
		if err != nil {
			fmt.Fprintf(os.Stderr, "错误: %v\n", err)
		}
	}
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

func runSetup() error {
	mustBeLinux()
	if !requireRoot("setup") {
		return nil
	}
	s := loadState()

	// Install frps binary if missing.
	if _, err := os.Stat(s.FrpsPath); err != nil {
		fmt.Println("frps 二进制未找到，开始安装...")
		if err := installFrps(s); err != nil {
			return err
		}
	} else {
		fmt.Printf("frps 已安装: %s\n", s.FrpsPath)
	}

	if len(s.Profiles) == 0 {
		fmt.Println()
		fmt.Println("当前没有任何 profile，开始创建第一个。")
		if err := addProfileInteractive(s); err != nil {
			return err
		}
	} else {
		fmt.Printf("已有 %d 个 profile，跳过创建。使用 'add' 命令可添加更多。\n", len(s.Profiles))
	}
	return nil
}

func runAdd() error {
	mustBeLinux()
	if !requireRoot("add") {
		return nil
	}
	s := loadState()
	return addProfileInteractive(s)
}

func addProfileInteractive(s *ServerState) error {
	p := Profile{}
	for {
		p.Name = prompt("Profile 名称 (如 office, home): ")
		if p.Name == "" {
			fmt.Println("名称不能为空")
			continue
		}
		if _, exists := s.findProfile(p.Name); exists >= 0 {
			fmt.Println("该名称已存在，请换一个")
			continue
		}
		break
	}
	p.Domain = prompt("子域名基域 (如 tunnel.yourdomain.com): ")
	if p.Domain == "" {
		return fmt.Errorf("子域名基域不能为空")
	}
	p.Token = prompt("认证 Token (该 profile 专用): ")
	if p.Token == "" {
		return fmt.Errorf("Token 不能为空")
	}
	p.BindPort = promptInt(fmt.Sprintf("客户端连接端口 [自动分配 %d]: ", s.nextBindPort()), s.nextBindPort())
	p.VhostHTTPPort = promptInt("HTTP vhost 端口 [8080]: ", defaultHTTPPort)
	p.VhostHTTPSPort = promptInt("HTTPS vhost 端口 [8443]: ", defaultHTTPSPort)

	s.Profiles = append(s.Profiles, p)
	if err := saveState(s); err != nil {
		return fmt.Errorf("保存配置失败: %w", err)
	}
	fmt.Printf("✓ 已添加 profile %q\n", p.Name)

	// Generate config + service + start.
	if err := deployProfile(s, &s.Profiles[len(s.Profiles)-1], s.FrpsPath); err != nil {
		return err
	}
	printProfileSummary(s, &s.Profiles[len(s.Profiles)-1])
	return nil
}

func runEdit(args []string) error {
	mustBeLinux()
	if !requireRoot("edit") {
		return nil
	}
	s := loadState()
	name := pickProfileName(args, s, "编辑")
	if name == "" {
		return nil
	}
	p, idx := s.findProfile(name)
	if p == nil {
		return fmt.Errorf("profile %q 不存在", name)
	}
	p.Domain = promptDefault("子域名基域", p.Domain)
	p.Token = promptDefault("认证 Token", p.Token)
	p.BindPort = promptIntDefault("客户端连接端口", p.BindPort)
	p.VhostHTTPPort = promptIntDefault("HTTP vhost 端口", p.VhostHTTPPort)
	p.VhostHTTPSPort = promptIntDefault("HTTPS vhost 端口", p.VhostHTTPSPort)
	s.Profiles[idx] = *p
	if err := saveState(s); err != nil {
		return err
	}
	fmt.Printf("✓ 已更新 profile %q，重新部署...\n", name)
	return deployProfile(s, p, s.FrpsPath)
}

func runRemove(args []string) error {
	mustBeLinux()
	if !requireRoot("remove") {
		return nil
	}
	s := loadState()
	name := pickProfileName(args, s, "删除")
	if name == "" {
		return nil
	}
	if prompt("确认删除 profile "+name+" 及其服务？输入 yes 确认: ") != "yes" {
		fmt.Println("已取消")
		return nil
	}
	// Stop and disable the service.
	svc := "frps-" + name
	exec.Command("systemctl", "stop", svc).Run()
	exec.Command("systemctl", "disable", svc).Run()
	os.Remove("/etc/systemd/system/" + svc + ".service")
	exec.Command("systemctl", "daemon-reload").Run()
	os.Remove(filepath.Join(configDir, "frps-"+name+".toml"))

	// Remove from state.
	_, idx := s.findProfile(name)
	if idx >= 0 {
		s.Profiles = append(s.Profiles[:idx], s.Profiles[idx+1:]...)
	}
	if err := saveState(s); err != nil {
		return err
	}
	fmt.Printf("✓ 已删除 profile %q 及其服务\n", name)
	return nil
}

func runList() error {
	s := loadState()
	fmt.Println()
	fmt.Printf("frps 版本: %s  路径: %s\n", s.FrpVersion, s.FrpsPath)
	if len(s.Profiles) == 0 {
		fmt.Println("暂无 profile。运行 'meilink-setup add' 创建。")
		return nil
	}
	fmt.Printf("%-14s %-32s %-8s %-8s %-8s %s\n", "名称", "域名", "Bind", "HTTP", "HTTPS", "服务状态")
	for _, p := range s.Profiles {
		st := serviceStatus("frps-" + p.Name)
		fmt.Printf("%-14s %-32s %-8d %-8d %-8d %s\n", p.Name, p.Domain, p.BindPort, p.VhostHTTPPort, p.VhostHTTPSPort, st)
	}
	return nil
}

func runStart(args []string) error {
	mustBeLinux()
	if !requireRoot("start") {
		return nil
	}
	return forEachProfile(args, func(p *Profile) error {
		return controlProfile("start", p)
	})
}

func runStop(args []string) error {
	mustBeLinux()
	if !requireRoot("stop") {
		return nil
	}
	return forEachProfile(args, func(p *Profile) error {
		return controlProfile("stop", p)
	})
}

func runRestart(args []string) error {
	mustBeLinux()
	if !requireRoot("restart") {
		return nil
	}
	return forEachProfile(args, func(p *Profile) error {
		return controlProfile("restart", p)
	})
}

func runStatus(args []string) error {
	mustBeLinux()
	return forEachProfile(args, func(p *Profile) error {
		svc := "frps-" + p.Name
		fmt.Printf("=== %s (%s) ===\n", p.Name, svc)
		cmd := exec.Command("systemctl", "status", svc, "--no-pager", "-l")
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		cmd.Run()
		fmt.Println()
		return nil
	})
}

func runInstallFrps() error {
	mustBeLinux()
	if !requireRoot("install-frps") {
		return nil
	}
	s := loadState()
	version := promptDefault("frp 版本", s.FrpVersion)
	s.FrpVersion = version
	if err := installFrps(s); err != nil {
		return err
	}
	return saveState(s)
}

func runUpgrade() error {
	mustBeLinux()
	if !requireRoot("upgrade") {
		return nil
	}
	s := loadState()
	fmt.Printf("当前版本: %s\n", s.FrpVersion)
	newVer := promptDefault("升级到版本", s.FrpVersion)
	if newVer != s.FrpVersion {
		s.FrpVersion = newVer
	}
	if err := installFrps(s); err != nil {
		return err
	}
	if err := saveState(s); err != nil {
		return err
	}
	// Redeploy all profiles with the new binary, then restart.
	for i := range s.Profiles {
		if err := deployProfile(s, &s.Profiles[i], s.FrpsPath); err != nil {
			fmt.Fprintf(os.Stderr, "部署 %s 失败: %v\n", s.Profiles[i].Name, err)
		}
		controlProfile("restart", &s.Profiles[i])
	}
	fmt.Println("✓ 升级完成，所有实例已重启。")
	return nil
}

// ---------------------------------------------------------------------------
// Deployment: config generation + systemd + start
// ---------------------------------------------------------------------------

// deployProfile writes the frps TOML, the systemd unit, reloads, enables and
// restarts the per-profile service. It does NOT return an error if start fails
// (non-fatal: service is still enabled).
func deployProfile(s *ServerState, p *Profile, binPath string) error {
	if !systemctlAvailable() {
		return fmt.Errorf("systemctl 不可用，无法注册服务")
	}
	if err := writeFrpsToml(p); err != nil {
		return fmt.Errorf("写入配置: %w", err)
	}
	if err := writeSystemdUnit(p, binPath); err != nil {
		return fmt.Errorf("写入 systemd unit: %w", err)
	}
	runCmd("systemctl", "daemon-reload")
	runCmd("systemctl", "enable", "frps-"+p.Name)
	runCmd("systemctl", "restart", "frps-"+p.Name)
	return nil
}

func writeFrpsToml(p *Profile) error {
	if err := os.MkdirAll(configDir, 0o755); err != nil {
		return err
	}
	path := filepath.Join(configDir, "frps-"+p.Name+".toml")
	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("# Meilink profile: %s (auto-generated)\n", p.Name))
	sb.WriteString(fmt.Sprintf("bindPort = %d\n", p.BindPort))
	sb.WriteString(fmt.Sprintf("vhostHTTPPort = %d\n", p.VhostHTTPPort))
	sb.WriteString(fmt.Sprintf("vhostHTTPSPort = %d\n", p.VhostHTTPSPort))
	sb.WriteString(fmt.Sprintf("subDomainHost = \"%s\"\n", p.Domain))
	sb.WriteString("auth.method = \"token\"\n")
	sb.WriteString(fmt.Sprintf("auth.token = \"%s\"\n", escapeTOML(p.Token)))
	return os.WriteFile(path, []byte(sb.String()), 0o600)
}

func writeSystemdUnit(p *Profile, binPath string) error {
	svcName := "frps-" + p.Name
	tomlPath := filepath.Join(configDir, "frps-"+p.Name+".toml")
	content := fmt.Sprintf(`[Unit]
Description=Meilink frps service (%s)
After=network.target
Wants=network.target

[Service]
Type=simple
ExecStart=%s -c %s
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
`, p.Name, binPath, tomlPath)
	return os.WriteFile("/etc/systemd/system/"+svcName+".service", []byte(content), 0o644)
}

func controlProfile(action string, p *Profile) error {
	svc := "frps-" + p.Name
	return runCmd("systemctl", action, svc)
}

// ---------------------------------------------------------------------------
// frps download/install
// ---------------------------------------------------------------------------

func installFrps(s *ServerState) error {
	version := s.FrpVersion
	arch := runtime.GOARCH
	if arch == "amd64" {
		arch = "amd64"
	} else if arch == "arm64" {
		arch = "arm64"
	} else if arch == "386" {
		arch = "386"
	}
	filename := fmt.Sprintf("frp_%s_linux_%s.tar.gz", strings.TrimPrefix(version, "v"), arch)
	url := fmt.Sprintf("%s/%s/%s", githubBase, version, filename)
	fmt.Printf("下载 frps %s (%s)...\n", version, url)

	resp, err := http.Get(url)
	if err != nil {
		return fmt.Errorf("下载失败: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("下载失败: HTTP %d", resp.StatusCode)
	}

	tmpDir, err := os.MkdirTemp("", "meilink-frps-*")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmpDir)

	tmpArchive := filepath.Join(tmpDir, "frp.tar.gz")
	f, err := os.Create(tmpArchive)
	if err != nil {
		return err
	}
	if _, err := io.Copy(f, resp.Body); err != nil {
		f.Close()
		return err
	}
	f.Close()

	if err := extractFrps(tmpArchive, tmpDir); err != nil {
		return fmt.Errorf("解压失败: %w", err)
	}
	// Find frps.
	matches, _ := filepath.Glob(filepath.Join(tmpDir, "frp_*", "frps"))
	if len(matches) == 0 {
		matches, _ = filepath.Glob(filepath.Join(tmpDir, "**", "frps"))
	}
	if len(matches) == 0 {
		return fmt.Errorf("未在归档中找到 frps 二进制")
	}
	// Stop all running instances before replacing binary.
	if systemctlAvailable() {
		s := loadState()
		for _, p := range s.Profiles {
			exec.Command("systemctl", "stop", "frps-"+p.Name).Run()
		}
	}
	destPath := s.FrpsPath
	if err := copyFile(matches[0], destPath); err != nil {
		return fmt.Errorf("安装到 %s 失败: %w", destPath, err)
	}
	os.Chmod(destPath, 0o755)
	fmt.Printf("✓ frps 已安装到 %s\n", destPath)
	return nil
}

// extractFrps extracts a tar.gz, stripping the top-level directory.
func extractFrps(tarGzPath, destDir string) error {
	f, err := os.Open(tarGzPath)
	if err != nil {
		return err
	}
	defer f.Close()
	gzr, err := gzip.NewReader(f)
	if err != nil {
		return err
	}
	defer gzr.Close()
	return untar(gzr, destDir)
}

// untar reads a tar stream into destDir, stripping the first path component.
func untar(r io.Reader, destDir string) error {
	tr := tar.NewReader(r)
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		name := hdr.Name
		if parts := strings.SplitN(name, "/", 2); len(parts) == 2 {
			name = parts[1]
		}
		if name == "" {
			continue
		}
		target := filepath.Join(destDir, name)
		if hdr.Typeflag == tar.TypeDir {
			os.MkdirAll(target, 0o755)
			continue
		}
		if hdr.Typeflag != tar.TypeReg && hdr.Typeflag != tar.TypeRegA {
			continue
		}
		os.MkdirAll(filepath.Dir(target), 0o755)
		out, err := os.OpenFile(target, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, os.FileMode(hdr.Mode))
		if err != nil {
			return err
		}
		if _, err := io.Copy(out, tr); err != nil {
			out.Close()
			return err
		}
		out.Close()
	}
	return nil
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	tmp := dst + ".new"
	out, err := os.Create(tmp)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		os.Remove(tmp)
		return err
	}
	out.Close()
	if err := os.Rename(tmp, dst); err != nil {
		return err
	}
	return nil
}

// ---------------------------------------------------------------------------
// Profile iteration helpers
// ---------------------------------------------------------------------------

// forEachProfile applies fn to each named profile, or all if args is empty.
func forEachProfile(args []string, fn func(*Profile) error) error {
	s := loadState()
	if len(s.Profiles) == 0 {
		fmt.Println("暂无 profile。运行 'meilink-setup add' 创建。")
		return nil
	}
	if len(args) == 0 {
		for i := range s.Profiles {
			if err := fn(&s.Profiles[i]); err != nil {
				fmt.Fprintf(os.Stderr, "%s: %v\n", s.Profiles[i].Name, err)
			}
		}
		return nil
	}
	for _, name := range args {
		p, _ := s.findProfile(name)
		if p == nil {
			fmt.Fprintf(os.Stderr, "profile %q 不存在\n", name)
			continue
		}
		if err := fn(p); err != nil {
			fmt.Fprintf(os.Stderr, "%s: %v\n", name, err)
		}
	}
	return nil
}

func pickProfileName(args []string, s *ServerState, verb string) string {
	if len(args) > 0 {
		return args[0]
	}
	if len(s.Profiles) == 0 {
		fmt.Println("暂无 profile。")
		return ""
	}
	fmt.Println("可用 profile:")
	for i, p := range s.Profiles {
		fmt.Printf("  %d) %s (%s)\n", i+1, p.Name, p.Domain)
	}
	fmt.Printf("选择要%s的 profile 名称: ", verb)
	return strings.TrimSpace(readLine())
}

func serviceStatus(svc string) string {
	out, err := exec.Command("systemctl", "is-active", svc).Output()
	if err != nil {
		return "未安装/未知"
	}
	return strings.TrimSpace(string(out))
}

func printProfileSummary(s *ServerState, p *Profile) {
	fmt.Println()
	fmt.Println("────────────────────────────────────────")
	fmt.Printf("  Profile:      %s\n", p.Name)
	fmt.Printf("  域名:         %s\n", p.Domain)
	fmt.Printf("  Token:        %s\n", p.Token)
	fmt.Printf("  客户端端口:   %d\n", p.BindPort)
	fmt.Printf("  HTTP 端口:    %d\n", p.VhostHTTPPort)
	fmt.Printf("  HTTPS 端口:   %d\n", p.VhostHTTPSPort)
	fmt.Println("────────────────────────────────────────")
	fmt.Println("DNS 配置: 在域名管理处为该域名添加泛解析:")
	fmt.Printf("  *.%s  →  A  →  <你的VPS_IP>\n", p.Domain)
	fmt.Println()
	fmt.Println("客户端连接信息 (给需要穿透的机器):")
	fmt.Printf("  服务器地址: <VPS_IP>\n")
	fmt.Printf("  端口: %d\n", p.BindPort)
	fmt.Printf("  Token: %s\n", p.Token)
	fmt.Printf("  子域名基域: %s\n", p.Domain)
	fmt.Println()
	fmt.Println("HTTP/HTTPS: 默认监听非标准端口，如需 80/443，请在前面配置 Nginx 反代:")
	fmt.Printf("  server_name *.%s;\n", p.Domain)
	fmt.Printf("  proxy_pass http://127.0.0.1:%d;\n", p.VhostHTTPPort)
}

// ---------------------------------------------------------------------------
// Prompt helpers
// ---------------------------------------------------------------------------

func readLine() string {
	line, _ := reader.ReadString('\n')
	return strings.TrimSpace(line)
}

func prompt(label string) string {
	fmt.Print(label + " ")
	return readLine()
}

func promptDefault(label, def string) string {
	fmt.Printf("%s [%s]: ", label, def)
	v := readLine()
	if v == "" {
		return def
	}
	return v
}

func promptInt(label string, def int) int {
	fmt.Print(label)
	v := readLine()
	if v == "" {
		return def
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return def
	}
	return n
}

func promptIntDefault(label string, def int) int {
	fmt.Printf("%s [%d]: ", label, def)
	return promptInt("", def)
}

func runCmd(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func escapeTOML(s string) string { return strings.ReplaceAll(s, "\"", "\\\"") }
