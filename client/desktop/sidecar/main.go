package main

import (
	"github.com/meilink/desktop-sidecar/cmd/meilink"
)

func main() {
	if err := meilink.Execute(); err != nil {
		panic(err)
	}
}
