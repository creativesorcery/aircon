# frozen_string_literal: true

require "yaml"
require "erb"

module Aircon
  class Configuration
    CONFIG_FILE = ".aircon/aircon.yml"
    VALID_CREDENTIALS_SOURCES = %w[keychain file oauth_token].freeze

    DEFAULTS = {
      "compose_file" => ".aircon/docker-compose.yml",
      "app_name" => nil,
      "gh_token" => nil,
      "credentials_source" => "keychain",
      "claude_code_oauth_token" => nil,
      "workspace_path" => nil,
      "claude_config_path" => "~/.claude.json",
      "claude_dir_path" => "~/.claude",
      "service" => "app",
      "git_email" => "claude_docker@localhost.com",
      "git_name" => "Claude Docker",
      "container_user" => "appuser",
      "init_script" => ".aircon/aircon_init.sh"
    }.freeze

    attr_reader :compose_file, :app_name, :gh_token, :credentials_source, :claude_code_oauth_token,
                :workspace_path, :claude_config_path, :claude_dir_path, :service, :git_email,
                :git_name, :container_user, :init_script

    def initialize(dir: Dir.pwd)
      attrs = DEFAULTS.dup
      config_path = File.join(dir, CONFIG_FILE)

      if File.exist?(config_path)
        raw = File.read(config_path)
        rendered = ERB.new(raw).result
        user_attrs = YAML.safe_load(rendered) || {}
        attrs.merge!(user_attrs)
      end

      @compose_file = attrs["compose_file"]
      @app_name = attrs["app_name"] || File.basename(dir)
      @gh_token = attrs["gh_token"]
      @credentials_source = attrs["credentials_source"]
      @claude_code_oauth_token = attrs["claude_code_oauth_token"]
      @workspace_path = attrs["workspace_path"] || "/workspace"
      @claude_config_path = attrs["claude_config_path"]
      @claude_dir_path = attrs["claude_dir_path"]
      @service = attrs["service"]
      @git_email = attrs["git_email"]
      @git_name = attrs["git_name"]
      @container_user = attrs["container_user"]
      @init_script = attrs["init_script"]

      validate!
    end

    def container_home
      @container_user == "root" ? "/root" : "/home/#{@container_user}"
    end

    private

    def validate!
      return if VALID_CREDENTIALS_SOURCES.include?(@credentials_source)

      raise ArgumentError,
            "Invalid credentials_source: #{@credentials_source.inspect}. " \
            "Must be one of: #{VALID_CREDENTIALS_SOURCES.join(', ')}"
    end
  end
end
