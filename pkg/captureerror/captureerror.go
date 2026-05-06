package captureerror

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

const (
	defaultTimeoutSeconds  = 3600
	defaultMaxOutputBytes  = 65536
	defaultMaxCaptureBytes = 10485760
)

type versionInfo struct {
	Version string `json:"version"`
	Commit  string `json:"commit"`
	Date    string `json:"date"`
}

var buildInfo = versionInfo{
	Version: "dev",
	Commit:  "unknown",
	Date:    "unknown",
}

type options struct {
	strictLogErrors   bool
	streamOutput      bool
	includeStdout     bool
	includeStderr     bool
	timeoutSeconds    int
	maxOutputBytes    int64
	maxCaptureBytes   int64
	redactionFilePath string
	command           []string
}

func SetVersion(version, commit, date string) {
	buildInfo = versionInfo{
		Version: defaultString(version, "dev"),
		Commit:  defaultString(commit, "unknown"),
		Date:    defaultString(date, "unknown"),
	}
}

type streamCapture struct {
	mu        sync.Mutex
	buf       bytes.Buffer
	rawBytes  int64
	truncated bool
	maxBytes  int64
	onBytes   func(int64)
}

func (s *streamCapture) Write(p []byte) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	n := len(p)
	s.rawBytes += int64(n)
	if s.onBytes != nil {
		s.onBytes(int64(n))
	}

	remaining := s.maxBytes - int64(s.buf.Len())
	if remaining > 0 {
		writeLen := int64(n)
		if writeLen > remaining {
			writeLen = remaining
		}
		_, _ = s.buf.Write(p[:writeLen])
	}

	if int64(s.buf.Len()) < s.rawBytes {
		s.truncated = true
	}

	return n, nil
}

func (s *streamCapture) text() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.buf.String()
}

func (s *streamCapture) size() int64 {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.rawBytes
}

func (s *streamCapture) isTruncated() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.truncated
}

type logEntry struct {
	Index   int         `json:"index"`
	Stream  string      `json:"stream"`
	Level   string      `json:"level"`
	Message string      `json:"message"`
	Format  string      `json:"format"`
	Fields  interface{} `json:"fields,omitempty"`
}

var (
	errHelp            = errors.New("help requested")
	errorPrefixPattern = regexp.MustCompile(`(?i)^\s*(?:\[[^\]]+\]\s*)?(?:error|err|failed|failure|fatal|panic|exception)\b(?:\s*[:=-]|\s+|$)`)
	errorLevelPattern  = regexp.MustCompile(`(?i)^\s*(?:level|severity|log_level)\s*[:=]\s*['"]?(?:error|err|fatal|panic)['"]?\b`)
	stderrErrorPattern = regexp.MustCompile(`(?i)\b(command not found|no such file or directory|permission denied|not found|cannot|can't|invalid)\b`)
	warnPrefixPattern  = regexp.MustCompile(`(?i)^\s*(?:\[[^\]]+\]\s*)?(?:warn|warning|deprecationwarning)\b(?:\s*[:=-]|\s+|$)`)
	warnLevelPattern   = regexp.MustCompile(`(?i)^\s*(?:level|severity|log_level)\s*[:=]\s*['"]?(?:warn|warning)['"]?\b`)
	tracebackPattern   = regexp.MustCompile(`(?i)^\s*(?:traceback \(most recent call last\)|unhandled(?:promise)?rejection|panic:|fatal:)`)
	sensitiveField     = regexp.MustCompile(`(?i)(webhook|token|api[_-]?key|secret|password|passwd|pwd|authorization)`)
	sensitiveArg       = regexp.MustCompile(`(?i)^-{1,2}(?:slack-)?(?:webhook(?:-url)?|token|access-token|refresh-token|api-key|apikey|secret|password|passwd|pwd|authorization)$`)
)

type replacement struct {
	pattern     *regexp.Regexp
	replacement string
}

func Execute(args []string) int {
	opts, err := parseOptions(args)
	if err != nil {
		if errors.Is(err, errHelp) {
			return 0
		}
		fmt.Fprintln(os.Stderr, err.Error())
		return 64
	}

	replacements := defaultReplacements()
	replacements = appendCustomReplacements(replacements, opts.redactionFilePath)

	if len(opts.command) == 0 {
		result := missingCommandResult(opts)
		if err := printJSON(result); err != nil {
			return 70
		}
		return 64
	}

	result, exitCode := runCommand(opts, replacements)
	if err := printJSON(result); err != nil {
		return 70
	}
	return exitCode
}

