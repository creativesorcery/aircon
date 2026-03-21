# Aircon

Manage Docker-based isolated Claude Code development containers — one per git branch.

Aircon spins up a Docker Compose environment for each branch, injects your Claude Code credentials at runtime (via `docker cp`, no Dockerfile changes needed), and attaches an interactive shell. When the last shell session exits, the container is automatically cleaned up.

## Prerequisites

- Ruby >= 4.0.0
- Docker and Docker Compose
- A `docker-compose.yml` (or custom Compose file) in your project
- Claude Code installed on the host (for credentials)
- VS Code with the Remote - Containers extension (for `aircon vscode`)

## Installation

```bash
gem install aircon
```

Or add to your Gemfile:

```ruby
gem "aircon"
```

## Quick Start

```bash
# Generate a config file (optional)
aircon init

# Start a dev container for a branch
aircon up my-feature-branch

# Start on a custom port (default: 3001)
aircon up my-feature-branch 3005

# Attach VS Code to a running container
aircon vscode my-feature-branch

# Show installed version
aircon version
```

## Configuration

Create an `.aircon.yml` in your project root (use `aircon init` to generate a template). All values are optional — sensible defaults are provided.

ERB is supported, so you can use dynamic values like environment variables.

```yaml
# Docker Compose file to use
compose_file: docker-compose.yml

# GitHub personal access token (supports ERB)
gh_token: <%= ENV['GITHUB_TOKEN'] %>

# How to obtain Claude Code credentials: "keychain" (macOS) or "file"
credentials_source: keychain

# Workspace folder path inside the container
workspace_path: /myproject

# Path to host's Claude config file
claude_config_path: ~/.claude.json

# Path to host's Claude directory
claude_dir_path: ~/.claude

# Docker Compose service name for the main container
service: app

# Git author identity inside the container
git_email: claude_docker@localhost.com
git_name: Claude Docker

# Non-root user inside the container
container_user: vscode
```

### Configuration Reference

| Key | Default | Description |
|-----|---------|-------------|
| `compose_file` | `docker-compose.yml` | Docker Compose filename |
| `gh_token` | `nil` | GitHub token value (supports ERB) |
| `credentials_source` | `keychain` | `keychain` (macOS) or `file` (~/.claude/.credentials.json) |
| `workspace_path` | `/#{basename of cwd}` | Container workspace folder path |
| `claude_config_path` | `~/.claude.json` | Path to host's claude.json settings file |
| `claude_dir_path` | `~/.claude` | Path to host's .claude directory |
| `service` | `app` | Docker Compose service name |
| `git_email` | `claude_docker@localhost.com` | Git author email inside the container |
| `git_name` | `Claude Docker` | Git author name inside the container |
| `container_user` | `vscode` | Non-root user inside the container (determines home directory) |

## Commands

### `aircon up BRANCH [PORT]`

Start or attach to a dev container for the given branch.

- **BRANCH** (required) — Git branch name
- **PORT** (optional, default: `3001`) — Host port mapped to the container

| Option | Alias | Description |
|--------|-------|-------------|
| `--detach` | `-d` | Start container without attaching an interactive session |

The branch name is used as the Docker Compose project name (`-p BRANCH`), so the resulting container is named `BRANCH-SERVICE-1` (e.g. `my-feature-branch-app-1`). This is how aircon identifies and tracks containers per branch.

If a container already exists for the branch, a new shell session is attached. When all shell sessions exit, the container is automatically torn down.

```bash
aircon up my-feature-branch
aircon up my-feature-branch 3005
aircon up my-feature-branch -d
```

### `aircon down BRANCH`

Tear down the container and volumes for the given branch.

- **BRANCH** (required) — Git branch name to tear down

Stops the Docker Compose services, removes volumes, cleans up orphaned containers, and prunes unused images.

```bash
aircon down my-feature-branch
```

### `aircon vscode BRANCH`

Attach VS Code to a running container for the given branch.

- **BRANCH** (required) — Git branch name

Opens VS Code connected to the running container via the Remote - Containers extension. The container must already be running (use `aircon up` first).

```bash
aircon vscode my-feature-branch
```

### `aircon init`

Create a sample `.aircon.yml` in the current directory. Aborts if one already exists.

```bash
aircon init
```

### `aircon version`

Show the installed aircon version.

```bash
aircon version
```

## How It Works

1. **`aircon up BRANCH`** checks for an existing container matching the branch. If found, it attaches a new shell session.
2. On first invocation, it builds and starts the Docker Compose environment, then injects Claude Code settings via `docker cp` (no COPY lines needed in your Dockerfile).
3. Credentials are sourced from macOS Keychain (`keychain`) or a file (`file`) based on your `credentials_source` setting.
4. Claude Code is automatically installed inside the container if not already present.
5. Git is configured with the `git_email`/`git_name` settings, and a new branch matching the provided name is checked out.
6. The container startup waits for a `/tmp/setup-done` sentinel file before attaching a shell — your Compose entrypoint should `touch /tmp/setup-done` when ready.
7. When the last `bash` session exits, the container is torn down and images are pruned.
8. **`aircon vscode BRANCH`** hex-encodes the container ID and opens VS Code attached to it.

## Notes

- Add `.aircon.yml` to your `.gitignore` if it contains secrets
- Add `.aircon/` to both `.gitignore` and `.dockerignore` (used as a temporary staging directory)
- SSH keys are not managed by aircon — they are project-specific
- Your Dockerfile does **not** need COPY lines for Claude settings; aircon injects them at runtime

## License

MIT — see [LICENSE.txt](LICENSE.txt).
