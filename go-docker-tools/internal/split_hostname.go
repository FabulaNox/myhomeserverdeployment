package internal

import (
	"strings"

	"github.com/distribution/reference"
)

// SplitHostname splits a named reference into a hostname and the remainder.
// This is a local replacement for the missing reference.SplitHostname.
func SplitHostname(named reference.Named) (string, string) {
	name := named.Name()
	parts := strings.SplitN(name, "/", 2)
	if len(parts) < 2 || (!strings.Contains(parts[0], ".") && !strings.Contains(parts[0], ":") && parts[0] != "localhost") {
		return "", name
	}
	return parts[0], parts[1]
}
