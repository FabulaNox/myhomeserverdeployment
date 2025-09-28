package main

import (
	"fmt"
	"go-docker-tools/cmd"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: docker-tools <command> [flags]")
		os.Exit(1)
	}
	cmd.MainLogic()
}
