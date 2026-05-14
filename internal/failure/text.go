package failure

import (
	"regexp"
	"strings"
)

var secretPatterns = []*regexp.Regexp{
	regexp.MustCompile(`(?i)(password|passwd|token|secret|api[_-]?key)=([^ \n]+)`),
	regexp.MustCompile(`(?i)(Authorization:\s*Bearer\s+)[A-Za-z0-9._~+/=-]+`),
	regexp.MustCompile(`(?s)-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----`),
}

func MaskSecrets(input string) string {
	output := input

	for _, pattern := range secretPatterns {
		output = pattern.ReplaceAllStringFunc(output, func(match string) string {
			if strings.Contains(strings.ToUpper(match), "PRIVATE KEY") {
				return "[REDACTED PRIVATE KEY]"
			}

			if strings.HasPrefix(strings.ToLower(match), "authorization") {
				return regexp.MustCompile(`(?i)(Authorization:\s*Bearer\s+).*`).
					ReplaceAllString(match, `${1}****`)
			}

			return regexp.MustCompile(`(?i)^([^=]+)=.*$`).
				ReplaceAllString(match, `${1}=****`)
		})
	}

	return output
}

func TruncateTrace(trace string, maxLines int, maxChars int) (string, bool) {
	lines := strings.Split(trace, "\n")
	trimmed := false

	if len(lines) > maxLines {
		lines = lines[len(lines)-maxLines:]
		trimmed = true
	}

	result := strings.Join(lines, "\n")

	if len(result) > maxChars {
		result = result[len(result)-maxChars:]
		trimmed = true
	}

	return strings.TrimSpace(result), trimmed
}

func FindErrorMessage(logText string) string {
	lines := strings.Split(logText, "\n")

	keywords := []string{
		"error",
		"failed",
		"fatal",
		"exception",
		"panic",
		"denied",
		"timeout",
		"exit status",
	}

	for i := len(lines) - 1; i >= 0; i-- {
		line := strings.TrimSpace(lines[i])
		lower := strings.ToLower(line)

		for _, keyword := range keywords {
			if strings.Contains(lower, keyword) {
				return line
			}
		}
	}

	return "No clear error line found"
}
