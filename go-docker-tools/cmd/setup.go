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
		       fmt.Fprintln(os.Stderr, "[ERROR] Failed to write default config:", err)
		       os.Exit(2)
	       }
	       fmt.Println("[NOTIFY] Default config created. Please review and edit as needed.")
	       return
       }
       // Validate config fields (basic)
       if conf.StateDir == "" || conf.BackupDir == "" {
	       fmt.Fprintln(os.Stderr, "[ERROR] Config missing required fields: STATE_DIR or BACKUP_DIR")
	       os.Exit(3)
       }
       // Ensure directories exist
       dirs := []string{conf.StateDir, conf.BackupDir}
       for _, dir := range dirs {
	       if dir == "" {
		       continue
	       }
	       if err := os.MkdirAll(dir, 0755); err != nil {
		       fmt.Fprintf(os.Stderr, "[ERROR] Failed to create directory %s: %v\n", dir, err)
		       os.Exit(4)
	       }
       }
       fmt.Println("[NOTIFY] Setup complete. All required directories exist.")
}
