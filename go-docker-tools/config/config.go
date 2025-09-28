package config

import (
	"github.com/spf13/viper"
)

type Config struct {
	StateDir   string
	StateFile  string
	LogFile    string
	BackupDir  string
	BackupRotationCount int
	DockerDesktopUser string
	SystemDockerSocket string
	DockerDesktopSocketTemplate string
}

func LoadConfig() (*Config, error) {
	viper.SetConfigName("saver")
	viper.AddConfigPath("/etc/docker-state-saver/")
	viper.AddConfigPath(".")
	viper.AutomaticEnv()
	if err := viper.ReadInConfig(); err != nil {
		return nil, err
	}
	return &Config{
		StateDir:   viper.GetString("STATE_DIR"),
		StateFile:  viper.GetString("STATE_FILE"),
		LogFile:    viper.GetString("LOG_FILE"),
		BackupDir:  viper.GetString("BACKUP_DIR"),
		BackupRotationCount: viper.GetInt("BACKUP_ROTATION_COUNT"),
		DockerDesktopUser: viper.GetString("DOCKER_DESKTOP_USER"),
		SystemDockerSocket: viper.GetString("SYSTEM_DOCKER_SOCKET"),
		DockerDesktopSocketTemplate: viper.GetString("DOCKER_DESKTOP_SOCKET_TEMPLATE"),
	}, nil
}
