package internal

import (
	"archive/tar"
	"compress/gzip"
	"context"
	"io"
	"log"
	"os"
	"path/filepath"
	"sort"

	"github.com/FabulaNox/go-docker-tools/config"
	"github.com/docker/docker/api/types/volume"
)

// BackupVolumesToFile backs up all volumes to a single tar.gz file
func BackupVolumesToFile(conf *config.Config, dockerHelper *DockerHelper, logger *log.Logger, backupFile string) error {
	// Go-native: tar/gzip all volumes into one archive
	f, err := os.Create(backupFile)
	if err != nil {
		return err
	}
	defer f.Close()
	gz := gzip.NewWriter(f)
	defer gz.Close()
	tarWriter := tar.NewWriter(gz)
	defer tarWriter.Close()

	// import "context" and "github.com/docker/docker/api/types" at the top if not present
	volumes, err := dockerHelper.cli.VolumeList(context.Background(), volume.ListOptions{})
	if err != nil {
		return err
	}
	for _, vol := range volumes.Volumes {
		volumePath := filepath.Join("/var/lib/docker/volumes", vol.Name, "_data")
		err = filepath.Walk(volumePath, func(path string, info os.FileInfo, err error) error {
			if err != nil {
				return err
			}
			header, err := tar.FileInfoHeader(info, "")
			if err != nil {
				return err
			}
			relPath, err := filepath.Rel("/var/lib/docker/volumes", path)
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
			logger.Printf("[ERROR] Failed to tar volume %s: %v", vol.Name, err)
			return err
		}
	}
	logger.Printf("[USER] Manual backup (Go-native) completed: %s", backupFile)
	return nil
}

// RotateManualBackups keeps only the most recent n manual backups
func RotateManualBackups(dir string, keep int, logger *log.Logger) {
	files, err := filepath.Glob(filepath.Join(dir, "manual_*.tar.gz"))
	if err != nil || len(files) <= keep {
		return
	}
	type fileInfo struct {
		path string
		time int64
	}
	var infos []fileInfo
	for _, f := range files {
		fi, err := os.Stat(f)
		if err == nil {
			infos = append(infos, fileInfo{f, fi.ModTime().Unix()})
		}
	}
	sort.Slice(infos, func(i, j int) bool { return infos[i].time < infos[j].time })
	for i := 0; i < len(infos)-keep; i++ {
		os.Remove(infos[i].path)
		logger.Println("[USER] Removed old manual backup:", infos[i].path)
	}
}