func parseOptions(args []string) (options, error) {
	opts := options{
		strictLogErrors: true,
		streamOutput:    true,
		includeStdout:   false,
		includeStderr:   true,
		timeoutSeconds:  defaultTimeoutSeconds,
		maxOutputBytes:  envInt64("CAPTURE_ERROR_MAX_OUTPUT_BYTES", defaultMaxOutputBytes),
		maxCaptureBytes: envInt64("CAPTURE_ERROR_MAX_CAPTURE_BYTES", defaultMaxCaptureBytes),
		redactionFilePath: os.Getenv(
			"CAPTURE_ERROR_REDACTION_REGEX_FILE",
		),
	}

	for len(args) > 0 {
		switch args[0] {
		case "--strict-log-errors":
			opts.strictLogErrors = true
			args = args[1:]
		case "--exit-code-only":
			opts.strictLogErrors = false
			args = args[1:]
		case "--stream-output":
			opts.streamOutput = true
			args = args[1:]
		case "--no-stream-output":
			opts.streamOutput = false
			args = args[1:]
		case "--stdout":
			if len(args) < 2 {
				return opts, errors.New("Error: --stdout requires true or false.")
			}
			value, err := parseBool("--stdout", args[1])
			if err != nil {
				return opts, err
			}
			opts.includeStdout = value
			args = args[2:]
		case "--stderr":
			if len(args) < 2 {
				return opts, errors.New("Error: --stderr requires true or false.")
			}
			value, err := parseBool("--stderr", args[1])
			if err != nil {
				return opts, err
			}
			opts.includeStderr = value
			args = args[2:]
		case "--timeout":
			if len(args) < 2 {
				return opts, errors.New("Error: --timeout requires a positive integer number of seconds.")
			}
			value, err := parsePositiveInt(args[1])
			if err != nil {
				return opts, errors.New("Error: --timeout requires a positive integer number of seconds.")
			}
			opts.timeoutSeconds = value
			args = args[2:]
		case "--max-output-bytes":
			if len(args) < 2 {
				return opts, errors.New("Error: --max-output-bytes requires a positive integer number of bytes.")
			}
			value, err := parsePositiveInt64(args[1])
			if err != nil {
				return opts, errors.New("Error: --max-output-bytes requires a positive integer number of bytes.")
			}
			opts.maxOutputBytes = value
			args = args[2:]
		case "--max-capture-bytes":
			if len(args) < 2 {
				return opts, errors.New("Error: --max-capture-bytes requires a positive integer number of bytes.")
			}
			value, err := parsePositiveInt64(args[1])
			if err != nil {
				return opts, errors.New("Error: --max-capture-bytes requires a positive integer number of bytes.")
			}
			opts.maxCaptureBytes = value
			args = args[2:]
		case "--redaction-regex-file":
			if len(args) < 2 || args[1] == "" {
				return opts, errors.New("Error: --redaction-regex-file requires a file path.")
			}
			opts.redactionFilePath = args[1]
			args = args[2:]
		case "-h", "--help":
			showHelp()
			return opts, errHelp
		case "--version":
			printVersion()
			return opts, errHelp
		case "--":
			opts.command = args[1:]
			return opts, nil
		default:
			opts.command = args
			return opts, nil
		}
	}

	return opts, nil
}

