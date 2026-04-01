# Aircon

No more worktrees. Aircon gives every feature branch its own isolated Docker container pre-loaded with Claude Code, your credentials, and a running shell — so you can work on multiple branches in parallel without them stepping on each other. Dependencies like databases are isolated, so a db migration in one container does not affect the other.

Each container gets:
- Your Claude Code credentials and settings injected at startup (no Dockerfile changes needed)
- Claude Code installed automatically if not already in the image
- Your GitHub token set for authenticated `git` and `gh` operations
- A git branch checked out and ready to go
- An optional project-specific init script that runs after the container is up

When you close the last shell session, the container and its volumes are automatically torn down.

---

## Prerequisites

- Ruby >= 3.3.0
- Docker and Docker Compose
- Claude Code installed on your host machine (aircon copies credentials from it)
- VS Code with the [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) extension (only needed for `aircon vscode`)

---

## Installation

```bash
gem install aircon
```

Or add to your Gemfile:

```ruby
gem "aircon"
```

---

## Getting Started

**1. Initialize aircon in your project:**

```bash
cd your-project
aircon init
```

This creates four files under `.aircon/`:

| File | Purpose |
|------|---------|
| `aircon.yml` | Main config (tokens, paths, user settings) |
| `aircon_init.sh` | Script run inside the container after setup |
| `Dockerfile` | Base image for your dev container, change it or use your own |
| `docker-compose.yml` | Compose config wired to the Dockerfile, change it or use your own |

Existing files are never overwritten, so `aircon init` is safe to re-run.

**2. Configure your tokens:**

Edit `.aircon/aircon.yml` and set at minimum:

```yaml
gh_token: <%= ENV['GITHUB_TOKEN'] %>
```

**3. Start a container:**

```bash
aircon up my-feature
```

This builds the image, injects your Claude credentials, checks out a branch named `my-feature`, runs your init script, and drops you into a shell inside the container. The container and dependencies set in the docker-compose file will all be running under the `my-feature` docker project, fully isolating it from other containers.

---

## Commands

### `aircon up NAME [PORT]`

Start or attach to a dev container.

```bash
aircon up my-feature               # start on default port 3001
aircon up my-feature 3005          # start on port 3005
aircon up my-feature -b feat/auth  # use a different git branch than NAME
aircon up my-feature -d            # start detached (no interactive shell)
```

**What `aircon up` does, step by step:**

1. Looks for an existing container named `NAME-SERVICE-1` (e.g. `my-feature-app-1`).
   - If found → attaches a new `bash` session to it and skips to step 12.
2. Warns if `gh_token` is not configured.
3. Runs `docker compose up -d --build` with `HOST_PORT`, `AIRCON_APP_NAME`, `AIRCON_CONTAINER_USER`, and `AIRCON_WORKSPACE_PATH` injected as environment variables.
4. Copies `~/.claude.json` and `~/.claude/` from your host into the container via `docker cp` (no `COPY` lines needed in your Dockerfile). Host home paths inside those files are rewritten to match the container home directory.
5. Installs Claude Code inside the container if not already present (`curl -fsSL https://claude.ai/install.sh | bash`).
6. Adds `~/.local/bin` to `PATH` in `/etc/bash.bashrc` so `claude` is available in all sessions.
7. Writes `GH_TOKEN` and `GITHUB_PERSONAL_ACCESS_TOKEN` to `/etc/bash.bashrc` (if `gh_token` is set).
8. Writes `CLAUDE_CODE_OAUTH_TOKEN` to `/etc/bash.bashrc` (if configured).
9. Sets `git config user.email` and `git config user.name` globally inside the container.
10. Configures `git` to authenticate GitHub URLs with your token (covers both `https://github.com/` and `git@github.com:`).
11. Checks out the branch:
    - If the branch exists on `origin` → fetches and checks it out.
    - Otherwise → creates a new branch from `origin/main`.
12. Runs the `init_script` (`.aircon/aircon_init.sh` by default) inside the container via `bash -l`, if the file exists.
13. Attaches an interactive `bash` session.
14. When the last `bash` session exits → runs `docker compose down -v --remove-orphans` and `docker image prune -f`.

**Options:**

