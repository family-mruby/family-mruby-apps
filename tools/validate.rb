# Checks every app in apps/ before it can go into the registry (spec.md 5.1).
#
# What is checked here is what the device cannot tell an author afterwards: a
# missing key means an app that installs and then behaves oddly, and a Regexp
# literal means an app that runs in a host test and dies on the machine.

require_relative "manifest"

module Validate
  REQUIRED = %w[app_id app_version app_author app_description app_category app_env].freeze

  CATEGORIES = %w[game tool education demo media presentation iot robotics development other].freeze
  ENVS       = %w[retro modern web].freeze

  # The screen each environment actually gives an app. Physical output is
  # larger on Modern (the panel is 1280x720) but the framebuffer is not.
  ENV_SCREEN = { "retro" => [320, 240], "modern" => [426, 240], "web" => [426, 240] }.freeze

  # https://spdx.org/licenses/ -- the handful a hobby app repository will see.
  # Add to this list rather than dropping the check.
  SPDX = %w[
    MIT Apache-2.0 BSD-2-Clause BSD-3-Clause ISC Zlib Unlicense CC0-1.0
    GPL-2.0-only GPL-2.0-or-later GPL-3.0-only GPL-3.0-or-later
    LGPL-2.1-only LGPL-2.1-or-later LGPL-3.0-only LGPL-3.0-or-later
    MPL-2.0 AGPL-3.0-only AGPL-3.0-or-later
  ].freeze

  # Things that pass a host Ruby and fail on picoruby. The device has no
  # Regexp at all, no defined?, no Array#pack and no File.binread.
  RUBY_TRAPS = [
    [/(?<![\w.])defined\?/,        "defined? does not exist in picoruby (use const_defined? or rescue)"],
    [/\.pack\s*\(/,                "Array#pack does not exist in picoruby (build bytes with setbyte)"],
    [/File\.binread/,              "File.binread does not exist in picoruby (File.open(path, \"r\") { |f| f.read })"],
    [/=~|!~/,                      "Regexp does not exist in picoruby"],
    [/(?<![\w.])Regexp(?![\w])/,   "Regexp does not exist in picoruby"],
    # A regexp literal. The slash is also division, so only count one that
    # sits where a value is expected (after =, (, [, comma, when, return) --
    # `(w - dw) / 2` and `x / 16` follow an identifier or a bracket and are
    # left alone.
    [%r{(?:^|[=(\[,|&!]|\bwhen\b|\breturn\b)\s*/(?![\s=/])(?:[^/\\\n]|\\.)+/[imxo]*},
     "Regexp does not exist in picoruby"],
    [/\.(?:match\??|scan)\s*\(/,   "String#match / #scan need Regexp, which picoruby does not have"],
  ].freeze

  def self.run(root)
    errors = []
    seen = {}

    dirs = Dir.children(File.join(root, "apps")).sort.map { |d| File.join(root, "apps", d) }
    dirs.select! { |d| File.directory?(d) }
    errors << "apps/ has no app directories" if dirs.empty?

    dirs.each do |dir|
      rel = dir.sub("#{root}/", "")
      begin
        m = Manifest.load(dir)
      rescue Manifest::Error => e
        errors << e.message.sub("#{root}/", "")
        next
      end
      errors.concat(check(m, rel, seen, root))
    end

    errors
  end

  def self.check(m, rel, seen, root)
    e = []
    id = m["app_id"]

    REQUIRED.each { |k| e << "#{rel}: missing #{k}" unless m[k] }
    return e unless id

    e << "#{rel}: app_id #{id.inspect} does not match the directory name" if id != m[:id_from_path]
    e << "#{rel}: app_id must be [a-z0-9_], 1..31 chars" unless id =~ /\A[a-z0-9_]{1,31}\z/
    if seen[id]
      e << "#{rel}: app_id #{id.inspect} is already used by #{seen[id]}"
    else
      seen[id] = rel
    end

    v = m["app_version"]
    e << "#{rel}: app_version #{v.inspect} is not <n>.<n>.<n>" if v && v !~ /\A\d+\.\d+\.\d+\z/

    c = m["app_category"]
    e << "#{rel}: app_category #{c.inspect} is not one of #{CATEGORIES.join(' ')}" if c && !CATEGORIES.include?(c)

    envs = m["app_env"]
    if envs
      unless envs.is_a?(Array) && !envs.empty?
        e << "#{rel}: app_env must be a non-empty array"
        envs = nil
      else
        envs.each { |x| e << "#{rel}: app_env #{x.inspect} is not one of #{ENVS.join(' ')}" unless ENVS.include?(x) }
      end
    end

    lic = m["app_license"]
    e << "#{rel}: app_license #{lic.inspect} is not an SPDX identifier we know" if lic && !SPDX.include?(lic)

    e.concat(check_screen(m, rel, envs))
    e.concat(check_heap(m, rel))
    e.concat(check_files(m, rel, root))
    e.concat(check_script(m, rel))
    e
  end

  # An app that asks for more room than an environment has cannot run there,
  # so listing that environment is a contradiction the author should see now.
  def self.check_screen(m, rel, envs)
    e = []
    w = m["app_min_width"]
    h = m["app_min_height"]
    return e unless (w || h) && envs
    envs.each do |env|
      sw, sh = ENV_SCREEN[env]
      next unless sw
      e << "#{rel}: app_min_width #{w} does not fit #{env} (#{sw}x#{sh})"  if w && w > sw
      e << "#{rel}: app_min_height #{h} does not fit #{env} (#{sw}x#{sh})" if h && h > sh
    end
    e
  end

  def self.check_heap(m, rel)
    e = []
    %w[required_heap_kb_esp32 required_heap_kb_linux].each do |k|
      v = m[k]
      next unless v
      e << "#{rel}: #{k} must be a positive integer (KB)" unless v.is_a?(Integer) && v > 0
    end
    k = m["task_stack_kb"]
    e << "#{rel}: task_stack_kb #{k} is outside the device's 16..64 KB range" if k && !(16..64).cover?(k)
    e
  end

  def self.check_files(m, rel, root)
    e = []
    e << "#{rel}: no #{m[:id_from_path]}.app.<rb|lua|bas|py> next to the manifest" unless m[:script_path]

    listed = m["app_files"]
    if listed
      unless listed.is_a?(Array)
        e << "#{rel}: app_files must be an array"
        listed = []
      end
      listed.each do |f|
        # The installer writes these under /app/usr/<id>/ and nowhere else.
        if f.start_with?("/") || f.split("/").include?("..")
          e << "#{rel}: app_files #{f.inspect} escapes the app directory"
          next
        end
        e << "#{rel}: app_files #{f.inspect} does not exist" unless File.file?(File.join(m[:dir], f))
      end
    end

    img = m["app_image"] || "#{m[:id_from_path]}.png"
    path = File.join(m[:dir], img)
    unless File.file?(path)
      e << "#{rel}: #{img} is missing (every app needs a picture, spec.md 10.2)"
      return e
    end
    unless File.binread(path, 8) == "\x89PNG\r\n\x1a\n".b
      e << "#{rel}: #{img} is not a PNG"
      return e
    end
    # A picture the exact size of a screen is usually a capture of the whole
    # desktop with the app somewhere in it, which shrinks to a picture of the
    # wallpaper. It is only usually, though: an app that runs fullscreen, or
    # artwork that happens to be that size, are both fine and say so.
    w, h = png_size(path)
    if w && FULL_SCREENS.include?([w, h]) &&
       m["default_window_mode"] != "fullscreen" && m["app_image_full_size"] != true
      e << "#{rel}: #{img} is #{w}x#{h}, exactly a screen. If it is a capture, " \
           "crop it to the app's own window; if you meant it, say " \
           "app_image_full_size = true"
    end
    e
  end

  # The screens something can be captured on.
  FULL_SCREENS = [[320, 240], [426, 240], [640, 360], [852, 480]].freeze

  # Straight out of the IHDR; there is no need to decode the image to learn
  # how big it is.
  def self.png_size(path)
    head = File.binread(path, 24)
    return [nil, nil] unless head && head.bytesize == 24
    head[16, 8].unpack("NN")
  end

  def self.check_script(m, rel)
    e = []
    path = m[:script_path]
    return e unless path && path.end_with?(".rb")
    src = File.read(path)
    if src.byteslice(0, Manifest::INLINE_SCAN_BYTES).to_s.include?(Manifest::FENCE_OPEN)
      e << "#{rel}: #{File.basename(path)} carries a #{Manifest::FENCE_OPEN} block. " \
           "The sidecar wins, so the two can disagree without anyone noticing -- " \
           "keep the keys in the .app.toml only"
    end
    # Comments are where the traps get talked about rather than used.
    code = src.split("\n").reject { |l| l.strip.start_with?("#") }.join("\n")
    RUBY_TRAPS.each do |re, why|
      next unless code =~ re
      e << "#{rel}: #{File.basename(path)}: #{why}"
    end
    unless code =~ /\.start\b/
      e << "#{rel}: #{File.basename(path)}: no .start call -- an app that is " \
           "never started does nothing when it is launched"
    end
    e
  end
end
