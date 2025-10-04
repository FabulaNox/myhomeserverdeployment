# Go SAST (Static Application Security Testing) Tools for GoLand

To enhance security and code quality in your Go project, you can integrate the following SAST tools. These work well with GoLand and other JetBrains IDEs:

## 1. gosec
- **Purpose:** Scans Go code for common security issues (injection, hardcoded credentials, unsafe usage, etc.)
- **Install:**
  ```sh
  go install github.com/securego/gosec/v2/cmd/gosec@latest
  ```
- **Usage:**
  ```sh
  gosec ./...
  ```
- **GoLand Integration:**
  - Add a GoLand Run/Debug configuration for `gosec`.
  - Or, add as an External Tool (Settings > Tools > External Tools).

## 2. staticcheck
- **Purpose:** Advanced linter for bug-prone code, code smells, and security issues.
- **Install:**
  ```sh
  go install honnef.co/go/tools/cmd/staticcheck@latest
  ```
- **Usage:**
  ```sh
  staticcheck ./...
  ```
- **GoLand Integration:**
  - GoLand can run `staticcheck` as part of inspections (enable in Settings > Go > Linting).

## 3. govulncheck
- **Purpose:** Checks for known vulnerabilities in dependencies using the Go vulnerability database.
- **Install:**
  ```sh
  go install golang.org/x/vuln/cmd/govulncheck@latest
  ```
- **Usage:**
  ```sh
  govulncheck ./...
  ```
- **GoLand Integration:**
  - Add as an External Tool or run in terminal.

## 4. golangci-lint (meta-linter)
- **Purpose:** Runs multiple linters (including `gosec`, `staticcheck`, etc.) in one command.
- **Install:**
  ```sh
  go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
  ```
- **Usage:**
  ```sh
  golangci-lint run
  ```
- **GoLand Integration:**
  - GoLand can use `golangci-lint` as the main linter (Settings > Go > Linting).

---

## Recommended Setup
- Install all tools above.
- Enable `golangci-lint` in GoLand for real-time feedback.
- Run `gosec` and `govulncheck` before releases.

## References
- [gosec](https://github.com/securego/gosec)
- [staticcheck](https://staticcheck.io/)
- [govulncheck](https://pkg.go.dev/golang.org/x/vuln/cmd/govulncheck)
- [golangci-lint](https://golangci-lint.run/)