func runCommand(opts options, replacements []replacement) (map[string]interface{}, int) {
	start := time.Now()
	startText := start.Format("2006-01-02T15:04:05-0700")

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	cmd := exec.CommandContext(ctx, opts.command[0], opts.command[1:]...)
	cmd.Stdin = os.Stdin
	isInteractiveStdin := stdinIsTerminal()
	if !isInteractiveStdin {
		cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	}

	var totalMu sync.Mutex
	totalCaptured := int64(0)
	captureLimitExceeded := false
	killOnce := sync.Once{}

	terminate := func() {
		killOnce.Do(func() {
			if cmd.Process == nil {
				return
			}
			pgid, err := syscall.Getpgid(cmd.Process.Pid)
			if err == nil && !isInteractiveStdin {
				_ = syscall.Kill(-pgid, syscall.SIGTERM)
			} else {
				_ = cmd.Process.Signal(syscall.SIGTERM)
			}
			time.Sleep(2 * time.Second)
			if err == nil && !isInteractiveStdin {
				_ = syscall.Kill(-pgid, syscall.SIGKILL)
			} else {
				_ = cmd.Process.Kill()
			}
		})
	}

	onBytes := func(n int64) {
		totalMu.Lock()
		totalCaptured += n
		overLimit := totalCaptured > opts.maxCaptureBytes && !captureLimitExceeded
		if overLimit {
			captureLimitExceeded = true
		}
		totalMu.Unlock()

		if overLimit {
			terminate()
		}
	}

	stdoutCapture := &streamCapture{maxBytes: opts.maxOutputBytes, onBytes: onBytes}
	stderrCapture := &streamCapture{maxBytes: opts.maxOutputBytes, onBytes: onBytes}

	stdoutWriter := io.Writer(stdoutCapture)
	stderrWriter := io.Writer(stderrCapture)
	if opts.streamOutput {
		stdoutWriter = io.MultiWriter(os.Stderr, stdoutCapture)
		stderrWriter = io.MultiWriter(os.Stderr, stderrCapture)
	}
	cmd.Stdout = stdoutWriter
	cmd.Stderr = stderrWriter

	err := cmd.Start()
	var timedOut atomic.Bool
	if err == nil {
		timer := time.AfterFunc(time.Duration(opts.timeoutSeconds)*time.Second, func() {
			timedOut.Store(true)
			_, _ = stderrCapture.Write([]byte(fmt.Sprintf("Command timed out after %d seconds.\n", opts.timeoutSeconds)))
			terminate()
		})

		err = cmd.Wait()
		timer.Stop()
	}

	totalMu.Lock()
	limitExceeded := captureLimitExceeded
	totalMu.Unlock()

	if limitExceeded {
		_, _ = stderrCapture.Write([]byte(fmt.Sprintf("Command exceeded max capture size of %d bytes.\n", opts.maxCaptureBytes)))
	}

	targetExitCode := exitCodeFromError(err)
	didTimeOut := timedOut.Load()
	if didTimeOut {
		targetExitCode = 124
	} else if limitExceeded {
		targetExitCode = 125
	}

	end := time.Now()
	durationMS := end.Sub(start).Milliseconds()

	stdoutText := stdoutCapture.text()
	stderrText := stderrCapture.text()
	logs := parseLogs(stdoutText, stderrText, replacements)
	stdoutLines := splitLines(stdoutText)
	stderrLines := splitLines(stderrText)
	errorLogs := filterLogs(logs, "error")
	warningLogs := filterLogs(logs, "warning")

	processSuccess := targetExitCode == 0 && !didTimeOut && !limitExceeded
	detectedLogError := len(errorLogs) > 0
	success := processSuccess && !(opts.strictLogErrors && detectedLogError)

	var failureReason interface{}
	var successMessage interface{}
	var errorMessage interface{}
	wrapperExitCode := 0

	switch {
	case success:
		successMessage = fmt.Sprintf("Command completed successfully in %d ms.", durationMS)
	case didTimeOut:
		failureReason = "timeout"
		errorMessage = fmt.Sprintf("Command timed out after %d seconds.", opts.timeoutSeconds)
		wrapperExitCode = 124
	case limitExceeded:
		failureReason = "capture_limit_exceeded"
		errorMessage = fmt.Sprintf("Command exceeded max capture size of %d bytes.", opts.maxCaptureBytes)
		wrapperExitCode = 125
	case !processSuccess:
		failureReason = "non_zero_exit_code"
		errorMessage = fmt.Sprintf("Command failed with exit code %d.", targetExitCode)
		wrapperExitCode = targetExitCode
	case opts.strictLogErrors && detectedLogError:
		failureReason = "error_log_detected"
		firstError := "Error log detected."
		if len(errorLogs) > 0 {
			firstError = errorLogs[0].Message
		}
		errorMessage = fmt.Sprintf("Command exited with code 0, but error logs were detected: %s", firstError)
		wrapperExitCode = 1
	default:
		failureReason = "unknown"
		errorMessage = "Command failed."
		wrapperExitCode = 1
	}

	status := "failed"
	if success {
		status = "success"
	}

	redactedErrorMessage := interface{}(nil)
	if errorMessage != nil {
		redactedErrorMessage = redactText(fmt.Sprint(errorMessage), replacements)
	}

	redactedCommand := redactCommandArgs(opts.command, replacements)
	result := map[string]interface{}{
		"success":                success,
		"status":                 status,
		"exit_code":              targetExitCode,
		"wrapper_exit_code":      wrapperExitCode,
		"failure_reason":         failureReason,
		"strict_log_errors":      opts.strictLogErrors,
		"detected_log_error":     detectedLogError,
		"timed_out":              didTimeOut,
		"capture_limit_exceeded": limitExceeded,
		"timeout_seconds":        opts.timeoutSeconds,
		"max_output_bytes":       opts.maxOutputBytes,
		"max_capture_bytes":      opts.maxCaptureBytes,
		"version":                buildInfo,
		"success_message":        successMessage,
		"error_message":          redactedErrorMessage,
		"command": map[string]interface{}{
			"display": shellJoin(redactedCommand),
			"args":    redactedCommand,
		},
		"timing": map[string]interface{}{
			"started_at":  startText,
			"finished_at": end.Format("2006-01-02T15:04:05-0700"),
			"duration_ms": durationMS,
		},
		"summary": map[string]interface{}{
			"total_log_lines":  len(logs),
			"stdout_lines":     len(stdoutLines),
			"stderr_lines":     len(stderrLines),
			"error_lines":      len(errorLogs),
			"warning_lines":    len(warningLogs),
			"first_error":      firstErrorMessage(errorLogs, replacements),
			"stdout_raw_bytes": stdoutCapture.size(),
			"stderr_raw_bytes": stderrCapture.size(),
			"stdout_truncated": stdoutCapture.isTruncated(),
			"stderr_truncated": stderrCapture.isTruncated(),
			"output_truncated": stdoutCapture.isTruncated() || stderrCapture.isTruncated(),
		},
		"output": map[string]interface{}{},
	}

	output := result["output"].(map[string]interface{})
	if opts.includeStdout {
		output["stdout"] = redactText(stdoutText, replacements)
	}
	if opts.includeStderr {
		output["stderr"] = redactText(stderrText, replacements)
	}

	return result, wrapperExitCode
}

