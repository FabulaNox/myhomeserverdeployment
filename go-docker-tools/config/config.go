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

	// Additional fields for full config parity
	DockerHost string
	ServiceFile string
	AutoscriptDir string
	ContainerList string
	ErrorLog string
	HealthLog string
	Lockfile string
	ImageBackupDir string
	ConfigBackupDir string
	JSONBackupFile string
	RestoreLog string
	SystemdService string
	BinPath string
	LockfileScript string
	DeployScript string
	AutostartScript string

	// Path to a hook script for pre/post/notify events
	HookScript string
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

		DockerHost: viper.GetString("DOCKER_HOST"),
		ServiceFile: viper.GetString("SERVICE_FILE"),
		AutoscriptDir: viper.GetString("AUTOSCRIPT_DIR"),
		ContainerList: viper.GetString("CONTAINER_LIST"),
		ErrorLog: viper.GetString("ERROR_LOG"),
		HealthLog: viper.GetString("HEALTH_LOG"),
		Lockfile: viper.GetString("LOCKFILE"),
		ImageBackupDir: viper.GetString("IMAGE_BACKUP_DIR"),
		ConfigBackupDir: viper.GetString("CONFIG_BACKUP_DIR"),
		JSONBackupFile: viper.GetString("JSON_BACKUP_FILE"),
		RestoreLog: viper.GetString("RESTORE_LOG"),
		SystemdService: viper.GetString("SYSTEMD_SERVICE"),
		BinPath: viper.GetString("BIN_PATH"),
		LockfileScript: viper.GetString("LOCKFILE_SCRIPT"),
		DeployScript: viper.GetString("DEPLOY_SCRIPT"),
		AutostartScript: viper.GetString("AUTOSTART_SCRIPT"),

		HookScript: viper.GetString("HOOK_SCRIPT"),
	}, nil
}
