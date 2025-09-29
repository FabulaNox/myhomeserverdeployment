package internal

import (
	"archive/tar"
	"compress/gzip"
	"io"
	"log"
	"os"
	"path/filepath"

	"github.com/FabulaNox/go-docker-tools/config"
)

// TarGzVolume backs up a Docker volume to a .tar.gz file using Go-native code
func TarGzVolume(volumeName, backupFile string, logger *log.Logger) error {
	volumePath := filepath.Join("/var/lib/docker/volumes", volumeName, "_data")
	f, ferr := os.Create(backupFile)
	if ferr != nil {
		return ferr
	}
	defer f.Close()
	gz := gzip.NewWriter(f)
	defer gz.Close()
	tarWriter := tar.NewWriter(gz)
	defer tarWriter.Close()
	walkErr := filepath.Walk(volumePath, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		header, herr := tar.FileInfoHeader(info, "")
		if herr != nil {
			return herr
		}
		relPath, rerr := filepath.Rel(volumePath, path)
		if rerr != nil {
			return rerr
		}
		header.Name = relPath
		if wherr := tarWriter.WriteHeader(header); wherr != nil {
			return wherr
		}
		if info.Mode().IsRegular() {
			file, oerr := os.Open(path)
			if oerr != nil {
				return oerr
			}
			defer file.Close()
			if _, cerr := io.Copy(tarWriter, file); cerr != nil {
				return cerr
			}
		}
		return nil
	})
	if walkErr != nil {
		logger.Printf("Failed to tar volume %s: %v", volumeName, walkErr)
		return walkErr
	}
	logger.Printf("Backed up volume %s to %s (Go-native)", volumeName, backupFile)
	return nil
}

// BackupVolumeCrossPlatform is a stub for now. Replace with actual implementation as needed.
func BackupVolumeCrossPlatform(cli interface{}, volumeName, backupFile string, logger *log.Logger) error {
	// This is a placeholder. Replace with Docker SDK logic if needed.
	return TarGzVolume(volumeName, backupFile, logger)
}
func BackupVolumesHelper(conf *config.Config, dockerHelper *DockerHelper, logger *log.Logger) error {
	// List volumes using Docker SDK
	// TODO: Replace with actual Docker SDK logic as needed
	// Example: volumes, vErr := dockerHelper.cli.VolumeList(context.Background(), types.VolumeListOptions{})
	// if vErr != nil {
	//     return fmt.Errorf("failed to list volumes: %w", vErr)
	// }
	// for _, vol := range volumes.Volumes {
	//     ...
	// }
	return nil
}
