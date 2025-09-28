import (
	"archive/tar"
	"compress/gzip"
	"io"
)
// TarGzVolume backs up a Docker volume to a .tar.gz file using Go-native code
func TarGzVolume(volumeName, backupFile string, logger *log.Logger) error {
	volumePath := filepath.Join("/var/lib/docker/volumes", volumeName, "_data")
	f, err := os.Create(backupFile)
	if err != nil {
		return err
	}
	defer f.Close()
	gz := gzip.NewWriter(f)
	defer gz.Close()
	tarWriter := tar.NewWriter(gz)
	defer tarWriter.Close()
	err = filepath.Walk(volumePath, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		header, err := tar.FileInfoHeader(info, "")
		if err != nil {
			return err
		}
		relPath, err := filepath.Rel(volumePath, path)
		if err != nil {
			return err
		}
		header.Name = relPath
		if err := tarWriter.WriteHeader(header); err != nil {
			return err
		}
		if info.Mode().IsRegular() {
			file, err := os.Open(path)
			if err != nil {
				return err
			}
			defer file.Close()
			_, err = io.Copy(tarWriter, file)
			if err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		logger.Printf("Failed to tar volume %s: %v", volumeName, err)
		return err
	}
	logger.Printf("Backed up volume %s to %s (Go-native)", volumeName, backupFile)
	return nil
}
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
	// List volumes using Docker SDK
	volumes, err := dockerHelper.cli.VolumeList(nil, nil)
	if err != nil {
		return fmt.Errorf("failed to list volumes: %w", err)
	}
	for _, vol := range volumes.Volumes {
		backupFile := filepath.Join(conf.BackupDir, fmt.Sprintf("%s_%s.tar.gz", vol.Name, time.Now().Format("20060102T150405")))
		// Use cross-platform helper for all platforms
		err := BackupVolumeCrossPlatform(dockerHelper.cli, vol.Name, backupFile, logger)
		if err != nil {
			logger.Printf("Failed to backup volume %s: %v", vol.Name, err)
			continue
		}

		// Backup rotation logic
		if conf.BackupRotationCount > 0 {
			pattern := fmt.Sprintf("%s_*.tar.gz", vol.Name)
			matches, err := filepath.Glob(filepath.Join(conf.BackupDir, pattern))
			if err != nil {
				logger.Printf("Failed to list backups for volume %s: %v", vol.Name, err)
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
					_, err := fmt.Sscanf(base, vol.Name+"_%14s.tar.gz", &tstr)
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
