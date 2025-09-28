package cmd

import (
	"fmt"
	"go-docker-tools/config"
	"os"
)

// SetupCommand ensures required directories and files exist, and creates default config if missing.
func SetupCommand() {
	conf, err := config.LoadConfig()
	if err != nil {
		fmt.Println("No config found, creating default config file: ./saver.yaml")
		defaultConfig := []byte(`# Default config for go-docker-tools\nSTATE_DIR: ./state\nSTATE_FILE: state.json\nLOG_FILE: go-docker-tools.log\nBACKUP_DIR: ./backups\nBACKUP_ROTATION_COUNT: 7\n`)
		err = os.WriteFile("saver.yaml", defaultConfig, 0644)
		if err != nil {
			fmt.Println("Failed to write default config:", err)
			os.Exit(1)
		}
		fmt.Println("Default config created. Please review and edit as needed.")
		return
	}
	// Ensure directories exist
	dirs := []string{conf.StateDir, conf.BackupDir}
	for _, dir := range dirs {
		if dir == "" {
			continue
		}
		if err := os.MkdirAll(dir, 0755); err != nil {
			fmt.Printf("Failed to create directory %s: %v\n", dir, err)
			os.Exit(1)
		}
	}
	fmt.Println("Setup complete. All required directories exist.")
}
