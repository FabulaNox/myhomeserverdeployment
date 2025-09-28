package internal

import (
	"os"
	"path/filepath"
	"runtime"
)

// GetDefaultDockerSocket returns the default Docker socket path for the current platform
func GetDefaultDockerSocket() string {
	switch runtime.GOOS {
	case "windows":
		return `npipe:////./pipe/docker_engine`
	case "darwin":
		return "/var/run/docker.sock" // Docker Desktop for Mac
	default:
		return "/var/run/docker.sock"
	}
}

// GetDefaultConfigDir returns a suitable config directory for the current platform
func GetDefaultConfigDir() string {
	home, _ := os.UserHomeDir()
	switch runtime.GOOS {
	case "windows":
		if appdata := os.Getenv("APPDATA"); appdata != "" {
			return filepath.Join(appdata, "go-docker-tools")
		}
		return filepath.Join(home, "AppData", "Roaming", "go-docker-tools")
	case "darwin":
		return filepath.Join(home, "Library", "Application Support", "go-docker-tools")
	default:
		return filepath.Join(home, ".config", "go-docker-tools")
	}
}

// GetDefaultBackupDir returns a suitable backup directory for the current platform
func GetDefaultBackupDir() string {
	return filepath.Join(GetDefaultConfigDir(), "backups")
}
