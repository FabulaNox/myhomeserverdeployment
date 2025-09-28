package internal

import (
	"github.com/gofrs/flock"
)

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
