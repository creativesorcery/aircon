# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"

module Aircon
  module Commands
    class Up
      def initialize(config:)
        @config = config
      end

      def call(branch, port: "3001", detach: false)
        container = Docker.find_container(project: branch, service: @config.service)

        if container
          attach_existing(container, branch, detach: detach)
        else
          start_new(branch, port, detach: detach)
        end
      end

      private

      def attach_existing(container, branch, detach: false)
        if detach
          puts "Container for '#{branch}' is already running: #{container}"
          return
        end

        puts "Attaching to existing container for '#{branch}'..."
        system("docker", "exec", "-it", container, "bash")
        cleanup_if_last(container, branch)
      end

      def start_new(branch, port, detach: false)
        if @config.gh_token.nil? || @config.gh_token.to_s.empty?
          warn "Warning: gh_token not configured. GitHub CLI (gh) will not be authenticated."
          warn "  Set gh_token in .aircon.yml if you want to use 'gh' commands."
        end

        env = {
          "HOST_PORT" => port.to_s,
          "GH_TOKEN" => @config.gh_token.to_s,
          "GITHUB_PERSONAL_ACCESS_TOKEN" => @config.gh_token.to_s
        }

        system(env, "docker", "compose",
               "-f", @config.compose_file,
               "-p", branch,
               "up", "-d", "--build")

        container = Docker.find_container(project: branch, service: @config.service)
        abort "Error: Could not find container after starting services." unless container

        inject_claude_settings(container)
        setup_container(container, branch)

        if detach
          puts "Container started: #{container}"
          return
        end

        system("docker", "exec", "-it", container, "bash")
        cleanup_if_last(container, branch)
      end

      def inject_claude_settings(container)
        Dir.mktmpdir("aircon_claude_settings") do |staging|
          claude_config = File.expand_path(@config.claude_config_path)
          claude_dir = File.expand_path(@config.claude_dir_path)

          FileUtils.cp(claude_config, File.join(staging, ".claude.json")) if File.exist?(claude_config)

          if File.directory?(claude_dir)
            FileUtils.cp_r(claude_dir, File.join(staging, ".claude"))
          else
            FileUtils.mkdir_p(File.join(staging, ".claude"))
          end

          write_credentials(File.join(staging, ".claude", ".credentials.json"))

          home = @config.container_home
          rewrite_paths(staging, home)
          user = @config.container_user
          system("docker", "cp", "#{File.join(staging, '.claude')}/.", "#{container}:#{home}/.claude")
          system("docker", "cp", File.join(staging, ".claude.json"), "#{container}:#{home}/.claude.json")
          system("docker", "exec", "-u", "root", container,
                 "bash", "-c", "chmod -R u+rwX #{home}/.claude #{home}/.claude.json && " \
                               "chown -R #{user}:#{user} #{home}/.claude #{home}/.claude.json")
        end
      end

      def rewrite_paths(staging, container_home)
        host_home = File.expand_path("~")

        Dir.glob(File.join(staging, "**", "*"), File::FNM_DOTMATCH).each do |path|
          next unless File.file?(path)
          next unless File.readable?(path)

          content = File.binread(path)
          next unless content.valid_encoding?
          next unless content.include?(host_home)

          File.write(path, content.gsub(host_home, container_home))
        end
      end

      def write_credentials(dest)
        case @config.credentials_source
        when "keychain"
          out, status = Open3.capture2(
            "security", "find-generic-password",
            "-a", ENV.fetch("USER", "unknown"),
            "-w", "-s", "Claude Code-credentials"
          )
          if status.success?
            File.write(dest, out)
          else
            warn "Warning: Could not read credentials from keychain."
          end
        when "file"
          src = File.expand_path("~/.claude/.credentials.json")
          if File.exist?(src)
            FileUtils.cp(src, dest)
          else
            warn "Warning: Credentials file not found at #{src}"
          end
        end
      end

      def setup_container(container, branch)
        home = @config.container_home

        # Install Claude Code if not already present, and ensure it's on PATH for all shells
        system("docker", "exec", container, "bash", "-c",
               "command -v claude >/dev/null 2>&1 || curl -fsSL https://claude.ai/install.sh | bash")
        system("docker", "exec", "-u", "root", container, "bash", "-c",
               "grep -qF '#{home}/.local/bin' /etc/bash.bashrc 2>/dev/null || " \
               "echo 'export PATH=\"#{home}/.local/bin:$PATH\"' >> /etc/bash.bashrc")

        if @config.gh_token && !@config.gh_token.to_s.empty?
          system("docker", "exec", "-u", "root", container, "bash", "-c",
                 "grep -qF 'export GH_TOKEN=' /etc/bash.bashrc 2>/dev/null || " \
                 "echo 'export GH_TOKEN=\"#{@config.gh_token}\"' >> /etc/bash.bashrc")
          system("docker", "exec", "-u", "root", container, "bash", "-c",
                 "grep -qF 'export GITHUB_PERSONAL_ACCESS_TOKEN=' /etc/bash.bashrc 2>/dev/null || " \
                 "echo 'export GITHUB_PERSONAL_ACCESS_TOKEN=\"#{@config.gh_token}\"' >> /etc/bash.bashrc")
        end

        # Configure git and create branch
        system("docker", "exec", container, "git", "config", "--global", "user.email", @config.git_email)
        system("docker", "exec", container, "git", "config", "--global", "user.name", @config.git_name)
        # Check if branch exists on remote; if so, check it out, otherwise create new
        _, status = Open3.capture2("docker", "exec", container, "git", "ls-remote", "--heads", "origin", branch)
        if status.success? && !_.strip.empty?
          system("docker", "exec", container, "git", "fetch", "origin", branch)
          system("docker", "exec", container, "git", "checkout", "-b", branch, "origin/#{branch}")
        else
          system("docker", "exec", container, "git", "fetch", "origin", "main")
          system("docker", "exec", container, "git", "checkout", "-b", branch, "origin/main")
        end

        # If you have the official anthropic marketplace plugin installed, it will always make a call to the anthropic github repo on claude startup. It uses SSH, but it should be https for universal compatibility since its a public repository.
        system("docker", "exec", container, "git", "config", "--global", "url.\"https://github.com/anthropics/\".insteadOf", "ssh://git@github.com/anthropics/")
      end

      # def wait_for_setup(container)
      #   puts "Waiting for container setup to complete..."
      #   loop do
      #     _, status = Open3.capture2("docker", "exec", container, "test", "-f", "/tmp/setup-done")
      #     break if status.success?

      #     sleep 1
      #   end
      # end

      def cleanup_if_last(container, branch)
        out, = Open3.capture2("docker", "exec", container, "pgrep", "-x", "bash")
        remaining = out.strip.lines.size

        return unless remaining == 0

        puts "Last session ended. Cleaning up..."
        system("docker", "compose", "-p", branch, "down", "-v", "--remove-orphans")
        system("docker", "image", "prune", "-f")
      end
    end
  end
end
