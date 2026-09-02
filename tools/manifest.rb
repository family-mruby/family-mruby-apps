# Reading an app's manifest.
#
# The manifest is the .app.toml the device itself reads, plus the distribution
# keys (spec.md 3.2). A one-file app carries the same keys in a fenced comment
# block at the top of the .rb instead, which is what the device's spawner does
# (fmruby-core main/app/fmrb_app_spawner.c, "Comment-embedded toml").
#
# Only the subset of TOML the device's own readers use is supported: flat
# `key = value` lines with strings, integers, booleans and single-line arrays
# of strings. Tables and multi-line values are deliberately not supported --
# the device's Ruby-side reader (launcher.rb parse_app_toml) is a line loop
# and cannot see them either, so accepting them here would let an author write
# something that works in CI and not on the machine.

module Manifest
  # The device reads only the first 512 bytes of a .rb looking for the fence,
  # and the fence must come before the first non-comment line.
  INLINE_SCAN_BYTES = 512
  FENCE_OPEN  = "#---fmrb"
  FENCE_CLOSE = "#---"

  SCRIPT_EXTS = %w[rb lua bas py].freeze

  class Error < StandardError; end

  # Every app directory holds exactly one app. Returns a Hash of the manifest
  # keys plus :dir, :id_from_path, :toml_path (nil when inline), :script_path.
  def self.load(dir)
    base = File.basename(dir)
    toml = File.join(dir, "#{base}.app.toml")
    script = SCRIPT_EXTS.map { |e| File.join(dir, "#{base}.app.#{e}") }.find { |p| File.file?(p) }

    unless File.file?(toml)
      # The device does support a manifest in a fenced comment at the top of
      # the .rb, and that is fine for a script you launch yourself. It is not
      # enough for an app someone installs: the launcher's scan walks .toml
      # files and never opens a .rb looking for a fence, so an app without a
      # sidecar installs and is then invisible. The spawner refuses to take
      # launcher metadata from a comment for the same reason (it says so:
      # "launcher metadata needs a .toml sidecar"). Measured 2026-09-02.
      raise Error, "#{dir}: no #{base}.app.toml -- a distributed app needs a " \
                   "sidecar manifest, or it never shows up in the launcher"
    end
    keys = parse(File.read(toml), toml)
    toml_path = toml

    keys.merge(dir: dir, id_from_path: base, toml_path: toml_path, script_path: script)
  end

  # The fenced comment block at the top of a .rb, with the leading "# "
  # stripped, exactly as the device assembles it before handing it to its TOML
  # parser. Raises when the fence is not there or does not close.
  def self.inline_body(path)
    # Read as bytes so the 512-byte window is the same one the device sees
    # (it counts bytes, not characters), then hand the text back as UTF-8 --
    # a Japanese app_screen_name_ja would otherwise travel as BINARY and blow
    # up in JSON.generate.
    head = File.open(path, "rb") { |f| f.read(INLINE_SCAN_BYTES) } || ""
    head = head.force_encoding(Encoding::UTF_8)
    lines = head.split("\n")
    open_at = nil
    lines.each_with_index do |line, i|
      stripped = line.strip
      if stripped.start_with?(FENCE_OPEN)
        open_at = i
        break
      end
      # The device stops looking at the first line that is not a comment.
      break unless stripped.empty? || stripped.start_with?("#")
    end
    raise Error, "#{path}: no #{FENCE_OPEN} fence in the first #{INLINE_SCAN_BYTES} bytes" unless open_at

    body = []
    closed = false
    lines[(open_at + 1)..].to_a.each do |line|
      stripped = line.strip
      if stripped == FENCE_CLOSE
        closed = true
        break
      end
      raise Error, "#{path}: line inside the fence is not a comment: #{line}" unless stripped.start_with?("#")
      body << stripped.sub(/\A#\s?/, "")
    end
    unless closed
      raise Error, "#{path}: the #{FENCE_OPEN} fence does not close within " \
                   "the first #{INLINE_SCAN_BYTES} bytes"
    end
    body.join("\n")
  end

  # The subset of TOML described at the top of this file.
  def self.parse(text, where)
    out = {}
    text.split("\n").each_with_index do |line, i|
      s = line.strip
      next if s.empty? || s.start_with?("#")
      if s.start_with?("[")
        raise Error, "#{where}:#{i + 1}: tables are not supported (the device's " \
                     "launcher reads .app.toml line by line and cannot see them)"
      end
      eq = s.index("=")
      raise Error, "#{where}:#{i + 1}: not a key = value line: #{s}" unless eq
      key = s[0, eq].strip
      out[key] = value(s[(eq + 1)..].strip, where, i + 1)
    end
    out
  end

  def self.value(raw, where, lineno)
    # Strip a trailing comment only when it cannot be inside a string.
    raw = raw.sub(/\s+#.*\z/, "") unless raw.start_with?('"')
    case raw
    when /\A"(.*)"\z/       then Regexp.last_match(1)
    when /\A-?\d+\z/        then raw.to_i
    when "true"             then true
    when "false"            then false
    when /\A\[(.*)\]\z/
      inner = Regexp.last_match(1).strip
      return [] if inner.empty?
      inner.split(",").map do |e|
        e = e.strip
        unless e =~ /\A"(.*)"\z/
          raise Error, "#{where}:#{lineno}: array elements must be quoted strings: #{e}"
        end
        Regexp.last_match(1)
      end
    else
      raise Error, "#{where}:#{lineno}: unsupported value: #{raw}"
    end
  end
end
