# Changelog

## [0.2.0] - 2026-04-03

### Added

- Restore `credentials_source` configuration option with three modes:
  - `keychain` (default) — reads Claude Code credentials from macOS Keychain
  - `file` — copies credentials from `~/.claude/.credentials.json`
  - `oauth_token` — injects `CLAUDE_CODE_OAUTH_TOKEN` env var into the container,
    using `claude_code_oauth_token` from config or falling back to the
    `CLAUDE_CODE_OAUTH_TOKEN` environment variable

## [0.1.1] - 2026-04-01

### Fixed

- Pin compose image name to `app_name` so it's reused across projects (#12).
  Without an explicit image key, Docker Compose derived the image name from the
  project name, causing a full rebuild on every `aircon up` invocation.

## [0.1.0] - 2026-04-01

- Initial release
