package main

import (
	"fmt"

	"github.com/Er-rdhtiwari/slack-integration/internal/cli"
)

func main() {
	input := cli.ReadFlags()
	fmt.Printf("%+v \n",input)
}
