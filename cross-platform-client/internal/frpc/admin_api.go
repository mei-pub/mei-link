package frpc

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"

	"github.com/meilink/client/internal/config"
)

// AdminAPI talks to the frpc web server (admin UI) on 127.0.0.1:{adminPort}.
// All endpoints require HTTP Basic Auth derived from the frpc webServer config.
type AdminAPI struct {
	baseURL    string
	authHeader string
	client     *http.Client
}

type HTTPStatusError struct {
	StatusCode int
	Method     string
	Path       string
}

func (e *HTTPStatusError) Error() string {
	return fmt.Sprintf("HTTP %d from %s %s", e.StatusCode, e.Method, e.Path)
}

func IsHTTPConflict(err error) bool {
	return IsHTTPStatus(err, http.StatusConflict)
}

func IsHTTPStatus(err error, statusCodes ...int) bool {
	var statusErr *HTTPStatusError
	if !errors.As(err, &statusErr) {
		return false
	}
	for _, statusCode := range statusCodes {
		if statusErr.StatusCode == statusCode {
			return true
		}
	}
	return false
}

// NewAdminAPI creates a client for the local frpc admin API.
func NewAdminAPI(cfg *config.ServerConfig) *AdminAPI {
	return &AdminAPI{
		baseURL:    fmt.Sprintf("http://127.0.0.1:%d", cfg.AdminPort),
		authHeader: "Basic " + base64.StdEncoding.EncodeToString([]byte(cfg.AdminUser+":"+cfg.AdminPassword)),
		client:     &http.Client{Timeout: 10 * time.Second},
	}
}

// HealthCheck verifies the frpc admin API is reachable (GET /healthz, no auth).
func (a *AdminAPI) HealthCheck(ctx context.Context) (bool, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, a.baseURL+"/healthz", nil)
	if err != nil {
		return false, err
	}
	resp, err := a.client.Do(req)
	if err != nil {
		return false, err
	}
	defer resp.Body.Close()
	return resp.StatusCode == http.StatusOK, nil
}

// StatusResponse maps proxy type -> list of statuses. Mirrors frp /api/status.
type StatusResponse map[string][]ProxyStatus

// ProxyStatus is one proxy status entry from frp /api/status. JSON keys are
// snake_case in frp's response (local_addr, remote_addr).
type ProxyStatus struct {
	Name       string `json:"name"`
	Type       string `json:"type"`
	Status     string `json:"status"` // frp phase: new / wait start / start error / running / check failed / closed
	Err        string `json:"err"`
	LocalAddr  string `json:"local_addr"`
	RemoteAddr string `json:"remote_addr"`
	Plugin     string `json:"plugin"`
	Source     string `json:"source,omitempty"` // "store" or "" (config)
}

// GetStatus returns current proxy statuses from frpc.
func (a *AdminAPI) GetStatus(ctx context.Context) (StatusResponse, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, a.baseURL+"/api/status", nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", a.authHeader)
	resp, err := a.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	var result StatusResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, err
	}
	return result, nil
}

// Reload tells frpc to reload its configuration.
func (a *AdminAPI) Reload(ctx context.Context) error {
	err := a.doJSON(ctx, http.MethodPost, "/api/reload", nil)
	if IsHTTPStatus(err, http.StatusNotFound, http.StatusMethodNotAllowed) {
		return nil
	}
	return err
}

// StopFrpc sends the stop command to frpc.
func (a *AdminAPI) StopFrpc(ctx context.Context) error {
	return a.doJSON(ctx, http.MethodPost, "/api/stop", nil)
}

// ListProxies returns all proxies currently registered in frpc's store.
func (a *AdminAPI) ListProxies(ctx context.Context) ([]config.ProxyDefinition, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, a.baseURL+"/api/store/proxies", nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", a.authHeader)
	resp, err := a.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("HTTP %d from GET /api/store/proxies", resp.StatusCode)
	}
	var out config.ProxyListResponse
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, err
	}
	return out.Proxies, nil
}

// CreateProxy adds a new proxy via Store API (POST /api/store/proxies).
func (a *AdminAPI) CreateProxy(ctx context.Context, def config.ProxyDefinition) error {
	return a.doJSON(ctx, http.MethodPost, "/api/store/proxies", def)
}

// UpdateProxy modifies an existing proxy (PUT /api/store/proxies/{name}).
func (a *AdminAPI) UpdateProxy(ctx context.Context, def config.ProxyDefinition) error {
	return a.doJSON(ctx, http.MethodPut, "/api/store/proxies/"+url.PathEscape(def.Name), def)
}

// DeleteProxy removes a proxy by name (DELETE /api/store/proxies/{name}).
func (a *AdminAPI) DeleteProxy(ctx context.Context, name string) error {
	return a.doJSON(ctx, http.MethodDelete, "/api/store/proxies/"+url.PathEscape(name), nil)
}

// doJSON issues an authenticated JSON request against path (path must NOT
// contain the baseURL). body may be nil.
func (a *AdminAPI) doJSON(ctx context.Context, method, path string, body interface{}) error {
	var reader io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			return err
		}
		reader = bytes.NewReader(data)
	}
	req, err := http.NewRequestWithContext(ctx, method, a.baseURL+path, reader)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", a.authHeader)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := a.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return &HTTPStatusError{StatusCode: resp.StatusCode, Method: method, Path: path}
	}
	return nil
}