func defaultString(value, fallback string) string {
	if value == "" {
		return fallback
	}
	return value
}

func missingCommandResult(opts options) map[string]interface{} {
	output := map[string]interface{}{}
	if opts.includeStdout {
		output["stdout"] = ""
	}
	if opts.includeStderr {
		output["stderr"] = ""
	}

	return map[string]interface{}{
		"success":           false,
		"status":            "failed",
		"exit_code":         64,
		"wrapper_exit_code": 64,
		"failure_reason":    "missing_command",
		"success_message":   nil,
		"error_message":     "No command provided. Usage: ./scripts/capture-error.sh <command> [args...]",
		"command": map[string]interface{}{
			"display": "",
			"args":    []string{},
		},
		"summary": map[string]interface{}{
			"total_log_lines": 0,
			"stdout_lines":    0,
			"stderr_lines":    0,
			"error_lines":     0,
			"warning_lines":   0,
		},
		"logs":   []interface{}{},
		"output": output,
	}
}

func parseLogs(stdoutText, stderrText string, replacements []replacement) []logEntry {
	logs := make([]logEntry, 0)
	for _, item := range []struct {
		stream string
		text   string
	}{
		{"stdout", stdoutText},
		{"stderr", stderrText},
	} {
		for _, line := range splitLines(item.text) {
			logs = append(logs, parseLogLine(item.stream, line, len(logs)+1, replacements))
		}
	}
	return logs
}

func parseLogLine(stream, line string, index int, replacements []replacement) logEntry {
	stripped := strings.TrimSpace(line)
	entry := logEntry{
		Index:   index,
		Stream:  stream,
		Level:   "info",
		Message: line,
		Format:  "text",
	}

	if strings.HasPrefix(stripped, "{") && strings.HasSuffix(stripped, "}") {
		var data map[string]interface{}
		if err := json.Unmarshal([]byte(stripped), &data); err == nil {
			rawLevel := firstString(data, "level", "severity", "log_level")
			if rawLevel == "" {
				rawLevel = "info"
			}
			message := firstString(data, "message", "msg", "error", "err")
			if message == "" {
				message = stripped
			}
			entry.Level = normalizeLevel(rawLevel)
			entry.Message = redactText(message, replacements)
			entry.Format = "json"
			entry.Fields = redactValue(data, replacements)
			return entry
		}
	}

	switch {
	case errorPrefixPattern.MatchString(line),
		errorLevelPattern.MatchString(line),
		stream == "stderr" && stderrErrorPattern.MatchString(line),
		tracebackPattern.MatchString(line):
		entry.Level = "error"
	case warnPrefixPattern.MatchString(line), warnLevelPattern.MatchString(line):
		entry.Level = "warning"
	}

	entry.Message = redactText(entry.Message, replacements)
	return entry
}

