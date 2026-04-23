package cli

import (
	"flag"
)

type InputFlags struct {
	User  string
	Event string
	Repo  string
}

func ReadFlags() InputFlags {
	user := flag.String("user", "", "name of the user")
	event := flag.String("event", "login", "provide event type")
	repo := flag.String("repo", "slack-integration", "provide repo name")

	flag.Parse()

	return InputFlags{
		User:  *user,
		Event: *event,
		Repo:  *repo,
	}
}
