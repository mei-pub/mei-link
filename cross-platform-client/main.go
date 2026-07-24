package main

import (
	"github.com/meilink/client/cmd/meilink"
)

func main() {
	if err := meilink.Execute(); err != nil {
		panic(err)
	}
}
