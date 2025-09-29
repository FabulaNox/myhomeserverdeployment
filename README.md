# Docker Backup/Restore Script Usage

## Quick Start

**If your script path contains spaces:**

Run commands like this:

```bash
sudo bash 'Server script tools/Docker tools/docker_backup_restore.sh' -restart-container <name>
sudo bash 'Server script tools/Docker tools/docker_backup_restore.sh' -restart-all
```

**Recommended: Create a symlink for easy usage**

```bash
sudo ln -s "$(pwd)/Server script tools/Docker tools/docker_backup_restore.sh" /usr/local/bin/docker-restore
```
Then you can use:

```bash
sudo docker-restore -restart-container <name>
sudo docker-restore -restart-all
```

## Notes
- All commands require sudo/root privileges.
- If a container fails to restart (e.g., port conflict), check the error message and resolve the issue before retrying.
# myhomeserverdeployment
Fast move for repo to home server setup scripts
Different sections will be broken down as the setup needs grow and also I learn how to better script