func defaultReplacements() []replacement {
	return []replacement{
		{regexp.MustCompile(`https://hooks\.slack\.com/services/[A-Za-z0-9_/\-]+`), "[REDACTED_SLACK_WEBHOOK]"},
		{regexp.MustCompile(`(?i)\b(authorization\s*:\s*bearer\s+)[A-Za-z0-9._~+/\-]+=*`), `${1}[REDACTED]`},
		{regexp.MustCompile(`(?i)(['"]authorization['"]\s*:\s*['"]bearer\s+)[^'"]+`), `${1}[REDACTED]`},
		{regexp.MustCompile(`(?i)(\\['"]authorization\\['"]\s*:\s*\\['"]bearer\s+)[^\\'"]+`), `${1}[REDACTED]`},
		{regexp.MustCompile(`(?i)\b((?:slack_)?webhook(?:_url)?|token|access_token|refresh_token|api_key|apikey|secret|password|passwd|pwd|authorization)\b(\s*[:=]\s*)(['"]?)[^\s,'"]+`), `${1}${2}${3}[REDACTED]`},
		{regexp.MustCompile(`(?i)(['"](?:slack_)?(?:webhook(?:_url)?|token|access_token|refresh_token|api_key|apikey|secret|password|passwd|pwd|authorization)['"]\s*:\s*['"])[^'"]+`), `${1}[REDACTED]`},
		{regexp.MustCompile(`(?i)(\\['"](?:slack_)?(?:webhook(?:_url)?|token|access_token|refresh_token|api_key|apikey|secret|password|passwd|pwd|authorization)\\['"]\s*:\s*\\['"])[^\\'"]+`), `${1}[REDACTED]`},
	}
}

func appendCustomReplacements(replacements []replacement, path string) []replacement {
	if path == "" {
		return replacements
	}
	content, err := os.ReadFile(path)
	if err != nil {
		return replacements
	}
	for _, rawPattern := range strings.Split(string(content), "\n") {
		pattern := strings.TrimSpace(rawPattern)
		if pattern == "" || strings.HasPrefix(pattern, "#") {
			continue
		}
		compiled, err := regexp.Compile(pattern)
		if err != nil {
			continue
		}
		replacements = append(replacements, replacement{compiled, "[REDACTED]"})
	}
	return replacements
}

func redactText(value string, replacements []replacement) string {
	if value == "<nil>" {
		return ""
	}
	redacted := value
	for _, item := range replacements {
		redacted = item.pattern.ReplaceAllString(redacted, item.replacement)
	}
	return redacted
}

func redactValue(value interface{}, replacements []replacement) interface{} {
	switch typed := value.(type) {
	case map[string]interface{}:
		out := make(map[string]interface{}, len(typed))
		for key, item := range typed {
			if sensitiveField.MatchString(key) {
				out[key] = "[REDACTED]"
			} else {
				out[key] = redactValue(item, replacements)
			}
		}
		return out
	case []interface{}:
		out := make([]interface{}, len(typed))
		for i, item := range typed {
			out[i] = redactValue(item, replacements)
		}
		return out
	case string:
		return redactText(typed, replacements)
	default:
		return value
	}
}

func redactCommandArgs(args []string, replacements []replacement) []string {
	redacted := make([]string, 0, len(args))
	redactNext := false
	for _, arg := range args {
		if redactNext {
			redacted = append(redacted, "[REDACTED]")
			redactNext = false
			continue
		}
		if strings.Contains(arg, "=") {
			parts := strings.SplitN(arg, "=", 2)
			if sensitiveArg.MatchString(parts[0]) {
				redacted = append(redacted, parts[0]+"=[REDACTED]")
				continue
			}
		}
		if sensitiveArg.MatchString(arg) {
			redacted = append(redacted, arg)
			redactNext = true
			continue
		}
		redacted = append(redacted, redactText(arg, replacements))
	}
	return redacted
}

func normalizeLevel(level string) string {
	switch strings.ToLower(strings.TrimSpace(level)) {
	case "fatal", "panic", "error", "err":
		return "error"
	case "warn", "warning":
		return "warning"
	case "debug", "trace":
		return strings.ToLower(strings.TrimSpace(level))
	case "info", "information":
		return "info"
	default:
		if level == "" {
			return "info"
		}
		return strings.ToLower(strings.TrimSpace(level))
	}
}

