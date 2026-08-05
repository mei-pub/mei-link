package config

import (
	"testing"
)

func TestTomlStringEscapesWindowsStorePath(t *testing.T) {
	got := tomlString(`C:\Users\Administrator\.meilink\store.json`)
	want := `path = "C:\\Users\\Administrator\\.meilink\\store.json"`
	if "path = "+got != want {
		t.Fatalf("escaped path = %q, want %q", "path = "+got, want)
	}
}
