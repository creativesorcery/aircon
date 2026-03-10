# frozen_string_literal: true

require "open3"

module Aircon
  module Docker
    module_function

    def find_container(project:, service:)
      out, _, status = Open3.capture3(
        "docker", "ps", "-q",
        "--filter", "label=com.docker.compose.project=#{project}",
        "--filter", "label=com.docker.compose.service=#{service}"
      )
      return nil unless status.success?

      id = out.strip.lines.first&.strip
      id.nil? || id.empty? ? nil : id
    end

    def hex_encode_id(container_id)
      container_id.each_byte.map { |b| format("%02x", b) }.join
    end
  end
end