func firstString(data map[string]interface{}, keys ...string) string {
	for _, key := range keys {
		if value, ok := data[key]; ok {
			switch typed := value.(type) {
			case string:
				if typed != "" {
					return typed
				}
			default:
				return fmt.Sprint(typed)
			}
		}
	}
	return ""
}

func splitLines(text string) []string {
	if text == "" {
		return nil
	}
	normalized := strings.ReplaceAll(text, "\r\n", "\n")
	normalized = strings.TrimSuffix(normalized, "\n")
	if normalized == "" {
		return nil
	}
	return strings.Split(normalized, "\n")
}

func stdinIsTerminal() bool {
	stat, err := os.Stdin.Stat()
	if err != nil {
		return false
	}

	return stat.Mode()&os.ModeCharDevice != 0
}

func filterLogs(logs []logEntry, level string) []logEntry {
	filtered := make([]logEntry, 0)
	for _, log := range logs {
		if log.Level == level {
			filtered = append(filtered, log)
		}
	}
	return filtered
}

func firstErrorMessage(errorLogs []logEntry, replacements []replacement) interface{} {
	if len(errorLogs) == 0 {
		return nil
	}
	return redactText(errorLogs[0].Message, replacements)
}

func shellJoin(args []string) string {
	quoted := make([]string, 0, len(args))
	for _, arg := range args {
		quoted = append(quoted, shellQuote(arg))
	}
	return strings.Join(quoted, " ")
}

func shellQuote(value string) string {
	if value == "" {
		return "''"
	}
	if regexp.MustCompile(`^[A-Za-z0-9_@%+=:,./-]+$`).MatchString(value) {
		return value
	}
	return "'" + strings.ReplaceAll(value, "'", `'"'"'`) + "'"
}

func exitCodeFromError(err error) int {
	if err == nil {
		return 0
	}

	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		if status, ok := exitErr.Sys().(syscall.WaitStatus); ok {
			if status.Signaled() {
				return 128 + int(status.Signal())
			}
			return status.ExitStatus()
		}
	}

	return 1
}

func parseBool(name, value string) (bool, error) {
	switch value {
	case "true":
		return true, nil
	case "false":
		return false, nil
	default:
		return false, fmt.Errorf("Error: %s requires true or false.", name)
	}
}

func parsePositiveInt(value string) (int, error) {
	parsed, err := strconv.Atoi(value)
	if err != nil || parsed <= 0 {
		return 0, errors.New("not positive")
	}
	return parsed, nil
}

func parsePositiveInt64(value string) (int64, error) {
	parsed, err := strconv.ParseInt(value, 10, 64)
	if err != nil || parsed <= 0 {
		return 0, errors.New("not positive")
	}
	return parsed, nil
}

func envInt64(name string, fallback int64) int64 {
	value := os.Getenv(name)
	if value == "" {
		return fallback
	}
	parsed, err := parsePositiveInt64(value)
	if err != nil {
		return fallback
	}
	return parsed
}

func showHelp() {
	fmt.Print(`Usage:
  ./scripts/capture-error/capture-error.sh [wrapper-options] -- <command> [args...]
  ./scripts/capture-error/capture-error.sh <command> [args...]

Wrapper options:
  --strict-log-errors      Mark result as failed if error-like logs are detected. Default.
  --exit-code-only         Mark failed only when command exits non-zero.
  --stream-output          Mirror raw command stdout/stderr live to stderr, then print final JSON to stdout. Default.
  --no-stream-output       Capture command output silently, then print only final JSON.
  --stdout true|false      Include captured stdout text in final JSON output. Default: false.
  --stderr true|false      Include captured stderr text in final JSON output. Default: true.
  --timeout SECONDS        Stop the command after this many seconds. Default: 3600.
  --max-output-bytes BYTES Maximum bytes returned per stream in JSON. Default: 65536.
  --max-capture-bytes BYTES Maximum combined captured bytes before terminating. Default: 10485760.
  --redaction-regex-file PATH
                            File with extra Go regexp patterns to redact, one per line.
  --version                 Print capture-error build metadata as JSON.
  -h, --help               Show help.
`)
}

func printVersion() {
	_ = printJSON(map[string]interface{}{
		"name":    "capture-error",
		"version": buildInfo,
	})
}

func printJSON(result map[string]interface{}) error {
	encoded, err := json.MarshalIndent(result, "", "  ")
	if err != nil {
		fmt.Fprintf(os.Stderr, "capture-error: failed to encode JSON: %v\n", err)
		return err
	}
	fmt.Println(string(encoded))
	return nil
}
