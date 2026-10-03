require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "yaml"
require "open3"

class TruenasFolderTest < Minitest::Test
  REPOSITORY = File.expand_path("../..", __dir__)

  def setup
    skip "Requires Linux root for deployment ownership checks" unless Process.uid.zero? && RUBY_PLATFORM.include?("linux")
    @dir = Dir.mktmpdir("relay-folder-")
    yaml = YAML.safe_load_file(File.join(REPOSITORY, "compose.truenas.folder.yml"), aliases: true)
    @code = yaml.fetch("services").fetch("init").fetch("command").first
      .sub('root = "/relay"', "root = #{@dir.inspect}")
      .gsub('"/rails/bin/update-relay.sh"', File.join(REPOSITORY, "bin/update-relay.sh").inspect)
      .sub('"/rails/compose.truenas.folder.yml"', File.join(REPOSITORY, "compose.truenas.folder.yml").inspect)
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir
  end

  def test_bootstrap_creates_private_configuration_and_installs_updater
    output, status = run_init
    assert status.success?, output
    assert_equal 5, File.readlines("#{@dir}/config/relay.env").length
    assert_equal 0600, File.stat("#{@dir}/config/relay.env").mode & 0777
    assert_equal 1000, File.stat("#{@dir}/config/relay.env").uid
    assert_equal 0700, File.stat(@dir).mode & 0777
    assert_equal 0, File.stat("#{@dir}/update-relay.sh").uid
    assert_equal 0700, File.stat("#{@dir}/update-relay.sh").mode & 0777
    assert_equal File.read("#{REPOSITORY}/bin/update-relay.sh"), File.read("#{@dir}/update-relay.sh")
    %w[postgres redis storage backups logs releases deployment .work].each do |name|
      assert Dir.exist?(File.join(@dir, name)), name
    end
    refute_includes output, File.read("#{@dir}/config/postgres-password")
  end

  def test_repeated_initialization_preserves_all_keys_and_data
    output, status = run_init
    assert status.success?, output
    secrets = File.binread("#{@dir}/config/relay.env")
    File.write("#{@dir}/storage/attachment", "preserved attachment")
    File.write("#{@dir}/postgres/PG_VERSION", "16")
    output, status = run_init
    assert status.success?, output
    assert_equal secrets, File.binread("#{@dir}/config/relay.env")
    assert_equal "preserved attachment", File.read("#{@dir}/storage/attachment")
  end

  def test_existing_database_without_keys_is_rejected
    FileUtils.mkdir_p("#{@dir}/postgres")
    File.write("#{@dir}/postgres/PG_VERSION", "16")
    output, status = run_init
    refute status.success?, output
    refute File.exist?("#{@dir}/config/relay.env")
    assert_equal "16", File.read("#{@dir}/postgres/PG_VERSION")
  end

  def test_incomplete_configuration_is_not_regenerated
    FileUtils.mkdir_p("#{@dir}/config")
    File.write("#{@dir}/config/relay.env", "POSTGRES_PASSWORD=incomplete\n")
    output, status = run_init
    refute status.success?, output
    assert_equal "POSTGRES_PASSWORD=incomplete\n", File.read("#{@dir}/config/relay.env")
  end

  def test_self_contained_bootstrap_installs_updater_without_new_image_files
    path = "#{@dir}/bootstrap-script"
    yaml = YAML.safe_load_file(File.join(REPOSITORY, "compose.truenas.folder.yml"), aliases: true)
    embedded = yaml.fetch("configs").fetch("relay-updater").fetch("content").gsub("$$", "$")
    assert_equal File.read("#{REPOSITORY}/bin/update-relay.sh"), embedded
    File.write(path, embedded)
    @code = @code.gsub(File.join(REPOSITORY, "bin/update-relay.sh").inspect, '"/missing/updater"')
      .sub('"/bootstrap/update-relay.sh"', path.inspect)
    output, status = run_init
    assert status.success?, output
    assert_equal embedded, File.read("#{@dir}/update-relay.sh")
  end

  private

    def run_init
      Open3.capture2e("ruby", "-e", @code)
    end
end
