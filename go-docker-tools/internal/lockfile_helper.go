package internal

import (
	"github.com/gofrs/flock"
)

// NewLockfileHelper is an alias for NewLockfile for compatibility with cmd package
func NewLockfileHelper(path string) *Lockfile {
	return NewLockfile(path)
}

type Lockfile struct {
	fl *flock.Flock
}

func NewLockfile(path string) *Lockfile {
	return &Lockfile{fl: flock.New(path)}
}

func (l *Lockfile) TryLock() bool {
	locked, _ := l.fl.TryLock()
	return locked
}

func (l *Lockfile) Unlock() {
	l.fl.Unlock()
}
