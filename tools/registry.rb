# Build registry.json from what is in apps/ (spec.md 5).
#
# The registry is a generated file. It is committed so that the store can pull
# it straight from raw.githubusercontent.com without an API call, but nobody
# edits it: CI regenerates it and fails if the result differs from what is in
# the tree.

require "digest"
require "json"
require_relative "manifest"
require_relative "gen_thumb"

module Registry
  FORMAT_VERSION = 1

  def self.build(root, generate_thumbs: true)
    apps = Dir.children(File.join(root, "apps")).sort.filter_map do |name|
      dir = File.join(root, "apps", name)
      next unless File.directory?(dir)
      entry(Manifest.load(dir), root, generate_thumbs)
    end
    { "format_version" => FORMAT_VERSION, "apps" => apps }
  end

  def self.entry(m, root, generate_thumbs)
    id  = m["app_id"]
    dir = m[:dir]
    base = "apps/#{id}/"

    img = m["app_image"] || "#{id}.png"
    thumb = "#{id}.thumb.png"
    GenThumb.generate(File.join(dir, img), File.join(dir, thumb)) if generate_thumbs

    # Files the installer writes to the device. The manifest and the script
    # always; anything else only when the author listed it. The picture and
    # the thumbnail are NOT here -- the store shows them, it does not install
    # them.
    names = []
    names << File.basename(m[:toml_path]) if m[:toml_path]
    names << File.basename(m[:script_path])
    names.concat(Array(m["app_files"]))
    names.uniq!

    e = {}
    e["id"]      = id
    e["version"] = m["app_version"]
    e["name"]    = m["app_screen_name"] || id
    e["name_ja"] = m["app_screen_name_ja"] if m["app_screen_name_ja"]
    e["description"]    = m["app_description"]
    e["description_ja"] = m["app_description_ja"] if m["app_description_ja"]
    e["category"] = m["app_category"]
    e["author"]   = m["app_author"]
    e["license"]  = m["app_license"] if m["app_license"]
    e["source"]   = m["app_source"] if m["app_source"]
    e["env"]      = m["app_env"]
    e["min_width"]  = m["app_min_width"]  if m["app_min_width"]
    e["min_height"] = m["app_min_height"] if m["app_min_height"]

    heap = {}
    heap["esp32"] = m["required_heap_kb_esp32"] if m["required_heap_kb_esp32"]
    heap["linux"] = m["required_heap_kb_linux"] if m["required_heap_kb_linux"]
    e["required_heap_kb"] = heap unless heap.empty?

    e["base"] = base
    # One digest for the whole app rather than one per file. The machine then
    # keeps a single digest object and makes a single comparison however many
    # files an app grows to, and the list does not swell with them. Knowing
    # WHICH file differs would not help: a mismatch throws the install away
    # whole.
    e["sha256"] = app_digest(dir, names)
    e["image"] = file_entry(dir, img)
    e["thumb"]      = file_entry(dir, thumb)
    e["files"]      = names.map { |n| file_entry(dir, n) }
    e
  end

  # Paths in the order the list gives them, each framed by its own name and
  # length before its bytes. Concatenating contents alone would let two
  # different splits of the same stream hash alike; the framing removes that
  # and costs a few bytes per file.
  #
  # The machine has to be able to reproduce this with MbedTLS::Digest, so
  # keep it to update() calls in a fixed order and nothing cleverer.
  def self.app_digest(dir, names)
    d = Digest::SHA256.new
    names.each do |name|
      body = File.binread(File.join(dir, name))
      d << name
      d << "\n"
      d << body.bytesize.to_s
      d << "\n"
      d << body
    end
    d.hexdigest
  end

  # Files carry their size but not their own digest: the size is what makes a
  # truncated transfer visible before anything is hashed, and it is what a
  # progress display has to work with.
  def self.file_entry(dir, name)
    { "path" => name, "size" => File.size(File.join(dir, name)) }
  end

  # Stable output: JSON.pretty_generate keeps insertion order, and every hash
  # above is built in a fixed order, so regenerating an unchanged tree gives a
  # byte-identical file. That is what lets CI diff it.
  def self.render(data)
    JSON.pretty_generate(data) + "\n"
  end

  # The same list as tab-separated lines, which is what the store on a device
  # actually reads.
  #
  # JSON is not usable there: picoruby's parser took 7.6 SECONDS over this
  # list's 2858 bytes on an ESP32-P4 (measured 2026-09-02), which is most of
  # what "the store is slow to load" was. Lines cost a split and nothing else.
  # The same trade was made for the RPG map, where a JSON file that took 39.5 s
  # became 55 ms as a packed format.
  #
  # Both files come out of the same data here, so they cannot drift, and the
  # JSON stays for people and for tools.
  #
  #   1 <TAB> format version
  #   A <TAB> id ... thumb_size      one per app, fields in a fixed order
  #   F <TAB> path <TAB> size        the files of the app above it, in order
  #
  # A reader skips a line whose first field it does not know, so a later
  # version can add line types without breaking an older store.
  TSV_VERSION = 1

  APP_FIELDS = %w[
    id version name name_ja description description_ja category author
    env min_width min_height heap_esp32 heap_linux sha256 base
    thumb_path thumb_size
  ].freeze

  def self.render_tsv(data)
    out = "#{TSV_VERSION}\n"
    data["apps"].each do |a|
      heap = a["required_heap_kb"] || {}
      thumb = a["thumb"] || {}
      row = [
        a["id"], a["version"], a["name"], a["name_ja"],
        a["description"], a["description_ja"], a["category"], a["author"],
        (a["env"] || []).join(","),
        a["min_width"], a["min_height"], heap["esp32"], heap["linux"],
        a["sha256"], a["base"], thumb["path"], thumb["size"],
      ]
      out << "A\t" << row.map { |v| field(v) }.join("\t") << "\n"
      (a["files"] || []).each do |f|
        out << "F\t" << field(f["path"]) << "\t" << field(f["size"]) << "\n"
      end
    end
    out
  end

  # A tab or a newline in a value would split the record where it should not,
  # so validate refuses them and this only has to turn nil into nothing.
  def self.field(v)
    v.nil? ? "" : v.to_s
  end
end
