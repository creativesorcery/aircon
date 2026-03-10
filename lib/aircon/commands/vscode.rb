# frozen_string_literal: true

module Aircon
  module Commands
    class Vscode
      def initialize(config:)
        @config = config
      end

      def call(branch)
        container = Docker.find_container(project: branch, service: @config.service)

        unless container
          abort "Error: No running container found for project '#{branch}'.\n" \
                "Start one first with: aircon up #{branch}"
        end

        hex_id = Docker.hex_encode_id(container)
        folder_uri = "vscode-remote://attached-container+#{hex_id}#{@config.workspace_path}"

        puts "Attaching VS Code to container #{container} for project '#{branch}'..."
        system("code", "--folder-uri", folder_uri)
      end
    end
  end
end
