package main

import (
	"os"

	"github.com/Er-rdhtiwari/slack-integration/pkg/captureerror"
)

var (
	version = "dev"
	commit  = "unknown"
	date    = "unknown"
)

func main() {
	captureerror.SetVersion(version, commit, date)
	os.Exit(captureerror.Execute(os.Args[1:]))
}
