#!/usr/bin/env bash
# docker-check-binary.sh
# Checks if the docker binary is available and executable
# Usage: source or execute this script, sets DOCKER_BINARY_OK=1 if found, 0 if not

DOCKER_BINARY_OK=0
if command -v docker >/dev/null 2>&1; then
    DOCKER_BINARY_OK=1
else
    echo "ERROR: docker binary not found in PATH." >&2
    DOCKER_BINARY_OK=0
fi
export DOCKER_BINARY_OK
