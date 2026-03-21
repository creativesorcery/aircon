# frozen_string_literal: true

require "thor"

module Aircon
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    desc "up BRANCH [PORT]", "Start or attach to a dev container for the given branch"
    method_option :detach, type: :boolean, default: false, aliases: "-d",
                           desc: "Start container without attaching an interactive session"
    def up(branch, port = "3001")
      config = Configuration.new
      Commands::Up.new(config: config).call(branch, port: port, detach: options[:detach])
    end

    desc "vscode BRANCH", "Attach VS Code to a running container for the given branch"
    def vscode(branch)
      config = Configuration.new
      Commands::Vscode.new(config: config).call(branch)
    end

    desc "init", "Create a sample .aircon.yml in the current directory"
    def init
      dest = File.join(Dir.pwd, ".aircon.yml")
      if File.exist?(dest)
        abort "Error: .aircon.yml already exists in this directory."
      end

      File.write(dest, SAMPLE_CONFIG)
      puts "Created .aircon.yml"
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

      # How to obtain Claude Code credentials: "keychain" (macOS) or "file"
      # credentials_source: keychain

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
    YAML
  end
end
