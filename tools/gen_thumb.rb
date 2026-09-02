# Turn the author's screenshot PNG into the small one the store shows beside
# each app in its list (spec.md 10.2).
#
# PNG, not BMP. The display side decodes PNG for create_image/draw_image,
# which is how an app draws a picture into its own window; BMP is the sprite
# path and belongs to the launcher's icons. Both the boards and the browser
# build compile the same display code, so one file serves all three.
#
# 32x24 rather than something roomier because a taller row is a shorter list:
# on Retro the store has about 110 px of list, which is four rows with
# pictures and eight without.

require "zlib"
require_relative "fmrb_png"

module GenThumb
  W = 32
  H = 24
  # What the letterbox is filled with when the aspect ratios disagree.
  PAD = [0x18, 0x18, 0x1c].freeze

  def self.generate(png_path, out_path)
    sw, sh, rows = FmrbPng.read_rgb(png_path)
    write_png(out_path, fit(sw, sh, rows))
    [W, H]
  end

  # Scale the whole screenshot down to fit inside WxH without distorting it,
  # and pad what is left over with the transparent colour. Screenshots arrive
  # at two aspect ratios (Retro is 4:3, Modern and the browser are 16:9) and a
  # list of stretched pictures looks wrong next to a list of unstretched ones.
  def self.fit(sw, sh, rows)
    scale = [W.to_f / sw, H.to_f / sh].min
    dw = [(sw * scale).round, 1].max
    dh = [(sh * scale).round, 1].max
    ox = (W - dw) / 2
    oy = (H - dh) / 2

    out = Array.new(H) { Array.new(W) { PAD.dup } }
    dh.times do |y|
      # Box filter: average the source pixels this destination pixel covers.
      # Nearest-neighbour on a 426x240 shot drops most of the image and turns
      # text into noise.
      y0 = (y * sh) / dh
      y1 = [(((y + 1) * sh) / dh), y0 + 1].max
      dw.times do |x|
        x0 = (x * sw) / dw
        x1 = [(((x + 1) * sw) / dw), x0 + 1].max
        r = g = b = n = 0
        (y0...y1).each do |sy|
          row = rows[sy]
          (x0...x1).each do |sx|
            o = sx * 3
            r += row.getbyte(o)
            g += row.getbyte(o + 1)
            b += row.getbyte(o + 2)
            n += 1
          end
        end
        out[oy + y][ox + x] = [r / n, g / n, b / n]
      end
    end
    out
  end

  # A PNG is a signature and three chunks; the pixels are one filter byte per
  # row followed by RGB triples, deflated in one go. No colour reduction: the
  # display decodes this and the picture is 32x24, so there is nothing to save
  # by quantising it.
  def self.write_png(path, pixels)
    h = pixels.size
    w = pixels[0].size
    raw = pixels.map { |row| "\0".b + row.flatten.pack("C*") }.join
    ihdr = [w, h].pack("NN") + [8, 2, 0, 0, 0].pack("C5")
    File.binwrite(path, PNG_SIGNATURE + chunk("IHDR", ihdr) +
                        chunk("IDAT", Zlib::Deflate.deflate(raw)) + chunk("IEND", ""))
  end

  PNG_SIGNATURE = "\x89PNG\r\n\x1a\n".b

  def self.chunk(type, data)
    [data.bytesize].pack("N") + type + data + [Zlib.crc32(type + data)].pack("N")
  end
end
