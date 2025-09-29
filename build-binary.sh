echo "Select target platform for build:"
echo "1) linux/amd64"
echo "2) linux/arm64"
echo "3) windows/amd64"
echo "4) darwin/amd64"
echo "5) darwin/arm64"
echo "6) custom (enter GOOS/GOARCH manually)"
echo

set -e

# Show vendor patch warning and code
PATCH_FILE="$(dirname "$0")/go-docker-tools/vendor/github.com/docker/distribution/reference/reference_deprecated.go"
echo "\n==== VENDOR PATCH NOTICE ===="
echo "This project uses a patched vendor file for SplitHostname.\n"
echo "Relevant code from vendor/github.com/docker/distribution/reference/reference_deprecated.go:" 
awk '/func SplitHostname\(/, /}/ { print }' "$PATCH_FILE"
echo "==== END PATCH NOTICE ===="

echo
echo "Select target platform for build:"
echo "1) linux/amd64"
echo "2) linux/arm64"
echo "3) windows/amd64"
echo "4) darwin/amd64"
echo "5) darwin/arm64"
echo "6) custom (enter GOOS/GOARCH manually)"
echo
read -p "Enter choice [1-6]: " choice

case $choice in
  1)
    GOOS=linux GOARCH=amd64 ;;
  2)
    GOOS=linux GOARCH=arm64 ;;
  3)
    GOOS=windows GOARCH=amd64 ;;
  4)
    GOOS=darwin GOARCH=amd64 ;;
  5)
    GOOS=darwin GOARCH=arm64 ;;
  6)
    read -p "Enter GOOS: " GOOS
    read -p "Enter GOARCH: " GOARCH
    ;;
  *)
    echo "Invalid choice" >&2
    exit 1
    ;;
esac

read -p "Enter output binary name (no extension for unix, .exe for windows): " OUTNAME

CMD_DIR="$(dirname "$0")/go-docker-tools/cmd"
VENDOR_DIR="$(dirname "$0")/go-docker-tools/vendor"

# Show the build command
BUILD_CMD="GOOS=$GOOS GOARCH=$GOARCH go build -mod=vendor -o $OUTNAME $CMD_DIR"
echo "\nRunning: $BUILD_CMD\n"

# Actually run the build
GOOS=$GOOS GOARCH=$GOARCH go build -mod=vendor -o "$OUTNAME" "$CMD_DIR"

echo "Build complete: $OUTNAME"