| Option | Alias | Description |
|--------|-------|-------------|
| `--branch BRANCH` | `-b` | Git branch to check out (defaults to NAME) |
| `--detach` | `-d` | Start without attaching an interactive session |

---

### `aircon down NAME`

Tear down the container and volumes for a project.

```bash
aircon down my-feature
```

Runs `docker compose down -v --remove-orphans` and prunes unused images. Use this to clean up manually if you need to reset state without waiting for a session to end.

---

### `aircon vscode NAME`

Attach VS Code to a running container.

```bash
aircon vscode my-feature
```

The container must already be running (`aircon up` first). Opens VS Code connected to the container via the Dev Containers extension, with the workspace set to `workspace_path`.

---

### `aircon init`

Generate the `.aircon/` config files in the current directory.

```bash
aircon init
```

Creates `aircon.yml`, `aircon_init.sh`, `Dockerfile`, and `docker-compose.yml` under `.aircon/`. Safe to re-run — existing files are not overwritten.

---

### `aircon version`

Print the installed version.

```bash
aircon version
```

---

## Configuration

Config is loaded from `.aircon/aircon.yml` in your project root. All keys are optional. ERB is supported, so you can pull in environment variables.

```yaml
# Docker Compose file to use
compose_file: .aircon/docker-compose.yml

# Application name — used for DB credentials in the default Compose template
# Defaults to the basename of the current directory
app_name: my-app

# GitHub personal access token — authenticates git and gh inside the container
gh_token: <%= ENV['GITHUB_TOKEN'] %>

# Claude Code OAuth token — set as CLAUDE_CODE_OAUTH_TOKEN inside the container
claude_code_oauth_token: <%= ENV['CLAUDE_CODE_OAUTH_TOKEN'] %>

# Workspace folder path inside the container
workspace_path: /my-app

# Path to your Claude config file on the host
claude_config_path: ~/.claude.json

# Path to your Claude directory on the host
claude_dir_path: ~/.claude

# Docker Compose service name
service: app

# Git identity inside the container
git_email: claude_docker@localhost.com
git_name: Claude Docker

# Non-root user inside the container (determines home directory)
container_user: appuser

# Script to run inside the container after setup (path relative to this file)
init_script: .aircon/aircon_init.sh
```

### Configuration Reference

| Key | Default | Description |
|-----|---------|-------------|
| `compose_file` | `.aircon/docker-compose.yml` | Docker Compose file to use |
| `app_name` | basename of cwd | App name passed to Compose as `AIRCON_APP_NAME` |
| `gh_token` | `nil` | GitHub token; sets `GH_TOKEN` and `GITHUB_PERSONAL_ACCESS_TOKEN` in the container |
| `claude_code_oauth_token` | `nil` | Claude Code OAuth token; sets `CLAUDE_CODE_OAUTH_TOKEN` in the container |
| `workspace_path` | `/workspace` | Workspace folder path inside the container |
| `claude_config_path` | `~/.claude.json` | Host path to `claude.json` |
| `claude_dir_path` | `~/.claude` | Host path to `.claude/` directory |
| `service` | `app` | Docker Compose service name for the main container |
| `git_email` | `claude_docker@localhost.com` | Git author email inside the container |
| `git_name` | `Claude Docker` | Git author name inside the container |
| `container_user` | `appuser` | Non-root user inside the container |
| `init_script` | `.aircon/aircon_init.sh` | Script run after setup; has access to `GH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`, etc. |

---

## Notes

- SSH keys are not managed by aircon — handle them in your `init_script` if needed.
- Your `Dockerfile` does not need `COPY` instructions for Claude settings; aircon injects them at runtime via `docker cp`.
- The Docker Compose project name is set to `NAME` (the argument to `aircon up`), so the container will be named `NAME-SERVICE-1` (e.g. `my-feature-app-1`). This is how aircon identifies containers across commands.

---

## Releasing to RubyGems

1. Bump the version in `lib/aircon/version.rb`.
2. Build and push:

```bash
gem build aircon.gemspec
gem push aircon-<version>.gem
```

You'll be prompted for your RubyGems credentials on first push. Subsequent pushes use the stored API key at `~/.gem/credentials`.

---

## License

MIT — see [LICENSE.txt](LICENSE.txt).
