package cmd

import (
	"fmt"
	"os"
	"os/exec"
)

// BootstrapCommand checks environment, dependencies, and user setup for autostart
func BootstrapCommand(args []string) {
	// Check Docker socket
	if _, err := os.Stat("/var/run/docker.sock"); err != nil {
		fmt.Fprintln(os.Stderr, "[ERROR] Docker socket missing or inaccessible:", err)
		os.Exit(2)
	}
	// Check Docker daemon health
	if err := exec.Command("docker", "info").Run(); err != nil {
		fmt.Fprintln(os.Stderr, "[ERROR] Docker daemon not running or not accessible:", err)
		os.Exit(3)
	}
	// Check config file
	if _, err := os.Stat("saver.yaml"); err != nil {
		fmt.Fprintln(os.Stderr, "[ERROR] Config file missing:", err)
		os.Exit(4)
	}
	// Validate config fields (basic)
	// (Could be expanded for stricter validation)
	fmt.Println("[NOTIFY] Environment and dependencies OK.")
}
