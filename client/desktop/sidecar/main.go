package main

import (
	"github.com/meilink/desktop-sidecar/cmd/meilink"
)

func main() {
	setProcessGroup()
	if err := meilink.Execute(); err != nil {
		panic(err)
	}
}
