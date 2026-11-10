require "fileutils"
require "minitest/autorun"
require "open3"
require "tmpdir"
require "yaml"

class CheckActionPinsTest < Minitest::Test
  SHA = "a" * 40
  DIGEST = "b" * 64
  WORKFLOW = File.expand_path("../workflows/check-action-pins.yml", __dir__)
  CHECKER = YAML.safe_load(File.read(WORKFLOW))["jobs"]["check"]["steps"].find { |step| step["shell"] == "ruby {0}" }.fetch("run")

  def setup
    @directory = Dir.mktmpdir
    system("git", "init", "--quiet", @directory, exception: true)
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_accepts_full_shas_local_actions_and_container_digests
    write ".github/workflows/ci.yml", <<~YAML
      jobs:
        reusable:
          uses: owner/repo/.github/workflows/ci.yml@#{SHA}
        build:
          steps:
            - uses: owner/action@#{SHA} # v1
            - uses: ./local-action
            - uses: docker://alpine@sha256:#{DIGEST}
            - run: |
                uses: owner/example@v1
      # uses: owner/comment@main
    YAML
    write "local-action/action.yaml", <<~YAML
      runs:
        using: composite
        steps:
          - uses: owner/action@#{SHA}
    YAML
    assert_check true
  end

  def test_rejects_tags_branches_short_shas_and_container_tags
    ["v1", "main", "a" * 39, "a" * 41].each do |ref|
      write ".github/workflows/ci.yml", "jobs: {build: {steps: [{uses: 'owner/action@#{ref}'}]}}\n"
      assert_check false, "owner/action@#{ref}"
    end
    write ".github/workflows/ci.yml", "jobs: {build: {steps: [{uses: 'docker://alpine:3.20'}]}}\n"
    assert_check false, "docker://alpine:3.20"
  end

  def test_checks_multiline_aliased_and_merged_references
    write ".github/workflows/ci.yml", <<~YAML
      jobs:
        build:
          steps:
            - uses: >-
                owner/action@v1
            - &action
              uses: owner/other@main
            - *action
            - <<: *action
    YAML
    assert_check false, "owner/action@v1", "owner/other@main"
  end

  def test_checks_nested_composite_actions
    write "tools/local/action.yml", "runs: {using: composite, steps: [{uses: 'owner/action@v1'}]}\n"
    assert_check false, "tools/local/action.yml"
  end

  def test_rejects_invalid_yaml
    write ".github/workflows/ci.yml", "jobs: [\n"
    assert_check false, "invalid YAML"
  end

  def test_rejects_symlinked_action_files
    write "actual.yml", "runs: {using: composite, steps: [{uses: 'owner/action@v1'}]}\n"
    FileUtils.mkdir_p File.join(@directory, ".github/actions/local")
    File.symlink "../../../actual.yml", File.join(@directory, ".github/actions/local/action.yml")
    assert_check false, "must not be symlinks"
  end

  private
    def write(path, content)
      file = File.join(@directory, path)
      FileUtils.mkdir_p File.dirname(file)
      File.write(file, content)
    end

    def assert_check(success, *messages)
      system("git", "-C", @directory, "add", ".", exception: true)
      output, status = Open3.capture2e(RbConfig.ruby, "-e", CHECKER, chdir: @directory)
      assert_equal success, status.success?, output
      messages.each { |message| assert_includes output, message }
    end
end
