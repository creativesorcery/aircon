# frozen_string_literal: true

require "fileutils"
require "thor"

module Aircon
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    desc "up NAME [PORT]", "Start or attach to a dev container for the given project"
    method_option :detach, type: :boolean, default: false, aliases: "-d",
                           desc: "Start container without attaching an interactive session"
    method_option :branch, type: :string, aliases: "-b",
                           desc: "Git branch to check out (defaults to NAME)"
    def up(name, port = "3001")
      config = Configuration.new
      branch = options[:branch] || name
      Commands::Up.new(config: config).call(name, branch: branch, port: port, detach: options[:detach])
    end

    desc "down NAME", "Tear down the container and volumes for the given project"
    def down(name)
      config = Configuration.new
      Commands::Down.new(config: config).call(name)
    end

    desc "vscode NAME", "Attach VS Code to a running container for the given project"
    def vscode(name)
      config = Configuration.new
      Commands::Vscode.new(config: config).call(name)
    end

    desc "init", "Create a sample .aircon/aircon.yml, Dockerfile, and docker-compose.yml in the current directory"
    def init
      FileUtils.mkdir_p(File.join(Dir.pwd, ".aircon"))

      {
        "aircon.yml" => SAMPLE_CONFIG,
        "aircon_init.sh" => INIT_SCRIPT_TEMPLATE,
        "Dockerfile" => DOCKERFILE_TEMPLATE,
        "docker-compose.yml" => COMPOSE_TEMPLATE
      }.each do |filename, content|
        path = File.join(Dir.pwd, ".aircon", filename)
        if File.exist?(path)
          puts "Skipped .aircon/#{filename} (already exists)"
        else
          File.write(path, content)
          puts "Created .aircon/#{filename}"
        end
      end
    end

    desc "version", "Show aircon version"
    def version
      puts "aircon #{VERSION}"
    end

    SAMPLE_CONFIG = <<~'YAML'
      # Aircon configuration — ERB is supported (e.g. <%= ENV['GITHUB_TOKEN'] %>)
      # See: https://github.com/creativesorcery/aircon

      # Docker Compose file to use (default: .aircon/docker-compose.yml)
      # compose_file: .aircon/docker-compose.yml

      # Application name used for database credentials etc. (default: directory basename)
      # app_name: myapp

      # GitHub personal access token (supports ERB)
      # gh_token: <%= ENV['GITHUB_TOKEN'] %>

      # Claude Code OAuth token (supports ERB)
      # claude_code_oauth_token: <%= ENV['CLAUDE_CODE_OAUTH_TOKEN'] %>

      # Workspace folder path inside the container
      # workspace_path: /myproject

      # Path to host's Claude config file
      # claude_config_path: ~/.claude.json

      # Path to host's Claude directory
      # claude_dir_path: ~/.claude

      # Docker Compose service name for the main container
      # service: app

      # Git author identity inside the container
      # git_email: claude_docker@localhost.com
      # git_name: Claude Docker

      # Non-root user inside the container
      # container_user: appuser

      # Script to run inside the container after setup (path relative to project root)
      # Defaults to .aircon/aircon_init.sh — edit that file to add your setup steps.
      # init_script: .aircon/aircon_init.sh
    YAML

    INIT_SCRIPT_TEMPLATE = <<~'BASH'
      #!/bin/bash
      # .aircon/aircon_init.sh
      #
      # This script runs inside the container after aircon completes its setup.
      # It is invoked as a login shell (bash -l), so environment variables
      # configured by aircon are available:
      #
      #   GH_TOKEN / GITHUB_PERSONAL_ACCESS_TOKEN  — GitHub personal access token
      #   CLAUDE_CODE_OAUTH_TOKEN                  — Claude Code OAuth token
      #   PATH                                     — includes ~/.local/bin (claude, gh, etc.)
      #
      # The working directory is the repository root inside the container.
      #
      # Examples:
      #   npm install
      #   bundle install
      #   cp .env.example .env
    BASH

    DOCKERFILE_TEMPLATE = <<~'DOCKERFILE'
      FROM ruby:4.0.1

      RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash -

      # Add GitHub CLI repository
      RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
          && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
          && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null

      # Install dependencies
      RUN apt-get update -qq && \
          apt-get install -y --no-install-recommends \
          bash \
          build-essential \
          git \
          libpq-dev \
          postgresql-client \
          curl \
          libvips \
          bubblewrap \
          socat \
          nodejs \
          gh \
          && rm -rf /var/lib/apt/lists/*

      # Make /bin/sh point to bash instead of dash (required for devcontainer features)
      RUN ln -sf /bin/bash /bin/sh

      # Ensure bash is the default shell for RUN commands
      SHELL ["/bin/bash", "-c"]

      # Create a non-root user
      ARG USERNAME=appuser
      ARG USER_UID=1000
      ARG USER_GID=$USER_UID
      ARG WORKSPACE_PATH=/workspace

      RUN groupadd --gid $USER_GID $USERNAME \
      && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
      && apt-get update \
      && apt-get install -y sudo \
      && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
      && chmod 0440 /etc/sudoers.d/$USERNAME \
      && rm -rf /var/lib/apt/lists/*

      # Give the container user write access to the gem directory
      RUN chown -R $USER_UID:$USER_GID /usr/local/bundle

      RUN npm install -g @anthropic-ai/sandbox-runtime
      RUN npm install -g yarn
      RUN npm install -g playwright@1.58.1
      RUN playwright install --with-deps chromium

      COPY --chown=$USERNAME:$USERNAME . $WORKSPACE_PATH

      USER $USERNAME

      RUN playwright install chromium

      WORKDIR $WORKSPACE_PATH

      RUN bundle install
    DOCKERFILE

    COMPOSE_TEMPLATE = <<~'YAML'
      services:
        app:
          build:
            context: ..
            dockerfile: .aircon/Dockerfile
            args:
              USERNAME: ${AIRCON_CONTAINER_USER:-appuser}
              WORKSPACE_PATH: ${AIRCON_WORKSPACE_PATH:-/workspace}
          ports:
            - "${HOST_PORT:-3001}:3000"
          command: sleep infinity
          environment:
            DATABASE_HOST: db
            DATABASE_USER: ${AIRCON_APP_NAME:-app}
            RAILS_ENV: development
            RAILS_BIND: 0.0.0.0
          depends_on:
            db:
              condition: service_started

        db:
          image: postgres:18
          restart: unless-stopped
          environment:
            POSTGRES_USER: ${AIRCON_APP_NAME:-app}
            POSTGRES_HOST_AUTH_METHOD: trust
            POSTGRES_DB: ${AIRCON_APP_NAME:-app}_development
    YAML
  end
end
