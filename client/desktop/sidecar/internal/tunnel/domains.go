package tunnel

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// DomainEntry 镜像服务端 config.ts 的 ManagedDomain（只读子集）。
type DomainEntry struct {
	Domain string `json:"domain"`
	Kind   string `json:"kind"` // "primary" 或 "wildcard"
}

func (d DomainEntry) IsWildcard() bool { return d.Kind == "wildcard" }

// HostPart 返回泛域名去掉 "*." 的主机部分；主域名直接返回自身。
func (d DomainEntry) HostPart() string {
	if len(d.Domain) > 2 && d.Domain[:2] == "*." {
		return d.Domain[2:]
	}
	return d.Domain
}

// Combined 把用户填的前缀拼成最终访问域名。
// 主域名：admin + meichuanxue.com → admin.meichuanxue.com
// 泛域名：admin + *.meichuanxue.com → admin.meichuanxue.com
func (d DomainEntry) Combined(prefix string) string {
	host := d.HostPart()
	if prefix == "" {
		return host
	}
	return prefix + "." + host
}

type domainsResponse struct {
	Domains []DomainEntry `json:"domains"`
}

// FetchDomains 从服务端管理页拉取域名目录。客户端不持久化，每次实时拉。
// 失败时返回 error，调用方 fallback 到手填模式。
func FetchDomains(managementURL, token string) ([]DomainEntry, error) {
	if managementURL == "" || token == "" {
		return nil, fmt.Errorf("未配置管理页地址或 token")
	}
	// 去掉尾部斜杠
	base := managementURL
	for len(base) > 0 && base[len(base)-1] == '/' {
		base = base[:len(base)-1]
	}

	client := &http.Client{Timeout: 5 * time.Second}
	req, err := http.NewRequest("GET", base+"/api/domains", nil)
	if err != nil {
		return nil, fmt.Errorf("管理页地址无效: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("无法连接管理页: %w", err)
	}
	defer resp.Body.Close()

	switch resp.StatusCode {
	case 404:
		return nil, fmt.Errorf("服务端未启用域名目录接口（未配 MEILINK_DOMAIN_API_TOKEN）")
	case 401:
		return nil, fmt.Errorf("域名拉取 token 错误")
	}
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("管理页返回错误（HTTP %d）", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("读取响应失败: %w", err)
	}
	var dr domainsResponse
	if err := json.Unmarshal(body, &dr); err != nil {
		return nil, fmt.Errorf("解析响应失败: %w", err)
	}
	return dr.Domains, nil
}
