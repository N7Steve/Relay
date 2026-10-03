# Standalone deployment tests: ruby test/deployment/update_relay_test.rb (Linux).
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"

class UpdateRelayTest < Minitest::Test
  SHA = "d7452d794baa3610a3a4d60c0a463d9a9bd3cc85"
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
    FileUtils.mkdir_p(File.join(@dir, "repo", "bin"))
    File.write(File.join(@dir, "repo", "Dockerfile"), "FROM scratch\n")
    File.write(File.join(@dir, "repo", "bin", "update-relay.sh"), "#!/bin/bash\n")
    File.write(File.join(@dir, "repo", "compose.truenas.folder.yml"), "services: {}\n")
    File.write(File.join(@dir, "relay.env"), "PRIVATE_TEST_VALUE=true\n")
    build = { "context" => "https://github.com/N7Steve/Relay.git#old", "args" => { "KEEP" => "value" } }
    services = %w[init web worker].to_h { |name| [ name, { "build" => build, "image" => "relay-local:old", "pull_policy" => "build" } ] }
    services["db"] = { "image" => "postgres:16-bookworm", "environment" => { "POSTGRES_DB" => "relay_production", "POSTGRES_USER" => "relay_user" } }
    services["redis"] = { "image" => "redis:7.4-bookworm" }
    services["web"]["ports"] = [ "3002:3000" ]
    services["init"]["volumes"] = [ "#{@root}:/relay" ]
    services["db"]["volumes"] = [ "#{@root}/postgres:/var/lib/postgresql/data", "#{@root}/config:/config:ro" ]
    services["redis"]["volumes"] = [ "#{@root}/redis:/data" ]
    %w[web worker].each { |name| services[name]["volumes"] = [ "#{@root}/config:/config:ro", "#{@root}/storage:/rails/storage" ] }
    @config = { "services" => services }
    write_config
    driver = <<~'RUBY'
      #!/usr/bin/env ruby
      require "json"
      dir = ENV.fetch("MOCK_DIR")
      args = ARGV
      tool = File.basename($0)
      File.open("#{dir}/calls.jsonl", "a") { |f| f.puts JSON.generate([tool, *args]) }
      if tool == "mountpoint"
        exit ENV["FAIL_AT"] == "pool" ? 1 : 0
      elsif tool == "curl"
        exit 22 if ENV["FAIL_AT"] == "github"
        if args.last.end_with?("/commits/main")
          puts JSON.generate({ sha: ENV["FAIL_AT"] == "invalid_sha" ? "main" : ENV.fetch("TARGET_SHA") })
        elsif args.last.include?("/tarball/")
          exec "tar", "-czf", "-", "-C", dir, "repo"
        else
          abort "Unexpected curl URL"
        end
      elsif tool == "midclt"
        case args[1]
        when "app.get_instance"
          puts JSON.generate({ custom_app: true, state: "RUNNING" })
        when "app.config"
          config = JSON.parse(File.read("#{dir}/config.json"))
          if ENV["FAIL_AT"] == "config_changed" && File.exist?("#{dir}/config-read")
            config["services"]["web"]["ports"] = ["3003:3000"]
          end
          File.write("#{dir}/config-read", "true")
          print JSON.generate(config)
        when "-j"
          File.write("#{dir}/payload.json", args.last)
          exit 1 if ENV["FAIL_AT"] == "update"
          puts "{}"
        else
          abort "Unexpected midclt command: #{args.inspect}"
        end
      elsif tool == "docker"
        case args[0]
        when "ps"
          service = args.find { |v| v.start_with?("label=com.docker.compose.service=") }
          puts service.split("=").last if service
        when "inspect"
          format = args[2]
          puts({ "{{.State.ExitCode}}" => "0", "{{.State.Health.Status}}" => "healthy", "{{.State.Running}}" => "true" }.fetch(format))
        when "build"
          exit 1 if ENV["FAIL_AT"] == "build"
        when "run"
          puts ENV.fetch("TARGET_SHA")
        when "exec"
          if args.last.include?("pg_dump")
            exit 1 if ENV["FAIL_AT"] == "dump"
            print "PGDMP-test-fixture"
          elsif args.include?("pg_restore")
            STDIN.read
            puts "test table of contents"
          elsif args.last == "ping"
            puts "PONG"
          elsif args.last == "SAVE"
            puts "OK"
          elsif args.include?("ruby") && args.last.include?("BUILD_COMMIT_SHA")
            puts File.exist?("#{dir}/payload.json") || ENV["FAIL_AT"] == "already_current" ? ENV.fetch("TARGET_SHA") : "bootstrap-main"
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
    %w[docker midclt curl mountpoint].each do |name|
      path = File.join(@bin, name)
      File.write(path, driver)
      FileUtils.chmod(0755, path)
    end
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir
  end

  def test_check_does_not_build_stop_or_update
    output, status = run_script("--check")
    assert status.success?, output
    refute calls.any? { |c| c[0] == "docker" && %w[build stop run].include?(c[1]) }
    refute calls.any? { |c| c.include?("app.update") }
    assert_empty Dir.glob("#{@root}/backups/relay-*")
  end

  def test_unexpected_source_is_rejected_before_mutations
    @config["services"]["web"]["build"]["context"] = "https://github.com/N7Steve/sure.git#old"
    write_config
    output, status = run_script
    refute status.success?, output
    refute calls.any? { |c| c[0] == "docker" }
  end

  def test_build_failure_leaves_original_services_running
    output, status = run_script(fail_at: "build")
    refute status.success?, output
    refute calls.any? { |c| c[0] == "docker" && c[1] == "stop" }
    refute calls.any? { |c| c.include?("app.update") }
  end

  def test_dump_failure_resumes_original_services_without_update
    output, status = run_script(fail_at: "dump")
    refute status.success?, output
    assert_includes calls, [ "docker", "start", "worker", "web" ]
    refute calls.any? { |c| c.include?("app.update") }
    assert_empty Dir.glob("#{@root}/backups/*/BACKUP_COMPLETE")
  end

  def test_update_failure_keeps_complete_backup_and_does_not_restart_old_code
    output, status = run_script(fail_at: "update")
    refute status.success?, output
    assert_equal 1, Dir.glob("#{@root}/backups/*/BACKUP_COMPLETE").length
    assert_empty Dir.glob("#{@root}/backups/*/UPDATE_COMPLETE")
    refute calls.any? { |c| c[0] == "docker" && c[1] == "start" }
  end

  def test_configuration_changed_during_build_is_not_overwritten
    output, status = run_script(fail_at: "config_changed")
    refute status.success?, output
    assert_includes calls, [ "docker", "start", "redis", "worker", "web" ]
    refute calls.any? { |c| c.include?("app.update") }
    assert_equal 1, Dir.glob("#{@root}/backups/*/BACKUP_COMPLETE").length
  end

  def test_success_preserves_configuration_and_verifies_after_backup
    output, status = run_script
    assert status.success?, output
    updated = JSON.parse(File.read("#{@dir}/payload.json")).fetch("custom_compose_config")
    refute updated.key?("volumes")
    assert_equal @config["services"]["db"], updated["services"]["db"]
    assert_equal @config["services"]["redis"], updated["services"]["redis"]
    assert_equal [ "3002:3000" ], updated["services"]["web"]["ports"]
    %w[init web worker].each do |name|
      assert_equal "never", updated["services"][name]["pull_policy"]
      assert_equal SHA, updated["services"][name]["build"]["args"]["BUILD_COMMIT_SHA"]
      assert_equal "value", updated["services"][name]["build"]["args"]["KEEP"]
    end
    assert_equal 1, Dir.glob("#{@root}/backups/*/UPDATE_COMPLETE").length
    assert_equal SHA, File.read("#{@root}/deployment/deployed-sha").strip
    assert File.exist?("#{@root}/releases/#{SHA}/Dockerfile")
    assert_equal 1, Dir.glob("#{@root}/logs/*.log").length
    assert_empty Dir.glob("#{@root}/.work/*")
    assert calls.index { |c| c[1] == "build" } < calls.index { |c| c[1] == "stop" }
    assert calls.index { |c| c.include?("pg_restore") } < calls.index { |c| c.include?("app.update") }
    assert calls.any? { |c| c.last.include?(". /config/relay.env") && c.last.include?("db:abort_if_pending_migrations") }
  end

  def test_latest_commit_already_running_skips_backup_and_build
    output, status = run_script(fail_at: "already_current")
    assert status.success?, output
    assert_includes output, "ya está actualizado"
    refute calls.any? { |c| c[0] == "docker" && %w[build stop].include?(c[1]) }
    assert_empty Dir.glob("#{@root}/backups/relay-*")
  end

  def test_github_failure_leaves_app_untouched
    output, status = run_script(fail_at: "github")
    refute status.success?, output
    refute calls.any? { |c| %w[docker midclt].include?(c[0]) }
  end

  def test_invalid_commit_is_rejected
    output, status = run_script(fail_at: "invalid_sha")
    refute status.success?, output
    refute calls.any? { |c| %w[docker midclt].include?(c[0]) }
  end

  def test_other_storage_paths_are_rejected_without_transferring_data
    @config["services"]["web"]["volumes"][1] = "/mnt/other/storage:/rails/storage"
    write_config
    output, status = run_script
    refute status.success?, output
    refute calls.any? { |c| c[0] == "docker" }
  end

  def test_pool_must_be_mounted_before_writing_to_its_folder
    output, status = run_script(fail_at: "pool")
    refute status.success?, output
    assert_equal [ [ "mountpoint", "-q", "/mnt/AppsPool" ] ], calls
    refute Dir.exist?("#{@root}/logs")
  end

  def test_releases_without_deployment_files_can_use_embedded_bootstrap
    FileUtils.rm(File.join(@dir, "repo", "bin", "update-relay.sh"))
    FileUtils.rm(File.join(@dir, "repo", "compose.truenas.folder.yml"))
    output, status = run_script
    assert status.success?, output
    requests = calls.select { |c| c[0] == "curl" }.map(&:last)
    assert_equal [ "https://api.github.com/repos/N7Steve/Relay/commits/main", "https://api.github.com/repos/N7Steve/Relay/tarball/#{SHA}" ], requests
    assert_equal "#{@root}/releases/#{SHA}", calls.find { |c| c[0] == "docker" && c[1] == "build" }.last
  end

  private

    def write_config
      File.write(File.join(@dir, "config.json"), JSON.generate(@config))
    end

    def calls
      File.readlines(File.join(@dir, "calls.jsonl")).map { |line| JSON.parse(line) }
    end

    def run_script(*args, fail_at: "")
      env = { "PATH" => "#{@bin}:#{ENV.fetch('PATH')}", "MOCK_DIR" => @dir, "TARGET_SHA" => SHA, "FAIL_AT" => fail_at }
      Open3.capture2e(env, "bash", @script, *args)
    end
end
