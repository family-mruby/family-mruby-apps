# Turn the author's screenshot PNG into the small BMP the device's store shows
# in its list (spec.md 10.2).
#
# The device cannot decode PNG, and the graphics side decodes BMP for us
# (SpriteImage#load_bmp). The BMP is 8-bit and its pixel bytes are RGB332
# values, NOT palette indices -- the device's loader ignores the palette and
# takes the byte as the colour. The palette is written anyway so the file also
# opens in an ordinary image viewer. This is the same arrangement as the
# launcher icons; the writer below follows fmruby-core tool/gen_icon_bmp.rb.
#
# 32x24 rather than something roomier because the device pays twice for a
# bigger one: a Retro list row grows from 8 px to 26 px (16 visible rows down
# to 6), and every sprite costs about 160 ms to hand to the graphics side.

require_relative "fmrb_png"

module GenThumb
  W = 32
  H = 24
  TRANSPARENT = 0  # matches SpriteImage transparent_color: 0 in the launcher

  def self.generate(png_path, bmp_path)
    sw, sh, rows = FmrbPng.read_rgb(png_path)
    pixels = fit(sw, sh, rows)
    write_bmp(bmp_path, pixels)
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

    out = Array.new(H) { Array.new(W, TRANSPARENT) }
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
        out[oy + y][ox + x] = rgb332(r / n, g / n, b / n)
      end
    end
    out
  end

  # RRRGGGBB. 0 is the transparent key, so a genuinely black pixel is nudged
  # to the darkest non-zero colour rather than punching a hole in the picture.
  def self.rgb332(r, g, b)
    v = ((r >> 5) << 5) | ((g >> 5) << 2) | (b >> 6)
    v == TRANSPARENT ? 0x01 : v
  end

  def self.palette_entry(v)
    r = ((v >> 5) & 0x07) * 255 / 7
    g = ((v >> 2) & 0x07) * 255 / 7
    b = (v & 0x03) * 255 / 3
    [b, g, r, 0].pack("C4")  # BMP palette entries are BGRA
  end

  def self.write_bmp(path, pixels)
    height = pixels.size
    width  = pixels[0].size
    pad = (4 - (width % 4)) % 4
    palette = (0..255).map { |v| palette_entry(v) }.join
    pixel_offset = 14 + 40 + palette.bytesize
    # BMP scanlines run bottom-up.
    body = (height - 1).downto(0).map { |y| pixels[y].pack("C*") + ("\0" * pad) }.join
    header = "BM".b + [pixel_offset + body.bytesize, 0, pixel_offset].pack("VVV")
    dib = [40, width, height].pack("Vll") +
          [1, 8].pack("vv") +
          [0, body.bytesize, 2835, 2835, 256, 0].pack("V6")
    File.binwrite(path, header + dib + palette + body)
  end
end
