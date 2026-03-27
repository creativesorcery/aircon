# frozen_string_literal: true

module Aircon
  module Commands
    class Down
      def initialize(config:)
        @config = config
      end

      def call(name)
        puts "Tearing down containers for '#{name}'..."
        system("docker", "compose", "-p", name, "down", "-v", "--remove-orphans")
        system("docker", "image", "prune", "-f")
      end
    end
  end
end
