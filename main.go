package main

import (
	"fmt"

	"github.com/Er-rdhtiwari/slack-integration/internal/cli"
	"github.com/Er-rdhtiwari/slack-integration/internal/parser"
)

func main() {
	input := cli.ReadFlags()

	event, err := parser.BuildEvent(input)

	if err != nil {
		fmt.Println("Error:", err)
		return
	}
	fmt.Printf("%+v \n", event)

	fmt.Printf("%+v \n", input)
}
