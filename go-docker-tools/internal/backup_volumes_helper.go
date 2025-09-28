package internal

import (
	"fmt"
	"go-docker-tools/config"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"time"
)

func BackupVolumesHelper(conf *config.Config, dockerHelper *DockerHelper, logger *log.Logger) error {
	// List volumes using Docker CLI (for simplicity)
	cmd := exec.Command("docker", "volume", "ls", "-q")
	output, err := cmd.Output()
	if err != nil {
		return fmt.Errorf("failed to list volumes: %w", err)
	}
	volumes := []string{}
	for _, line := range splitLines(string(output)) {
		if line != "" {
			volumes = append(volumes, line)
		}
	}
	for _, vol := range volumes {
		backupFile := filepath.Join(conf.BackupDir, fmt.Sprintf("%s_%s.tar.gz", vol, time.Now().Format("20060102T150405")))
		cmd := exec.Command("docker", "run", "--rm", "-v", vol+":/volume", "-v", conf.BackupDir+":/backup", "alpine", "tar", "czf", "/backup/"+filepath.Base(backupFile), "-C", "/volume", ".")
		if err := cmd.Run(); err != nil {
			logger.Printf("Failed to backup volume %s: %v", vol, err)
			continue
		}
		logger.Printf("Backed up volume %s to %s", vol, backupFile)

		// Backup rotation logic
		if conf.BackupRotationCount > 0 {
			pattern := fmt.Sprintf("%s_*.tar.gz", vol)
			matches, err := filepath.Glob(filepath.Join(conf.BackupDir, pattern))
			if err != nil {
				logger.Printf("Failed to list backups for volume %s: %v", vol, err)
				continue
			}
			if len(matches) > conf.BackupRotationCount {
				type fileInfo struct {
					path string
					time time.Time
				}
				var infos []fileInfo
				for _, f := range matches {
					base := filepath.Base(f)
					// Expect format: vol_YYYYMMDDTHHMMSS.tar.gz
					var t time.Time
					var tstr string
					_, err := fmt.Sscanf(base, vol+"_%14s.tar.gz", &tstr)
					if err == nil {
						t, _ = time.Parse("20060102T150405", tstr)
					} else {
						fi, err := os.Stat(f)
						if err == nil {
							t = fi.ModTime()
						}
					}
					infos = append(infos, fileInfo{f, t})
				}
				// Sort by time ascending (oldest first)
				sort.Slice(infos, func(i, j int) bool { return infos[i].time.Before(infos[j].time) })
				for i := 0; i < len(infos)-conf.BackupRotationCount; i++ {
					os.Remove(infos[i].path)
					logger.Printf("Removed old backup: %s", infos[i].path)
				}
			}
		}
	}
	return nil
}

func splitLines(s string) []string {
	lines := []string{}
	start := 0
	for i, c := range s {
		if c == '\n' {
			lines = append(lines, s[start:i])
			start = i + 1
		}
	}
	if start < len(s) {
		lines = append(lines, s[start:])
	}
	return lines
}
