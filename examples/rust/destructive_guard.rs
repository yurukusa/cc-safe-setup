// destructive_guard.rs — Claude Code PreToolUse hook in Rust
//
// Blocks rm -rf /, git reset --hard, git clean -fd, and similar
// destructive commands. Exit code 2 = block, 0 = allow.
//
// Build: rustc destructive_guard.rs -o destructive-guard
// Usage: {"type": "command", "command": "/path/to/destructive-guard"}

use std::io::{self, Read};
use std::process;

fn main() {
    let mut input = String::new();
    if io::stdin().read_to_string(&mut input).is_err() {
        process::exit(0);
    }

    // Simple JSON parsing without serde (zero dependencies)
    let cmd = extract_command(&input);
    if cmd.is_empty() {
        process::exit(0);
    }

    // Skip echo/printf context
    let trimmed = cmd.trim_start().to_lowercase();
    if trimmed.starts_with("echo ") || trimmed.starts_with("printf ") {
        process::exit(0);
    }

    let patterns: &[&str] = &[
        "rm -rf /",
        "rm -rf ~/",
        "rm -rf ../",
        "rm -rf .",
        "git reset --hard",
        "git clean -f",
        "git checkout --force",
        "chmod 777 /",
        "find / -delete",
        "--no-preserve-root",
        "sudo mkfs",
    ];

    for pattern in patterns {
        if cmd.to_lowercase().contains(&pattern.to_lowercase()) {
            eprintln!("BLOCKED: Dangerous command detected");
            eprintln!("Command: {}", cmd);
            process::exit(2);
        }
    }

    process::exit(0);
}

fn extract_command(json: &str) -> String {
    // Extract .tool_input.command from JSON without a parser
    if let Some(pos) = json.find("\"command\"") {
        let rest = &json[pos + 9..];
        if let Some(start) = rest.find('"') {
            let value_start = start + 1;
            let mut end = value_start;
            let bytes = rest.as_bytes();
            while end < bytes.len() {
                if bytes[end] == b'"' && (end == 0 || bytes[end - 1] != b'\\') {
                    return rest[value_start..end].replace("\\\"", "\"").replace("\\\\", "\\");
                }
                end += 1;
            }
        }
    }
    String::new()
}
