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

      def call(name, branch:, port: "3001", detach: false)
        container = Docker.find_container(project: name, service: @config.service)

        if container
          attach_existing(container, name, detach: detach)
        else
          start_new(name, branch, port, detach: detach)
        end
      end

      private

      def attach_existing(container, name, detach: false)
        if detach
          puts "Container for '#{name}' is already running: #{container}"
          return
        end

        puts "Attaching to existing container for '#{name}'..."
        system("docker", "exec", "-it", container, "bash")
        cleanup_if_last(container, name)
      end

      def start_new(name, branch, port, detach: false)
        if @config.gh_token.nil? || @config.gh_token.to_s.empty?
          warn "Warning: gh_token not configured. GitHub CLI (gh) will not be authenticated."
          warn "  Set gh_token in .aircon.yml if you want to use 'gh' commands."
        end

        env = {
          "HOST_PORT" => port.to_s,
          "AIRCON_APP_NAME" => @config.app_name,
          "AIRCON_CONTAINER_USER" => @config.container_user,
          "AIRCON_WORKSPACE_PATH" => @config.workspace_path
        }
        system(env, "docker", "compose",
               "-f", @config.compose_file,
               "-p", name,
               "up", "-d", "--build")

        container = Docker.find_container(project: name, service: @config.service)
        abort "Error: Could not find container after starting services." unless container

        inject_claude_settings(container)
        setup_container(container, branch)
        run_init_script(container)

        if detach
          puts "Container started: #{container}"
          return
        end

        system("docker", "exec", "-it", container, "bash")
        cleanup_if_last(container, name)
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

        if @config.credentials_source == "oauth_token"
          token = @config.claude_code_oauth_token || ENV["CLAUDE_CODE_OAUTH_TOKEN"]
          if token && !token.to_s.empty?
            system("docker", "exec", "-u", "root", container, "bash", "-c",
                   "grep -qF 'export CLAUDE_CODE_OAUTH_TOKEN=' /etc/bash.bashrc 2>/dev/null || " \
                   "echo 'export CLAUDE_CODE_OAUTH_TOKEN=\"#{token}\"' >> /etc/bash.bashrc")
          end
        end

        # Configure git and create branch
        system("docker", "exec", container, "git", "config", "--global", "user.email", @config.git_email)
        system("docker", "exec", container, "git", "config", "--global", "user.name", @config.git_name)
        # Configure git authentication for GitHub using the personal access token
        if @config.gh_token && !@config.gh_token.to_s.empty?
          authed = "https://x-access-token:#{@config.gh_token}@github.com/"
          system("docker", "exec", container, "git", "config", "--global",
                 "url.#{authed}.insteadOf", "https://github.com/")
          system("docker", "exec", container, "git", "config", "--global",
                 "url.#{authed}.insteadOf", "git@github.com:")
        end
        # Skip checkout if already on the target branch (host was on this branch)
        current_branch, = Open3.capture2("docker", "exec", container, "git", "rev-parse", "--abbrev-ref", "HEAD")
        if current_branch.strip != branch
          # Check if branch exists on remote; if so, check it out, otherwise create new
          _, status = Open3.capture2("docker", "exec", container, "git", "ls-remote", "--heads", "origin", branch)
          if status.success? && !_.strip.empty?
            system("docker", "exec", container, "git", "fetch", "origin", branch)
            system("docker", "exec", container, "git", "checkout", "-f", "-b", branch, "origin/#{branch}")
            system("docker", "exec", container, "git", "clean", "-fd")
          else
            system("docker", "exec", container, "git", "fetch", "origin", "main")
            system("docker", "exec", container, "git", "checkout", "-f", "--no-track", "-b", branch, "origin/main")
            system("docker", "exec", container, "git", "clean", "-fd")
          end
        end

        # If you have the official anthropic marketplace plugin installed, it will always make a call to the anthropic github repo on claude startup. It uses SSH, but it should be https for universal compatibility since its a public repository.
        system("docker", "exec", container, "git", "config", "--global", "url.\"https://github.com/anthropics/\".insteadOf", "ssh://git@github.com/anthropics/")
      end

      def run_init_script(container)
        return unless @config.init_script && !@config.init_script.to_s.empty?

        script_path = File.expand_path(@config.init_script)
        unless File.exist?(script_path)
          warn "Warning: init_script '#{@config.init_script}' not found, skipping."
          return
        end

        home = @config.container_home
        remote_script = "#{home}/.aircon_init.sh"
        system("docker", "cp", script_path, "#{container}:#{remote_script}")
        system("docker", "exec", container, "bash", "-l", remote_script)
      end

      def cleanup_if_last(container, name)
        out, = Open3.capture2("docker", "exec", container, "pgrep", "-x", "bash")
        remaining = out.strip.lines.size

        return unless remaining == 0

        puts "Last session ended. Cleaning up..."
        system("docker", "compose", "-p", name, "down", "-v", "--remove-orphans")
        system("docker", "image", "prune", "-f")
      end
    end
  end
end
