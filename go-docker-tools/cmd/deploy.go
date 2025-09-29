package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"github.com/FabulaNox/go-docker-tools/internal"
)

// DeployAutostartCommand installs or uninstalls autostart integration (systemd or cron)
func DeployAutostartCommand(args []string) {
	if len(args) < 1 {
		fmt.Println("Usage: go-docker-tools deploy [install|uninstall]")
		os.Exit(1)
	}
	switch args[0] {
	case "install":
		switch runtime.GOOS {
		case "linux":
			installAutostart()
		case "windows":
			installWindowsService()
		case "darwin":
			installLaunchd()
		default:
			fmt.Println("[WARN] Autostart install not supported on this platform.")
		}
	case "uninstall":
		switch runtime.GOOS {
		case "linux":
			uninstallAutostart()
		case "windows":
			uninstallWindowsService()
		case "darwin":
			uninstallLaunchd()
		default:
			fmt.Println("[WARN] Autostart uninstall not supported on this platform.")
		}
	default:
		fmt.Println("Unknown deploy action:", args[0])
		os.Exit(1)
	}
}

// Windows Service install/uninstall (scaffold)
func installWindowsService() {
	exe, err := os.Executable()
	if err != nil {
		fmt.Println("[ERROR] Could not determine executable path:", err)
		internal.SendSlackNotification("[ERROR] Could not determine executable path: " + err.Error())
		os.Exit(1)
	}
	serviceName := "GoDockerTools"
	// Try to find nssm.exe in PATH or current dir
	nssmPath, err := exec.LookPath("nssm.exe")
	if err != nil {
		nssmPath = filepath.Join(filepath.Dir(exe), "nssm.exe")
	}
	if _, err := os.Stat(nssmPath); err != nil {
		fmt.Println("[ERROR] nssm.exe not found. Please download NSSM and place it in the same directory as this binary or in your PATH.")
		os.Exit(2)
	}
	// Install service
	cmd := exec.Command(nssmPath, "install", serviceName, exe, "autostart")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		fmt.Println("[ERROR] Failed to install Windows service:", err)
		os.Exit(3)
	}
	fmt.Println("[NOTIFY] Windows service installed via NSSM. Use 'nssm start", serviceName, "' to start.")
}
func uninstallWindowsService() {
	serviceName := "GoDockerTools"
	nssmPath, err := exec.LookPath("nssm.exe")
	if err != nil {
		exe, _ := os.Executable()
		nssmPath = filepath.Join(filepath.Dir(exe), "nssm.exe")
	}
	if _, err := os.Stat(nssmPath); err != nil {
		fmt.Println("[ERROR] nssm.exe not found. Please download NSSM and place it in the same directory as this binary or in your PATH.")
		os.Exit(2)
	}
	cmd := exec.Command(nssmPath, "remove", serviceName, "confirm")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		fmt.Println("[ERROR] Failed to uninstall Windows service:", err)
		os.Exit(3)
	}
	fmt.Println("[NOTIFY] Windows service uninstalled via NSSM.")
}

// macOS launchd install/uninstall (scaffold)
func installLaunchd() {
	exe, err := os.Executable()
	if err != nil {
		fmt.Println("[ERROR] Could not determine executable path:", err)
		os.Exit(1)
	}
	userHome, err := os.UserHomeDir()
	if err != nil {
		fmt.Println("[ERROR] Could not determine user home directory:", err)
		internal.SendSlackNotification("[ERROR] Could not determine user home directory: " + err.Error())
		os.Exit(2)
	}
		plistPath := filepath.Join(userHome, "Library", "LaunchAgents", "com.godockertools.autostart.plist")
		plist := fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.godockertools.autostart</string>
	<key>ProgramArguments</key>
	<array>
		<string>%s</string>
		<string>autostart</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
`, exe)
		msg := fmt.Sprintf("[NOTIFY] Launchd plist will be written to: %s", plistPath)
		internal.SendSlackNotification(msg)
	if err := os.WriteFile(plistPath, []byte(plist), 0644); err != nil {
		fmt.Println("[ERROR] Failed to write launchd plist:", err)
		os.Exit(3)
	}
	cmd := exec.Command("launchctl", "load", plistPath)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		fmt.Println("[ERROR] Failed to load launchd agent:", err)
		os.Exit(4)
	}
	fmt.Println("[NOTIFY] macOS launchd agent installed and loaded.")
}

func uninstallLaunchd() {
	userHome, err := os.UserHomeDir()
	if err != nil {
		fmt.Println("[ERROR] Could not determine user home directory:", err)
		os.Exit(1)
	}
	plistPath := filepath.Join(userHome, "Library", "LaunchAgents", "com.godockertools.autostart.plist")
	cmd := exec.Command("launchctl", "unload", plistPath)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	_ = cmd.Run() // ignore error if not loaded
	if err := os.Remove(plistPath); err != nil {
		fmt.Println("[ERROR] Failed to remove launchd plist:", err)
		os.Exit(2)
	}
	fmt.Println("[NOTIFY] macOS launchd agent unloaded and removed.")
}

func installAutostart() {
	// Example: create a systemd service file for autostart
	if runtime.GOOS != "linux" {
		fmt.Println("[WARN] Autostart deployment is only supported on Linux/systemd. Skipping.")
		return
	}
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
	if runtime.GOOS != "linux" {
		fmt.Println("[WARN] Autostart uninstall is only supported on Linux/systemd. Skipping.")
		return
	}
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
