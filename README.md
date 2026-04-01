# Aircon

Manage Docker-based isolated Claude Code development containers.

Aircon spins up a Docker Compose environment for each project, injects your Claude Code credentials at runtime (via `docker cp`, no Dockerfile changes needed), and attaches an interactive shell. When the last shell session exits, the container is automatically cleaned up.

## Prerequisites

- Ruby >= 3.3.0
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

# Start a dev container (uses "my-project" as both project name and git branch)
aircon up my-project

# Use a different git branch than the project name
aircon up my-project -b feature/some-branch

# Start on a custom port (default: 3001)
aircon up my-project 3005

# Attach VS Code to a running container
aircon vscode my-project

# Tear down a container
aircon down my-project

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

# Claude Code OAuth token (supports ERB)
claude_code_oauth_token: <%= ENV['CLAUDE_CODE_OAUTH_TOKEN'] %>

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
| `claude_code_oauth_token` | `nil` | Claude Code OAuth token (supports ERB) |
| `workspace_path` | `/#{basename of cwd}` | Container workspace folder path |
| `claude_config_path` | `~/.claude.json` | Path to host's claude.json settings file |
| `claude_dir_path` | `~/.claude` | Path to host's .claude directory |
| `service` | `app` | Docker Compose service name |
| `git_email` | `claude_docker@localhost.com` | Git author email inside the container |
| `git_name` | `Claude Docker` | Git author name inside the container |
| `container_user` | `vscode` | Non-root user inside the container (determines home directory) |

## Commands

### `aircon up NAME [PORT]`

Start or attach to a dev container for the given project.

- **NAME** (required) — Project name (also used as the git branch unless `--branch` is specified)
- **PORT** (optional, default: `3001`) — Host port mapped to the container

| Option | Alias | Description |
|--------|-------|-------------|
| `--branch` | `-b` | Git branch to check out (defaults to NAME) |
| `--detach` | `-d` | Start container without attaching an interactive session |

The project name is used as the Docker Compose project name (`-p NAME`), so the resulting container is named `NAME-SERVICE-1` (e.g. `my-project-app-1`). This is how aircon identifies and tracks containers.

If a container already exists for the project, a new shell session is attached. When all shell sessions exit, the container is automatically torn down.

```bash
aircon up my-project
aircon up my-project -b feature/some-branch
aircon up my-project 3005
aircon up my-project -d
```

### `aircon down NAME`

Tear down the container and volumes for the given project.

- **NAME** (required) — Project name to tear down

Stops the Docker Compose services, removes volumes, cleans up orphaned containers, and prunes unused images.

```bash
aircon down my-project
```

### `aircon vscode NAME`

Attach VS Code to a running container for the given project.

- **NAME** (required) — Project name

Opens VS Code connected to the running container via the Remote - Containers extension. The container must already be running (use `aircon up` first).

```bash
aircon vscode my-project
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

1. **`aircon up NAME`** checks for an existing container matching the project name. If found, it attaches a new shell session.
2. On first invocation, it builds and starts the Docker Compose environment, then injects Claude Code settings via `docker cp` (no COPY lines needed in your Dockerfile).
3. If `claude_code_oauth_token` is configured, it is set as the `CLAUDE_CODE_OAUTH_TOKEN` environment variable inside the container.
4. Claude Code is automatically installed inside the container if not already present.
5. Git is configured with the `git_email`/`git_name` settings, and a branch is checked out (defaults to `NAME`, or the value of `--branch` if provided).
6. When the last `bash` session exits, the container is torn down and images are pruned.
7. **`aircon vscode NAME`** hex-encodes the container ID and opens VS Code attached to it.

## Notes

- SSH keys are not managed by aircon — they are project-specific
- Your Dockerfile does **not** need COPY lines for Claude settings; aircon injects them at runtime

## License

MIT — see [LICENSE.txt](LICENSE.txt).
