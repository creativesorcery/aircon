# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aircon::CLI do
  include FakeFS::SpecHelpers

  let(:container_id) { "abc123" }
  let(:ok) { instance_double(Process::Status, success?: true) }

  let(:config) do
    instance_double(Aircon::Configuration,
      service: "app",
      compose_file: "docker-compose.yml",
      app_name: "myapp",
      gh_token: "ghp_testtoken",
      credentials_source: "oauth_token",
      claude_code_oauth_token: "test_oauth",
      git_email: "test@example.com",
      git_name: "Test User",
      container_home: "/home/vscode",
      container_user: "vscode",
      claude_config_path: "~/.claude.json",
      claude_dir_path: "~/.claude",
      workspace_path: "/workspace",
      init_script: nil)
  end

  before { allow(Aircon::Configuration).to receive(:new).and_return(config) }

  describe "aircon up" do
    before do
      # Intercept Commands::Up.new to stub system() on the real instance and save a reference.
      # Everything else (path rewriting, branch logic, env injection) runs through the real code.
      allow(Aircon::Commands::Up).to receive(:new).and_wrap_original do |orig, *args, **kwargs|
        @up = orig.call(*args, **kwargs)
        allow(@up).to receive(:system).and_return(true)
        @up
      end

      # First find_container call (before compose up) returns nothing;
      # second call (after compose up) returns the new container.
      allow(Open3).to receive(:capture3)
        .with("docker", "ps", "-q",
              "--filter", "label=com.docker.compose.project=myproject",
              "--filter", "label=com.docker.compose.service=app")
        .and_return(["\n", "", ok], ["#{container_id}\n", "", ok])

      # Branch not found on remote by default
      allow(Open3).to receive(:capture2)
        .with("docker", "exec", container_id, "git", "ls-remote", "--heads", "origin", anything)
        .and_return(["", ok])

      # Bash session still active after attach — no cleanup triggered
      allow(Open3).to receive(:capture2)
        .with("docker", "exec", container_id, "pgrep", "-x", "bash")
        .and_return(["12345\n", instance_double(Process::Status)])
    end

    describe "aircon up <project_name>" do
      it "runs docker compose up with the project name and default port" do
        described_class.start(["up", "myproject"])
        expect(@up).to have_received(:system).with(
          { "HOST_PORT" => "3001", "AIRCON_APP_NAME" => "myapp",
            "AIRCON_CONTAINER_USER" => "vscode", "AIRCON_WORKSPACE_PATH" => "/workspace" },
          "docker", "compose", "-f", "docker-compose.yml", "-p", "myproject", "up", "-d", "--build"
        )
      end

      it "injects GH_TOKEN into /etc/bash.bashrc" do
        described_class.start(["up", "myproject"])
        expect(@up).to have_received(:system).with(
          "docker", "exec", "-u", "root", container_id, "bash", "-c",
          a_string_including("export GH_TOKEN=\"ghp_testtoken\"")
        )
      end

      it "injects GITHUB_PERSONAL_ACCESS_TOKEN as an alias" do
        described_class.start(["up", "myproject"])
        expect(@up).to have_received(:system).with(
          "docker", "exec", "-u", "root", container_id, "bash", "-c",
          a_string_including("export GITHUB_PERSONAL_ACCESS_TOKEN=\"ghp_testtoken\"")
        )
      end

      it "injects CLAUDE_CODE_OAUTH_TOKEN into /etc/bash.bashrc when credentials_source is oauth_token" do
        described_class.start(["up", "myproject"])
        expect(@up).to have_received(:system).with(
          "docker", "exec", "-u", "root", container_id, "bash", "-c",
          a_string_including("export CLAUDE_CODE_OAUTH_TOKEN=\"test_oauth\"")
        )
      end

      context "when credentials_source is keychain" do
        before do
          allow(config).to receive(:credentials_source).and_return("keychain")
          allow(Open3).to receive(:capture2)
            .with("security", "find-generic-password", "-a", anything, "-w", "-s", "Claude Code-credentials")
            .and_return(["{\"token\":\"keychain_cred\"}", ok])
        end

        it "does not inject CLAUDE_CODE_OAUTH_TOKEN" do
          described_class.start(["up", "myproject"])
          expect(@up).not_to have_received(:system).with(
            "docker", "exec", "-u", "root", container_id, "bash", "-c",
            a_string_including("export CLAUDE_CODE_OAUTH_TOKEN=")
          )
        end
      end

      context "when credentials_source is file" do
        before do
          allow(config).to receive(:credentials_source).and_return("file")
          FileUtils.mkdir_p(File.expand_path("~/.claude"))
          File.write(File.expand_path("~/.claude/.credentials.json"), '{"token":"file_cred"}')
        end

        it "does not inject CLAUDE_CODE_OAUTH_TOKEN" do
          described_class.start(["up", "myproject"])
          expect(@up).not_to have_received(:system).with(
            "docker", "exec", "-u", "root", container_id, "bash", "-c",
            a_string_including("export CLAUDE_CODE_OAUTH_TOKEN=")
          )
        end
      end

      it "configures git identity in the container" do
        described_class.start(["up", "myproject"])
        expect(@up).to have_received(:system).with(
          "docker", "exec", container_id, "git", "config", "--global", "user.email", "test@example.com"
        )
        expect(@up).to have_received(:system).with(
          "docker", "exec", container_id, "git", "config", "--global", "user.name", "Test User"
        )
      end

      it "rewrites GitHub HTTPS and SSH URLs to use token-based auth" do
        authed = "https://x-access-token:ghp_testtoken@github.com/"
        described_class.start(["up", "myproject"])
        expect(@up).to have_received(:system).with(
          "docker", "exec", container_id, "git", "config", "--global",
          "url.#{authed}.insteadOf", "https://github.com/"
        )
        expect(@up).to have_received(:system).with(
          "docker", "exec", container_id, "git", "config", "--global",
          "url.#{authed}.insteadOf", "git@github.com:"
        )
      end

      context "when a container is already running" do
        before do
          allow(Open3).to receive(:capture3)
            .with("docker", "ps", "-q", any_args)
            .and_return(["#{container_id}\n", "", ok])
        end

        it "attaches an interactive bash session without running compose up" do
          described_class.start(["up", "myproject"])
          expect(@up).to have_received(:system).with("docker", "exec", "-it", container_id, "bash")
          expect(@up).not_to have_received(:system).with(hash_including("HOST_PORT"), any_args)
        end
      end

      context "when the last bash session exits" do
        before do
          allow(Open3).to receive(:capture2)
            .with("docker", "exec", container_id, "pgrep", "-x", "bash")
            .and_return(["", instance_double(Process::Status)])
        end

        it "tears down the project and prunes images" do
          described_class.start(["up", "myproject"])
          expect(@up).to have_received(:system).with(
            "docker", "compose", "-p", "myproject", "down", "-v", "--remove-orphans"
          )
          expect(@up).to have_received(:system).with("docker", "image", "prune", "-f")
        end
      end
    end

    describe "aircon up <project_name> <host_port>" do
      it "passes the port to docker compose" do
        described_class.start(["up", "myproject", "8080"])
        expect(@up).to have_received(:system).with(
          hash_including("HOST_PORT" => "8080"), "docker", "compose", any_args
        )
      end
    end

    describe "aircon up <project_name> --detach" do
      context "when a container is already running" do
        before do
          allow(Open3).to receive(:capture3)
            .with("docker", "ps", "-q", any_args)
            .and_return(["#{container_id}\n", "", ok])
        end

        it "does not attach an interactive bash session" do
          described_class.start(["up", "myproject", "--detach"])
          expect(@up).not_to have_received(:system).with("docker", "exec", "-it", container_id, "bash")
        end
      end

      context "when no container is running" do
        it "starts the container without attaching" do
          described_class.start(["up", "myproject", "--detach"])
          expect(@up).to have_received(:system).with(
            { "HOST_PORT" => "3001", "AIRCON_APP_NAME" => "myapp",
              "AIRCON_CONTAINER_USER" => "vscode", "AIRCON_WORKSPACE_PATH" => "/workspace" },
            "docker", "compose", "-f", "docker-compose.yml", "-p", "myproject", "up", "-d", "--build"
          )
          expect(@up).not_to have_received(:system).with("docker", "exec", "-it", container_id, "bash")
        end
      end
    end

    describe "init_script" do
      context "when init_script is configured and the file exists" do
        before do
          allow(config).to receive(:init_script).and_return("scripts/setup.sh")
          FileUtils.mkdir_p("scripts")
          File.write("scripts/setup.sh", "#!/bin/bash\necho hello")
        end

        it "copies and runs the script in the container after setup" do
          described_class.start(["up", "myproject"])
          expect(@up).to have_received(:system).with(
            "docker", "cp", File.expand_path("scripts/setup.sh"), "#{container_id}:/home/vscode/.aircon_init.sh"
          )
          expect(@up).to have_received(:system).with(
            "docker", "exec", container_id, "bash", "-l", "/home/vscode/.aircon_init.sh"
          )
        end
      end

      context "when init_script is configured but the file does not exist" do
        before { allow(config).to receive(:init_script).and_return("missing.sh") }

        it "skips execution and warns" do
          expect { described_class.start(["up", "myproject"]) }.to output(/init_script.*missing\.sh.*not found/i).to_stderr
          expect(@up).not_to have_received(:system).with(
            "docker", "exec", container_id, "bash", "-l", "/home/vscode/.aircon_init.sh"
          )
        end
      end
    end

    describe "aircon up <project_name> --branch <feature_branch>" do
      context "when the branch does not exist on remote" do
        it "creates a new branch from origin/main" do
          described_class.start(["up", "myproject", "--branch", "new-feature"])
          expect(@up).to have_received(:system).with(
            "docker", "exec", container_id, "git", "fetch", "origin", "main"
          )
          expect(@up).to have_received(:system).with(
            "docker", "exec", container_id, "git", "checkout", "-b", "new-feature", "origin/main"
          )
        end

        it "accepts -b as a short alias" do
          described_class.start(["up", "myproject", "-b", "new-feature"])
          expect(@up).to have_received(:system).with(
            "docker", "exec", container_id, "git", "fetch", "origin", "main"
          )
          expect(@up).to have_received(:system).with(
            "docker", "exec", container_id, "git", "checkout", "-b", "new-feature", "origin/main"
          )
        end
      end

      context "when the branch already exists on remote" do
        before do
          allow(Open3).to receive(:capture2)
            .with("docker", "exec", container_id, "git", "ls-remote", "--heads", "origin", "existing-branch")
            .and_return(["abc123 refs/heads/existing-branch\n", ok])
        end

        it "fetches and checks out the existing branch" do
          described_class.start(["up", "myproject", "--branch", "existing-branch"])
          expect(@up).to have_received(:system).with(
            "docker", "exec", container_id, "git", "fetch", "origin", "existing-branch"
          )
          expect(@up).to have_received(:system).with(
            "docker", "exec", container_id, "git", "checkout", "-b", "existing-branch", "origin/existing-branch"
          )
        end

        it "accepts -b as a short alias" do
          described_class.start(["up", "myproject", "-b", "existing-branch"])
          expect(@up).to have_received(:system).with(
            "docker", "exec", container_id, "git", "fetch", "origin", "existing-branch"
          )
          expect(@up).to have_received(:system).with(
            "docker", "exec", container_id, "git", "checkout", "-b", "existing-branch", "origin/existing-branch"
          )
        end
      end
    end
  end

  describe "aircon down" do
    before do
      allow(Aircon::Commands::Down).to receive(:new).and_wrap_original do |orig, *args, **kwargs|
        @down = orig.call(*args, **kwargs)
        allow(@down).to receive(:system).and_return(true)
        @down
      end
    end

    it "tears down the named project and prunes images" do
      described_class.start(["down", "myproject"])
      expect(@down).to have_received(:system).with(
        "docker", "compose", "-p", "myproject", "down", "-v", "--remove-orphans"
      )
      expect(@down).to have_received(:system).with("docker", "image", "prune", "-f")
    end
  end

  describe "aircon vscode" do
    before do
      allow(Open3).to receive(:capture3)
        .with("docker", "ps", "-q", any_args)
        .and_return(["#{container_id}\n", "", ok])

      allow(Aircon::Commands::Vscode).to receive(:new).and_wrap_original do |orig, *args, **kwargs|
        @vscode = orig.call(*args, **kwargs)
        allow(@vscode).to receive(:system).and_return(true)
        @vscode
      end
    end

    it "opens VS Code with a vscode-remote URI for the container" do
      hex_id = container_id.each_byte.map { |b| format("%02x", b) }.join
      expected_uri = "vscode-remote://attached-container+#{hex_id}/workspace"

      described_class.start(["vscode", "myproject"])
      expect(@vscode).to have_received(:system).with("code", "--folder-uri", expected_uri)
    end

    context "when no container is running" do
      before do
        allow(Open3).to receive(:capture3)
          .with("docker", "ps", "-q", any_args)
          .and_return(["\n", "", ok])
      end

      it "aborts with an error" do
        expect { described_class.start(["vscode", "myproject"]) }.to raise_error(SystemExit)
      end
    end
  end

  describe "aircon init" do
    # FakeFS::SpecHelpers (active for all examples) isolates all file I/O,
    # so no Dir.mktmpdir / Dir.chdir needed here.

    it "creates .aircon/aircon.yml in the current directory" do
      described_class.start(["init"])
      expect(File).to exist(File.join(Dir.pwd, ".aircon", "aircon.yml"))
    end

    it "writes the sample config template" do
      described_class.start(["init"])
      content = File.read(File.join(Dir.pwd, ".aircon", "aircon.yml"))
      expect(content).to include("compose_file")
      expect(content).to include("gh_token")
      expect(content).to include("credentials_source")
      expect(content).to include("claude_code_oauth_token")
      expect(content).to include("container_user")
      expect(content).to include("init_script")
    end

    it "creates .aircon/aircon_init.sh" do
      described_class.start(["init"])
      expect(File).to exist(File.join(Dir.pwd, ".aircon", "aircon_init.sh"))
    end

    it "writes helpful comments to aircon_init.sh" do
      described_class.start(["init"])
      content = File.read(File.join(Dir.pwd, ".aircon", "aircon_init.sh"))
      expect(content).to include("GH_TOKEN")
      expect(content).to include("CLAUDE_CODE_OAUTH_TOKEN")
    end

    it "does not overwrite an existing aircon_init.sh" do
      FileUtils.mkdir_p(File.join(Dir.pwd, ".aircon"))
      File.write(File.join(Dir.pwd, ".aircon", "aircon_init.sh"), "existing")
      described_class.start(["init"])
      expect(File.read(File.join(Dir.pwd, ".aircon", "aircon_init.sh"))).to eq("existing")
    end

    it "does not overwrite an existing .aircon/aircon.yml" do
      FileUtils.mkdir_p(File.join(Dir.pwd, ".aircon"))
      File.write(File.join(Dir.pwd, ".aircon", "aircon.yml"), "existing")
      described_class.start(["init"])
      expect(File.read(File.join(Dir.pwd, ".aircon", "aircon.yml"))).to eq("existing")
    end
  end
end
