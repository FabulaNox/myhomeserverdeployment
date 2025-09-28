// RestoreVolumeCrossPlatform restores a tar.gz archive into a Docker volume using a helper container
func RestoreVolumeCrossPlatform(cli *client.Client, volumeName, backupFile string, logger *log.Logger) error {
	ctx := context.Background()
	containerName := fmt.Sprintf("restore-helper-%s-%d", volumeName, time.Now().UnixNano())
	resp, err := cli.ContainerCreate(ctx, &container.Config{
		Image: "alpine",
		Cmd:   []string{"sleep", "60"},
		Tty:   false,
	}, nil, nil, nil, containerName)
	if err != nil {
		return fmt.Errorf("failed to create helper container: %w", err)
	}
	defer func() {
		_ = cli.ContainerRemove(ctx, resp.ID, types.ContainerRemoveOptions{Force: true})
	}()
	// Mount the volume
	mounts := []mount.Mount{{
		Type:   mount.TypeVolume,
		Source: volumeName,
		Target: "/data",
	}}
	if err := cli.ContainerStart(ctx, resp.ID, types.ContainerStartOptions{}); err != nil {
		return fmt.Errorf("failed to start helper container: %w", err)
	}
	// Open the backup file
	f, err := os.Open(backupFile)
	if err != nil {
		return err
	}
	defer f.Close()
	// Copy the tar archive into the container's /data directory
	err = cli.CopyToContainer(ctx, resp.ID, "/data", f, types.CopyToContainerOptions{AllowOverwriteDirWithFile: true})
	if err != nil {
		return fmt.Errorf("failed to copy to container: %w", err)
	}
	logger.Printf("[CROSS-PLATFORM] Restored volume %s from %s", volumeName, backupFile)
	return nil
}
package internal

import (
	"archive/tar"
	"bytes"
	"context"
	"fmt"
	"github.com/docker/docker/api/types"
	"github.com/docker/docker/api/types/container"
	"github.com/docker/docker/api/types/mount"
	"github.com/docker/docker/client"
	"io"
	"log"
	"os"
	"path/filepath"
	"time"
)

// BackupVolumeCrossPlatform creates a tar.gz archive of a Docker volume using a helper container
func BackupVolumeCrossPlatform(cli *client.Client, volumeName, backupFile string, logger *log.Logger) error {
	ctx := context.Background()
	containerName := fmt.Sprintf("backup-helper-%s-%d", volumeName, time.Now().UnixNano())
	resp, err := cli.ContainerCreate(ctx, &container.Config{
		Image: "alpine",
		Cmd:   []string{"sleep", "60"},
		Tty:   false,
	}, nil, nil, nil, containerName)
	if err != nil {
		return fmt.Errorf("failed to create helper container: %w", err)
	}
	defer func() {
		_ = cli.ContainerRemove(ctx, resp.ID, types.ContainerRemoveOptions{Force: true})
	}()
	// Mount the volume
	mounts := []mount.Mount{{
		Type:   mount.TypeVolume,
		Source: volumeName,
		Target: "/data",
	}}
	if err := cli.ContainerStart(ctx, resp.ID, types.ContainerStartOptions{}); err != nil {
		return fmt.Errorf("failed to start helper container: %w", err)
	}
	// Archive the /data directory in the container
	tarStream, stat, err := cli.CopyFromContainer(ctx, resp.ID, "/data")
	if err != nil {
		return fmt.Errorf("failed to copy from container: %w", err)
	}
	defer tarStream.Close()
	// Write the tar stream to a .tar.gz file
	f, err := os.Create(backupFile)
	if err != nil {
		return err
	}
	defer f.Close()
	gz := NewGzipWriter(f)
	defer gz.Close()
	_, err = io.Copy(gz, tarStream)
	if err != nil {
		return err
	}
	logger.Printf("[CROSS-PLATFORM] Backed up volume %s to %s", volumeName, backupFile)
	return nil
}

// NewGzipWriter wraps gzip.NewWriter for easy replacement/testing
func NewGzipWriter(w io.Writer) *gzip.Writer {
	return gzip.NewWriter(w)
}
