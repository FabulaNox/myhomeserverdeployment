#!/bin/bash
# Install Go SAST tools for GoLand and CI
set -e

echo "Installing gosec..."
go install github.com/securego/gosec/v2/cmd/gosec@latest

echo "Installing staticcheck..."
go install honnef.co/go/tools/cmd/staticcheck@latest

echo "Installing govulncheck..."
go install golang.org/x/vuln/cmd/govulncheck@latest

echo "Installing golangci-lint..."
go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest

echo "All SAST tools installed. Add $GOPATH/bin to your PATH if needed."
