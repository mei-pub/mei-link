package frpc

import (
	"context"
	"io"
	"net/http"
	"strings"
	"testing"
)

type roundTripFunc func(*http.Request) (*http.Response, error)

func (fn roundTripFunc) RoundTrip(req *http.Request) (*http.Response, error) {
	return fn(req)
}

func TestIsHTTPConflictRecognizesStatusError(t *testing.T) {
	if !IsHTTPConflict(&HTTPStatusError{StatusCode: 409, Method: "POST", Path: "/api/store/proxies"}) {
		t.Fatal("expected HTTP 409 status error to be recognized as conflict")
	}
	if IsHTTPConflict(&HTTPStatusError{StatusCode: 500, Method: "POST", Path: "/api/store/proxies"}) {
		t.Fatal("HTTP 500 should not be recognized as conflict")
	}
}

func TestReloadIgnoresUnsupportedEndpoint(t *testing.T) {
	for _, statusCode := range []int{http.StatusNotFound, http.StatusMethodNotAllowed} {
		t.Run(http.StatusText(statusCode), func(t *testing.T) {
			api := &AdminAPI{
				baseURL: "http://127.0.0.1:7500",
				client: &http.Client{
					Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
						if req.Method != http.MethodPost {
							t.Fatalf("unexpected method: %s", req.Method)
						}
						if req.URL.Path != "/api/reload" {
							t.Fatalf("unexpected path: %s", req.URL.Path)
						}
						return &http.Response{
							StatusCode: statusCode,
							Body:       io.NopCloser(strings.NewReader("")),
							Header:     make(http.Header),
						}, nil
					}),
				},
			}
			if err := api.Reload(context.Background()); err != nil {
				t.Fatalf("Reload() returned error for HTTP %d: %v", statusCode, err)
			}
		})
	}
}
