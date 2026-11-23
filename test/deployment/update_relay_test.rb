# Standalone deployment tests: ruby test/deployment/update_relay_test.rb (Linux).
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"

class UpdateRelayTest < Minitest::Test
  SHA = "d7452d794baa3610a3a4d60c0a463d9a9bd3cc85"
  IMAGE_ID = "sha256:#{'a' * 64}"
  OLD_IMAGE_ID = "sha256:#{'0' * 64}"
  STALE_IMAGE_ID = "sha256:#{'1' * 64}"
  DIGEST = "100.81.25.109:30008/n7steve/relay@sha256:#{'b' * 64}"
  SCRIPT = File.expand_path("../../bin/update-relay.sh", __dir__)

  def setup
    skip "Requires Linux root, /mnt and Python 3; all deployment commands are mocked" unless
      Process.uid.zero? && Dir.exist?("/mnt") && system("python3", "--version", out: File::NULL, err: File::NULL)
    @dir = Dir.mktmpdir("relay-update-tests-", "/mnt")
    @bin = File.join(@dir, "bin")
    FileUtils.mkdir_p(@bin)
    @root = File.join(@dir, "relay")
    %w[config postgres storage redis].each { |name| FileUtils.mkdir_p(File.join(@root, name)) }
    @script = File.join(@dir, "update-relay.sh")
    File.write(@script, File.read(SCRIPT).sub("ROOT=/mnt/AppsPool/relay", "ROOT=#{@root}"))
    File.write(File.join(@dir, "relay.env"), "PRIVATE_TEST_VALUE=true\n")
    services = %w[init web worker].to_h { |name| [ name, { "image" => "100.81.25.109:30008/n7steve/relay:stable", "pull_policy" => "missing" } ] }
    services["db"] = { "image" => "postgres:16-bookworm", "environment" => { "POSTGRES_DB" => "relay_production", "POSTGRES_USER" => "relay_user" } }
    services["redis"] = { "image" => "redis:7.4-bookworm" }
    services["web"]["ports"] = [ "3002:3000" ]
    services["init"]["volumes"] = [ "#{@root}:/relay" ]
    services["db"]["volumes"] = [ "#{@root}/postgres:/var/lib/postgresql/data", "#{@root}/config:/config:ro" ]
    services["redis"]["volumes"] = [ "#{@root}/redis:/data" ]
    %w[web worker].each { |name| services[name]["volumes"] = [ "#{@root}/config:/config:ro", "#{@root}/storage:/rails/storage" ] }
    @config = { "x-relay-image" => { "image" => "100.81.25.109:30008/n7steve/relay:stable", "pull_policy" => "missing" }, "services" => services }
    write_config
    driver = <<~'RUBY'
      #!/usr/bin/env ruby
      require "json"
      dir = ENV.fetch("MOCK_DIR")
      args = ARGV
      tool = File.basename($0)
      File.open("#{dir}/calls.jsonl", "a") { |f| f.puts JSON.generate([tool, *args]) }
      fail_at = ENV["FAIL_AT"]
      updated = File.exist?("#{dir}/payload.json") || fail_at == "already_current"
      if tool == "mountpoint"
        exit fail_at == "pool" ? 1 : 0
      elsif tool == "midclt"
        case args[1]
        when "app.get_instance"
          puts JSON.generate({ custom_app: true, state: "RUNNING" })
        when "app.config"
          config = JSON.parse(File.read("#{dir}/config.json"))
          if fail_at == "config_changed" && File.exist?("#{dir}/config-read")
            config["services"]["web"]["ports"] = ["3003:3000"]
          end
          # TrueNAS stored the new configuration although the client failed.
          config = JSON.parse(File.read("#{dir}/payload.json")).fetch("custom_compose_config") if fail_at == "update_applied" && File.exist?("#{dir}/payload.json")
          File.write("#{dir}/config-read", "true")
          print JSON.generate(config)
        when "core.get_jobs"
          options = JSON.parse(args.last)
          if options["count"]
            active = %w[update_running update_pending].include?(fail_at)
            puts(active && (fail_at == "update_pending" || File.exist?("#{dir}/submitted")) ? 1 : 0)
          else
            abort "Unexpected job lookup: #{args.inspect}" unless options["select"] == ["state"] && JSON.parse(args[2]) == [["id", "=", 123]]
            puts JSON.generate([{state: fail_at == "job_failed" ? "FAILED" : "SUCCESS"}])
          end
        else
          abort "Unexpected midclt command: #{args.inspect}"
        end
      elsif tool == "docker"
        case args[0]
        when "pull"
          File.write("#{dir}/docker-config", ENV["DOCKER_CONFIG"].to_s)
          exit 1 if fail_at == "registry"
        when "image"
          case args[1]
          when "inspect"
            image = {
              "Id" => ENV.fetch("IMAGE_ID"),
              "RepoDigests" => [ ENV.fetch("DIGEST") ],
              "Os" => "linux",
              "Architecture" => fail_at == "arch" ? "arm64" : "amd64",
              "Config" => { "Env" => fail_at == "no_commit" ? [ "PATH=/usr/bin" ] : [ "PATH=/usr/bin", "BUILD_COMMIT_SHA=#{ENV.fetch('TARGET_SHA')}" ] }
            }
            puts JSON.generate([ image ])
          when "ls"
            puts "100.81.25.109:30008/n7steve/relay #{ENV.fetch('STALE_IMAGE_ID')}"
            puts "100.81.25.109:30008/n7steve/relay #{ENV.fetch('IMAGE_ID')}"
            puts "postgres #{ENV.fetch('STALE_IMAGE_ID').tr('1', '2')}"
          when "rm"
            # Only mocks: never remove a real image.
          else
            abort "Unexpected docker image command: #{args.inspect}"
          end
        when "ps"
          service = args.find { |v| v.start_with?("label=com.docker.compose.service=") }
          puts service.split("=").last if service
        when "inspect"
          format = args[2]
          image = updated ? ENV.fetch("IMAGE_ID") : ENV.fetch("OLD_IMAGE_ID")
          puts({ "{{.State.ExitCode}}" => "0", "{{.State.Health.Status}}" => "healthy", "{{.State.Running}}" => "true", "{{.Image}}" => image }.fetch(format))
        when "exec"
          if args.last.include?("pg_dump")
            exit 1 if fail_at == "dump"
            print "PGDMP-test-fixture"
          elsif args.include?("pg_restore")
            STDIN.read
            puts "test table of contents"
          elsif args.last == "ping"
            puts "PONG"
          elsif args.last == "SAVE"
            puts "OK"
          elsif args.include?("ruby") && args.last.include?("BUILD_COMMIT_SHA")
            puts updated ? ENV.fetch("TARGET_SHA") : "previous"
          end
        when "cp"
          exec "tar", "-cf", "-", "-C", dir, "relay.env"
        when "stop", "start"
          # Only mocks: never operate a real container.
        else
          abort "Unexpected docker command: #{args.inspect}"
        end
      end
    RUBY
    %w[docker midclt mountpoint].each do |name|
      path = File.join(@bin, name)
      File.write(path, driver)
      FileUtils.chmod(0755, path)
    end
    install_middleware_client
  end

  def teardown
    FileUtils.rm_f(@client) if @client
    FileUtils.remove_entry(@dir) if @dir
  end

  def test_check_does_not_stop_or_update
    output, status = run_script("--check")
    assert status.success?, output
    refute calls.any? { |c| c[0] == "docker" && %w[stop rm].include?(c[1]) }
    refute calls.any? { |c| c.include?("app.update") }
    assert_empty Dir.glob("#{@root}/backups/relay-*")
  end

  def test_unexpected_image_is_rejected_before_mutations
    @config["services"]["web"]["image"] = "ghcr.io/someone/relay:stable"
    write_config
    output, status = run_script
    refute status.success?, output
    refute calls.any? { |c| c[0] == "docker" && %w[exec stop].include?(c[1]) }
    refute calls.any? { |c| c.include?("app.update") }
  end

  def test_registry_failure_leaves_app_untouched
    output, status = run_script(fail_at: "registry")
    refute status.success?, output
    assert_equal [ [ "docker", "pull", "--quiet", "100.81.25.109:30008/n7steve/relay:stable" ] ], calls.select { |c| c[0] == "docker" }
    refute calls.any? { |c| c[0] == "midclt" }
  end

  def test_image_without_commit_is_rejected
    output, status = run_script(fail_at: "no_commit")
    refute status.success?, output
    refute calls.any? { |c| c[0] == "midclt" }
  end

  def test_image_for_another_architecture_is_rejected
    output, status = run_script(fail_at: "arch")
    refute status.success?, output
    refute calls.any? { |c| c[0] == "midclt" }
  end

  def test_dump_failure_resumes_original_services_without_update
    output, status = run_script(fail_at: "dump")
    refute status.success?, output
    assert_includes calls, [ "docker", "start", "worker", "web" ]
    refute calls.any? { |c| c.include?("app.update") }
    assert_empty Dir.glob("#{@root}/backups/*/BACKUP_COMPLETE")
  end

  def test_rejected_update_resumes_the_previous_version_and_keeps_the_error_in_the_backup
    output, status = run_script(fail_at: "update")
    refute status.success?, output
    assert_equal 1, Dir.glob("#{@root}/backups/*/BACKUP_COMPLETE").length
    assert_empty Dir.glob("#{@root}/backups/*/UPDATE_COMPLETE")
    assert_includes calls, [ "docker", "start", "redis", "worker", "web" ]
    assert_includes output, "no modificó la app"
    refute_includes output, "ValidationError"
    assert_operator File.size(Dir.glob("#{@root}/backups/*/update-error.txt").first), :>, 5_000
  end

  def test_update_that_may_have_been_applied_does_not_resume_old_code
    output, status = run_script(fail_at: "update_applied")
    refute status.success?, output
    assert_includes output, "No está claro"
    refute calls.any? { |c| c[0] == "docker" && c[1] == "start" }
    assert_empty Dir.glob("#{@root}/backups/*/UPDATE_COMPLETE")
  end

  def test_update_job_still_running_does_not_resume_old_code
    output, status = run_script(fail_at: "update_running")
    refute status.success?, output
    assert_includes output, "trabajos activos: 1"
    refute calls.any? { |c| c[0] == "docker" && c[1] == "start" }
  end

  def test_failed_job_resumes_the_previous_version
    output, status = run_script(fail_at: "job_failed")
    refute status.success?, output
    assert_includes calls, [ "docker", "start", "redis", "worker", "web" ]
    assert_includes File.read(Dir.glob("#{@root}/backups/*/update-error.txt").first), "Trabajo 123: FAILED"
  end

  def test_killed_client_resumes_relay_when_no_job_or_config_change_exists
    output, status = run_script(fail_at: "update_killed")
    refute status.success?, output
    assert_includes calls, [ "docker", "start", "redis", "worker", "web" ]
    assert_equal 1, Dir.glob("#{@root}/backups/*/BACKUP_COMPLETE").length
    assert_empty Dir.glob("#{@root}/backups/*/UPDATE_COMPLETE")
  end

  def test_existing_update_blocks_downtime
    output, status = run_script(fail_at: "update_pending")
    refute status.success?, output
    refute calls.any? { |c| c[0] == "docker" && c[1] == "stop" }
    refute calls.any? { |c| c.include?("app.update") }
  end

  def test_cron_does_not_stop_relay_again_for_a_failed_digest
    _, status = run_script("--cron", fail_at: "update")
    refute status.success?
    stops = calls.count { |c| c[0] == "docker" && c[1] == "stop" }

    output, status = run_script("--cron")
    assert status.success?, output
    assert_equal stops, calls.count { |c| c[0] == "docker" && c[1] == "stop" }

    output, status = run_script
    assert status.success?, output
    assert_equal 1, Dir.glob("#{@root}/backups/*/UPDATE_COMPLETE").length
    refute File.exist?("#{@root}/deployment/update-attempted-image")
  end

  def test_configuration_changed_during_backup_is_not_overwritten
    output, status = run_script(fail_at: "config_changed")
    refute status.success?, output
    assert_includes calls, [ "docker", "start", "redis", "worker", "web" ]
    refute calls.any? { |c| c.include?("app.update") }
    assert_equal 1, Dir.glob("#{@root}/backups/*/BACKUP_COMPLETE").length
  end

  def test_configuration_never_travels_on_a_command_line
    # TrueNAS audits commands through sudo, which kills a process whose long
    # arguments it cannot verify; the configuration goes over the middleware socket.
    output, status = run_script("--cron")
    assert status.success?, output
    assert_includes calls, [ "middleware", "app.update", "relay" ]
    longest = calls.flatten.map { |arg| arg.to_s.length }.max
    assert_operator longest, :<, 500
  end

  def test_success_pins_the_published_digest_and_verifies_after_backup
    output, status = run_script
    assert status.success?, output
    updated = JSON.parse(File.read("#{@dir}/payload.json")).fetch("custom_compose_config")
    refute updated.key?("volumes")
    assert_equal @config["services"]["db"], updated["services"]["db"]
    assert_equal @config["services"]["redis"], updated["services"]["redis"]
    assert_equal [ "3002:3000" ], updated["services"]["web"]["ports"]
    %w[init web worker].each do |name|
      assert_equal DIGEST, updated["services"][name]["image"]
      assert_equal "missing", updated["services"][name]["pull_policy"]
      refute updated["services"][name].key?("build")
    end
    assert_equal({ "image" => DIGEST, "pull_policy" => "missing" }, updated["x-relay-image"])
    assert_equal 1, Dir.glob("#{@root}/backups/*/UPDATE_COMPLETE").length
    assert_equal SHA, File.read("#{@root}/deployment/deployed-sha").strip
    assert_equal DIGEST, File.read("#{@root}/deployment/deployed-image").strip
    assert_equal 1, Dir.glob("#{@root}/logs/*.log").length
    assert_empty Dir.glob("#{@root}/.work/*")
    assert calls.index { |c| c[1] == "pull" } < calls.index { |c| c[1] == "stop" }
    assert calls.index { |c| c.include?("pg_restore") } < calls.index { |c| c.include?("app.update") }
    assert calls.any? { |c| c.last.include?(". /config/relay.env") && c.last.include?("db:abort_if_pending_migrations") }
    removed = calls.select { |c| c[0] == "docker" && c[1] == "image" && c[2] == "rm" }.map(&:last)
    assert_equal [ STALE_IMAGE_ID ], removed
  end

  def test_legacy_ghcr_installation_is_converted
    %w[init web worker].each do |name|
      @config["services"][name]["image"] = "ghcr.io/n7steve/relay@sha256:#{'c' * 64}"
    end
    write_config
    output, status = run_script
    assert status.success?, output
    updated = JSON.parse(File.read("#{@dir}/payload.json")).fetch("custom_compose_config")
    %w[init web worker].each do |name|
      assert_equal DIGEST, updated["services"][name]["image"]
    end
  end

  def test_legacy_source_build_installation_is_converted
    build = { "context" => "https://github.com/N7Steve/Relay.git#old", "args" => { "BUILD_COMMIT_SHA" => "old" } }
    %w[init web worker].each do |name|
      @config["services"][name].merge!("image" => "relay-local:sha-old", "pull_policy" => "never", "build" => build)
    end
    write_config
    output, status = run_script
    assert status.success?, output
    updated = JSON.parse(File.read("#{@dir}/payload.json")).fetch("custom_compose_config")
    %w[init web worker].each do |name|
      assert_equal DIGEST, updated["services"][name]["image"]
      refute updated["services"][name].key?("build")
    end
  end

  def test_legacy_build_from_another_source_is_rejected
    build = { "context" => "https://github.com/N7Steve/sure.git#old" }
    @config["services"]["web"].merge!("image" => "relay-local:sha-old", "build" => build)
    write_config
    output, status = run_script
    refute status.success?, output
    refute calls.any? { |c| c.include?("app.update") }
  end

  def test_published_image_already_running_skips_backup
    output, status = run_script(fail_at: "already_current")
    assert status.success?, output
    assert_includes output, "ya ejecuta la imagen publicada"
    refute calls.any? { |c| c[0] == "docker" && c[1] == "stop" }
    assert_empty Dir.glob("#{@root}/backups/relay-*")
    assert_equal 1, Dir.glob("#{@root}/logs/*.log").length
  end

  def test_cron_run_without_changes_leaves_no_log
    output, status = run_script("--cron", fail_at: "already_current")
    assert status.success?, output
    assert_empty Dir.glob("#{@root}/logs/*.log")
  end

  def test_cron_run_applies_a_new_image
    output, status = run_script("--cron")
    assert status.success?, output
    assert_equal 1, Dir.glob("#{@root}/backups/*/UPDATE_COMPLETE").length
    assert_equal 1, Dir.glob("#{@root}/logs/*.log").length
  end

  def test_other_storage_paths_are_rejected_without_transferring_data
    @config["services"]["web"]["volumes"][1] = "/mnt/other/storage:/rails/storage"
    write_config
    output, status = run_script
    refute status.success?, output
    refute calls.any? { |c| c[0] == "docker" && %w[exec stop].include?(c[1]) }
  end

  def test_pool_must_be_mounted_before_writing_to_its_folder
    output, status = run_script(fail_at: "pool")
    refute status.success?, output
    assert_equal [ [ "mountpoint", "-q", "/mnt/AppsPool" ] ], calls
    refute Dir.exist?("#{@root}/logs")
  end

  def test_private_registry_credentials_are_read_from_the_app_folder
    FileUtils.mkdir_p("#{@root}/registry")
    File.write("#{@root}/registry/config.json", "{}")
    output, status = run_script("--check")
    assert status.success?, output
    assert_equal "#{@root}/registry", File.read("#{@dir}/docker-config")
  end

  def test_public_registry_uses_default_docker_credentials
    output, status = run_script("--check")
    assert status.success?, output
    assert_equal "", File.read("#{@dir}/docker-config")
  end

  private

    # The updater submits app.update with TrueNAS's Python client; this stand-in
    # records the call and fails as FAIL_AT asks. It never replaces a real client.
    def install_middleware_client
      _, found = Open3.capture2e("python3", "-I", "-c", "import truenas_api_client")
      skip "A real truenas_api_client is installed; run these tests in a disposable container" if found.success?
      site, = Open3.capture2("python3", "-I", "-c", "import site; print(site.getsitepackages()[0])")
      FileUtils.mkdir_p(site.strip)
      @client = File.join(site.strip, "truenas_api_client.py")
      File.write(@client, <<~'PYTHON')
        import json
        import os
        import signal
        import sys


        class Client:
            def __enter__(self):
                return self

            def __exit__(self, *error):
                return False

            def call(self, method, *params):
                folder = os.environ["MOCK_DIR"]
                fail_at = os.environ.get("FAIL_AT", "")
                with open(os.path.join(folder, "calls.jsonl"), "a") as log:
                    log.write(json.dumps(["middleware", method, params[0]]) + "\n")
                if method != "app.update":
                    raise RuntimeError("Unexpected middleware call: " + method)
                open(os.path.join(folder, "submitted"), "w").write("true")
                if fail_at == "update_killed":
                    os.kill(os.getpid(), signal.SIGKILL)
                if fail_at in ("update", "update_running"):
                    # Rejected before anything was stored; the error is huge and noisy.
                    sys.stderr.write("ValidationError: " + "expected {config}, got {config} " * 200 + "\n")
                    raise RuntimeError("rejected")
                if fail_at != "job_failed":
                    with open(os.path.join(folder, "payload.json"), "w") as payload:
                        json.dump(params[1], payload)
                if fail_at == "update_applied":
                    raise ConnectionError("connection lost")
                return 123
      PYTHON
    end

    def write_config
      File.write(File.join(@dir, "config.json"), JSON.generate(@config))
    end

    def calls
      File.readlines(File.join(@dir, "calls.jsonl")).map { |line| JSON.parse(line) }
    end

    def run_script(*args, fail_at: "")
      env = {
        "PATH" => "#{@bin}:#{ENV.fetch('PATH')}", "MOCK_DIR" => @dir, "TARGET_SHA" => SHA, "FAIL_AT" => fail_at,
        "IMAGE_ID" => IMAGE_ID, "OLD_IMAGE_ID" => OLD_IMAGE_ID, "STALE_IMAGE_ID" => STALE_IMAGE_ID, "DIGEST" => DIGEST,
        "DOCKER_CONFIG" => nil
      }
      Open3.capture2e(env, "bash", @script, *args)
    end
end
