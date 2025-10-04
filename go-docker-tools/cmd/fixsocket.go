package cmd

import (
	"fmt"
	"os"
	"runtime"

	"github.com/FabulaNox/go-docker-tools/internal"
)

// FixSocketCommand fixes Docker socket permissions for the configured user/group
func FixSocketCommand(args []string) {
	if len(args) < 1 {
		fmt.Println("Usage: go-docker-tools fixsocket <socket_path>")
		internal.SendSlackNotification("[ERROR] Usage: go-docker-tools fixsocket <socket_path>")
		os.Exit(1)
	}
	socket := args[0]
	if runtime.GOOS == "windows" {
		fmt.Println("[WARN] Socket permissions cannot be set on Windows. Skipping.")
		internal.SendSlackNotification("[WARN] Socket permissions cannot be set on Windows. Skipping.")
		return
	}
	// Example: set permissions to 666 (rw for all)
	err := os.Chmod(socket, 0666)
	if err != nil {
		fmt.Println("Failed to set permissions on socket:", err)
		internal.SendSlackNotification("[ERROR] Failed to set permissions on socket: " + err.Error())
		os.Exit(1)
	}
	msg := fmt.Sprintf("Docker socket permissions fixed: %s", socket)
	fmt.Println(msg)
	internal.SendSlackNotification("[NOTIFY] " + msg)
}
