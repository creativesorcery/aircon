# frozen_string_literal: true

require_relative "lib/aircon/version"

Gem::Specification.new do |spec|
  spec.name = "aircon"
  spec.version = Aircon::VERSION
  spec.authors = ["Philip Nguyen"]
  spec.email = ["5519675+philipqnguyen@users.noreply.github.com"]

  spec.summary = "Manage Docker-based isolated Claude Code development containers"
  spec.description = "Aircon spins up one Docker Compose environment per git branch, " \
                     "injects Claude Code credentials, and attaches an interactive shell or VS Code."
  spec.homepage = "https://github.com/creativesorcery/aircon"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.files = Dir["lib/**/*.rb", "exe/*", "LICENSE.txt", "README.md"]
  spec.bindir = "exe"
  spec.executables = ["aircon"]
  spec.require_paths = ["lib"]

  spec.add_dependency "thor", "~> 1.3"

  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "fakefs"
end
