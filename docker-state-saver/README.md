# Docker State Saver

A robust, modular Bash tool for saving and restoring the running state of Docker containers across system reboots. Designed for Ubuntu 24.04 LTS, it supports both system Docker and Docker Desktop, with all configuration centralized in a sourceable `.conf` file. The script is production-ready, security-hardened, and supports both automated and manual operation.

## Features
- Saves the list of running (or all) containers for all Docker daemons (system and Docker Desktop)
- Restores containers on boot, matching the saved state
- Manual save and restore commands for on-demand use
- All configuration in a single, sourceable config file
- Robust logging and error handling
- Security best practices: file permissions, config validation, log sanitization
- Flexible CLI with many flags for advanced use

## Installation
1. Place the script and its config (`saver.conf`) in a secure directory (e.g., `/etc/docker-state-saver/`).
2. Ensure the script is executable: `chmod +x docker-state-saver.sh`
3. (Optional) Set up a systemd service or cron job to run the script on shutdown/startup.
4. Use the provided installer/uninstaller scripts if available.

## Usage

Run the script directly or via a symlink (e.g., `/usr/local/bin/docker-save`).

```sh
sudo ./docker-state-saver.sh [--config <file>] [--log <file>] <command> [flags]
```

### Global Flags
- `--config <file>`: Use an alternate config file (default: `/etc/docker-state-saver/saver.conf`)
- `--log <file>`: Override the log file location
- `--help`, `-h`: Show help and usage

### Commands and Flags

#### save
Save the current state of running containers (or all containers).

Flags:
- `--all`, `-a`: Save all containers, not just running ones
- `--filter <pattern>`: Only save containers matching a name or label pattern
- `--dry-run`: Show what would be saved, but don’t actually write the state file
- `--verbose`, `-v`: Output detailed information during save

#### restore
Restore containers to the saved state.

Flags:
- `--force`, `-f`: Force start containers even if already running
- `--skip-missing`: Skip containers that no longer exist without error
- `--dry-run`: Show what would be restored, but don’t actually start containers
- `--verbose`, `-v`: Output detailed information during restore

#### manual-save
Manual version of `save`, with the same flags as above. Intended for on-demand use.

#### checkpoint-restore
Manual version of `restore`, with additional options.

Flags:
- `--force`, `-f`: Force start containers even if already running
- `--skip-missing`: Skip containers that no longer exist without error
- `--dry-run`: Show what would be restored, but don’t actually start containers
- `--rollback <file>`: Restore from a specific previous state file
- `--verbose`, `-v`: Output detailed information during restore

## Example Usage

Save running containers:
```sh
sudo ./docker-state-saver.sh save
```

Save all containers, with verbose output:
```sh
sudo ./docker-state-saver.sh save --all --verbose
```

Restore containers, skipping missing ones:
```sh
sudo ./docker-state-saver.sh restore --skip-missing
```

Manual save with a filter:
```sh
sudo ./docker-state-saver.sh manual-save --filter myapp
```

Manual checkpoint restore from a previous file:
```sh
sudo ./docker-state-saver.sh checkpoint-restore --rollback /path/to/old_state.txt
```

## Security Notes
- Only trusted users should be able to modify the config file and state directory.
- The script enforces strict file permissions and validates config file ownership.
- All logs are sanitized to prevent log injection.

## Configuration
Edit the `saver.conf` file to set paths, users, and other options. Example:

```sh
STATE_DIR="/var/lib/docker-state-saver"
STATE_FILE="$STATE_DIR/state.txt"
LOG_FILE="/var/log/docker-state-saver.log"
DOCKER_DESKTOP_USER="myuser"  # Optional, for Docker Desktop integration
```

## Troubleshooting
- Check the log file (default: `/var/log/docker-state-saver.log`) for errors.
- Ensure the config file is owned by root or the current user and is not writable by others.
- Make sure the script has execute permissions and is run with sufficient privileges to access Docker.

## License
MIT License

## Author
FabulaNox
