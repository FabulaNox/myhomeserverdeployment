package cmd

import (
	"fmt"
	"os"
	"runtime"
)

// FixSocketCommand fixes Docker socket permissions for the configured user/group
func FixSocketCommand(args []string) {
	if len(args) < 1 {
		fmt.Println("Usage: go-docker-tools fixsocket <socket_path>")
		os.Exit(1)
	}
       socket := args[0]
       if runtime.GOOS == "windows" {
	       fmt.Println("[WARN] Socket permissions cannot be set on Windows. Skipping.")
	       return
       }
       // Example: set permissions to 666 (rw for all)
       err := os.Chmod(socket, 0666)
       if err != nil {
	       fmt.Println("Failed to set permissions on socket:", err)
	       os.Exit(1)
       }
       fmt.Println("Docker socket permissions fixed:", socket)
}
