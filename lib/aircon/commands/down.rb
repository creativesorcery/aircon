# frozen_string_literal: true

module Aircon
  module Commands
    class Down
      def initialize(config:)
        @config = config
      end

      def call(branch)
        puts "Tearing down containers for '#{branch}'..."
        system("docker", "compose", "-p", branch, "down", "-v", "--remove-orphans")
        system("docker", "image", "prune", "-f")
      end
    end
  end
end
