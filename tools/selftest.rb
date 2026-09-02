# Prove the checks still bite.
#
# A validator that quietly stops catching things is worse than no validator:
# CI stays green and the bad app ships. So each check gets a specimen that is
# broken in exactly one way, and the run fails unless the expected complaint
# comes back.
#
# The specimens are made by copying apps/ into a temporary tree and damaging
# the copy, so nothing here can touch the real apps.

require "fileutils"
require "tmpdir"
require_relative "validate"

module Selftest
  # [name, what to do to the copied tree, a fragment of the expected message]
  CASES = [
    ["duplicate app_id", ->(d) {
      FileUtils.cp_r("#{d}/apps/paint_pad", "#{d}/apps/paint_pad2")
      FileUtils.mv("#{d}/apps/paint_pad2/paint_pad.app.toml", "#{d}/apps/paint_pad2/paint_pad2.app.toml")
      FileUtils.mv("#{d}/apps/paint_pad2/paint_pad.app.rb",   "#{d}/apps/paint_pad2/paint_pad2.app.rb")
      FileUtils.mv("#{d}/apps/paint_pad2/paint_pad.png",      "#{d}/apps/paint_pad2/paint_pad2.png")
    }, "is already used by"],

    ["missing required key", ->(d) {
      sub("#{d}/apps/paint_pad/paint_pad.app.toml", /^app_author = .*$/, "")
    }, "missing app_author"],

    ["no script file", ->(d) {
      FileUtils.rm("#{d}/apps/paint_pad/paint_pad.app.rb")
    }, "no paint_pad.app."],

    ["misspelt app_env", ->(d) {
      sub("#{d}/apps/paint_pad/paint_pad.app.toml", /^app_env = .*$/, 'app_env = ["retro", "moderrn"]')
    }, "app_env \"moderrn\" is not one of"],

    ["app_id not matching the directory", ->(d) {
      sub("#{d}/apps/paint_pad/paint_pad.app.toml", /^app_id = .*$/, 'app_id = "paintpad"')
    }, "does not match the directory name"],

    ["bad version", ->(d) {
      sub("#{d}/apps/paint_pad/paint_pad.app.toml", /^app_version = .*$/, 'app_version = "1.0"')
    }, "is not <n>.<n>.<n>"],

    ["unknown licence", ->(d) {
      sub("#{d}/apps/paint_pad/paint_pad.app.toml", /^app_license = .*$/, 'app_license = "MIT-ish"')
    }, "is not an SPDX identifier"],

    ["screen it cannot fit", ->(d) {
      sub("#{d}/apps/paint_pad/paint_pad.app.toml", /^app_min_width = .*$/, "app_min_width = 640")
    }, "does not fit retro"],

    ["stack outside the device's range", ->(d) {
      add("#{d}/apps/paint_pad/paint_pad.app.toml", "task_stack_kb = 128")
    }, "outside the device's 16..64 KB range"],

    ["app_files escaping the directory", ->(d) {
      add("#{d}/apps/paint_pad/paint_pad.app.toml", 'app_files = ["../../LICENSE"]')
    }, "escapes the app directory"],

    ["missing screenshot", ->(d) {
      FileUtils.rm("#{d}/apps/paint_pad/paint_pad.png")
    }, "is missing"],

    ["a capture of the whole desktop", ->(d) {
      FileUtils.cp("#{d}/apps/wide_only/wide_only.png",
                   "#{d}/apps/paint_pad/paint_pad.png")
    }, "exactly a screen"],

    ["a fullscreen app may fill the screen", ->(d) {
      # wide_only is default_window_mode = "fullscreen", so a picture the size
      # of the screen is the right one and must not be complained about.
    }, :no_error],

    ["a picture that size on purpose is allowed", ->(d) {
      FileUtils.cp("#{d}/apps/wide_only/wide_only.png",
                   "#{d}/apps/paint_pad/paint_pad.png")
      add("#{d}/apps/paint_pad/paint_pad.app.toml", "app_image_full_size = true")
    }, :no_error],

    ["regexp literal in the source", ->(d) {
      add("#{d}/apps/paint_pad/paint_pad.app.rb", 'PATTERN = /ab+c/')
    }, "Regexp does not exist"],

    ["=~ in the source", ->(d) {
      add("#{d}/apps/paint_pad/paint_pad.app.rb", 'HIT = ("a" =~ B)')
    }, "Regexp does not exist"],

    ["division is not mistaken for a regexp", ->(d) {
      add("#{d}/apps/paint_pad/paint_pad.app.rb", "MID = (100 - 4) / 2\nSTEP = 640 / 16")
    }, :no_error],

    ["defined? in the source", ->(d) {
      add("#{d}/apps/paint_pad/paint_pad.app.rb", 'X = defined?(Foo)')
    }, "defined? does not exist"],

    ["no .start call", ->(d) {
      sub("#{d}/apps/paint_pad/paint_pad.app.rb", /^\s*app\.start$/, "")
    }, "no .start call"],

    ["no sidecar manifest", ->(d) {
      FileUtils.rm("#{d}/apps/hello_store/hello_store.app.toml")
    }, "needs a sidecar manifest"],

    ["keys duplicated into a comment fence", ->(d) {
      path = "#{d}/apps/hello_store/hello_store.app.rb"
      File.write(path, "#---fmrb\n# app_id = \"hello_store\"\n#---\n" + File.read(path))
    }, "keep the keys in the .app.toml only"],

    ["a table in the manifest", ->(d) {
      add("#{d}/apps/paint_pad/paint_pad.app.toml", "[extra]\nkey = 1")
    }, "tables are not supported"],
  ].freeze

  def self.sub(path, re, repl)
    File.write(path, File.read(path).sub(re, repl))
  end

  def self.add(path, line)
    File.write(path, "#{File.read(path)}\n#{line}\n")
  end

  def self.run(root)
    failures = []

    clean = Validate.run(root)
    failures << "the tree as committed does not pass: #{clean.join('; ')}" unless clean.empty?

    CASES.each do |name, damage, expected|
      Dir.mktmpdir("fmrb-selftest") do |dir|
        FileUtils.cp_r("#{root}/apps", dir)
        damage.call(dir)
        errors = Validate.run(dir)
        if expected == :no_error
          # The other direction: this specimen must stay clean. A check that
          # fires on ordinary code is as bad as one that never fires.
          failures << "#{name}: expected no complaint, got #{errors.inspect}" unless errors.empty?
        elsif errors.none? { |e| e.include?(expected) }
          failures << "#{name}: expected a complaint containing #{expected.inspect}, got " +
                      (errors.empty? ? "nothing" : errors.inspect)
        end
      end
    end

    failures
  end
end
