# go-docker-tools

A Go-based replacement for the Docker state saver and automation scripts. This project provides full feature parity with the original Bash scripts, including:

- Docker state save/restore (system and Docker Desktop)
- Manual and automated operations
- Volume backup and rotation
- Lockfile handling
- Logging
- Config file parsing
- Socket/process checks
- Cross-platform support (Linux/macOS)

## Structure
- `cmd/` - Main commands (save, restore, backup, autostart, etc.)
- `internal/` - Core logic and helpers
- `config/` - Configuration parsing

## Usage
Build with `go build -o docker-tools` and run with the desired command.

## License
MIT
