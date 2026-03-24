// destructive_guard.go — Claude Code PreToolUse hook in Go
//
// Blocks rm -rf /, git reset --hard, git clean -fd, and similar
// destructive commands. Exit code 2 = block, 0 = allow.
//
// Build: go build -o destructive-guard destructive_guard.go
// Usage in settings.json:
//   {"type": "command", "command": "/path/to/destructive-guard"}
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"regexp"
	"strings"
)

type HookInput struct {
	ToolInput struct {
		Command string `json:"command"`
	} `json:"tool_input"`
}

var dangerousPatterns = []*regexp.Regexp{
	regexp.MustCompile(`\brm\s+.*-rf\s+(/|~/?\s*$|\.\./)`),
	regexp.MustCompile(`\bgit\s+reset\s+--hard`),
	regexp.MustCompile(`\bgit\s+clean\s+-[a-zA-Z]*f`),
	regexp.MustCompile(`\bgit\s+checkout\s+--force`),
	regexp.MustCompile(`\bchmod\s+(-R\s+)?777\s+/`),
	regexp.MustCompile(`\bfind\s+/\s+-delete`),
	regexp.MustCompile(`Remove-Item.*-Recurse.*-Force`),
	regexp.MustCompile(`--no-preserve-root`),
	regexp.MustCompile(`\bsudo\s+mkfs\b`),
}

func main() {
	data, err := io.ReadAll(os.Stdin)
	if err != nil {
		os.Exit(0) // Don't block on read error
	}

	var input HookInput
	if err := json.Unmarshal(data, &input); err != nil {
		os.Exit(0) // Don't block on parse error
	}

	cmd := input.ToolInput.Command
	if cmd == "" {
		os.Exit(0)
	}

	// Skip if command is in an echo/printf context
	lower := strings.ToLower(cmd)
	if strings.HasPrefix(strings.TrimSpace(lower), "echo ") ||
		strings.HasPrefix(strings.TrimSpace(lower), "printf ") {
		os.Exit(0)
	}

	for _, pattern := range dangerousPatterns {
		if pattern.MatchString(cmd) {
			fmt.Fprintf(os.Stderr, "BLOCKED: Dangerous command detected\nCommand: %s\n", cmd)
			os.Exit(2)
		}
	}

	os.Exit(0)
}
