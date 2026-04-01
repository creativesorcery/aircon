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

    desc "init", "Create a sample .aircon.yml in the current directory"
    def init
      dest = File.join(Dir.pwd, ".aircon.yml")
      if File.exist?(dest)
        abort "Error: .aircon.yml already exists in this directory."
      end

      FileUtils.mkdir_p(File.join(Dir.pwd, ".aircon"))
      init_script_dest = File.join(Dir.pwd, ".aircon", "aircon_init.sh")
      File.write(init_script_dest, INIT_SCRIPT_TEMPLATE) unless File.exist?(init_script_dest)

      File.write(dest, SAMPLE_CONFIG)
      puts "Created .aircon.yml"
      puts "Created .aircon/aircon_init.sh"
    end

    desc "version", "Show aircon version"
    def version
      puts "aircon #{VERSION}"
    end

    SAMPLE_CONFIG = <<~'YAML'
      # Aircon configuration — ERB is supported (e.g. <%= ENV['GITHUB_TOKEN'] %>)
      # See: https://github.com/creativesorcery/aircon

      # Docker Compose file to use
      # compose_file: docker-compose.yml

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
      # container_user: vscode

      # Script to run inside the container after setup (path relative to this file)
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
  end
end
