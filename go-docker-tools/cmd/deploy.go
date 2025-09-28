package cmd

import (
	"fmt"
	"os"
	"os/exec"
)

// DeployAutostartCommand installs or uninstalls autostart integration (systemd or cron)
func DeployAutostartCommand(args []string) {
	if len(args) < 1 {
		fmt.Println("Usage: go-docker-tools deploy [install|uninstall]")
		os.Exit(1)
	}
	switch args[0] {
	case "install":
		installAutostart()
	case "uninstall":
		uninstallAutostart()
	default:
		fmt.Println("Unknown deploy action:", args[0])
		os.Exit(1)
	}
}

func installAutostart() {
	// Example: create a systemd service file for autostart
	service := `[Unit]
Description=Go Docker Tools Autostart
After=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/go-docker-tools autostart

[Install]
WantedBy=multi-user.target
`
	path := "/etc/systemd/system/go-docker-tools-autostart.service"
	err := os.WriteFile(path, []byte(service), 0644)
	if err != nil {
		fmt.Fprintln(os.Stderr, "[ERROR] Failed to write systemd service:", err)
		os.Exit(2)
	}
	if err := exec.Command("systemctl", "daemon-reload").Run(); err != nil {
		fmt.Fprintln(os.Stderr, "[ERROR] Failed to reload systemd:", err)
		os.Exit(3)
	}
	if err := exec.Command("systemctl", "enable", "go-docker-tools-autostart").Run(); err != nil {
		fmt.Fprintln(os.Stderr, "[ERROR] Failed to enable systemd service:", err)
		os.Exit(4)
	}
	fmt.Println("[NOTIFY] Autostart installed and enabled via systemd.")
}

func uninstallAutostart() {
	path := "/etc/systemd/system/go-docker-tools-autostart.service"
	if err := exec.Command("systemctl", "disable", "go-docker-tools-autostart").Run(); err != nil {
		fmt.Fprintln(os.Stderr, "[ERROR] Failed to disable systemd service:", err)
	}
	if err := os.Remove(path); err != nil {
		fmt.Fprintln(os.Stderr, "[ERROR] Failed to remove systemd service file:", err)
	}
	if err := exec.Command("systemctl", "daemon-reload").Run(); err != nil {
		fmt.Fprintln(os.Stderr, "[ERROR] Failed to reload systemd:", err)
	}
	fmt.Println("[NOTIFY] Autostart uninstalled from systemd.")
}
