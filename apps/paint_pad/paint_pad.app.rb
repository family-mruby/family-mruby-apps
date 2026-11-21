# Paint Pad -- drag to draw, right button to clear.
#
# The sample that carries every distribution key in a sidecar .app.toml.
# The file only defines the class; the firmware starts it.

class PaintPadApp < FmrbApp
  # The inks after the first, as RGB332 values written out (a table in the
  # class body is read before the app runs). The first ink is the theme's
  # text colour, so it shows on a light paper and a dark one alike.
  #           red   green blue  orange
  COLORS = [nil, 0xE0, 0x14, 0x03, 0xE8]
  SWATCH = 14

  def on_create
    @color = 0
    @drawing = false
    @last_x = 0
    @last_y = 0
    draw_screen
  end

  # Coordinates, here and in the mouse events, are relative to the area
  # inside the frame; the frame is redrawn by the firmware.
  def draw_screen
    clear_user_area
    draw_palette
    @gfx.present
  end

  def draw_palette
    i = 0
    while i < COLORS.size
      x = 2 + i * (SWATCH + 2)
      # the chosen ink gets a bar under it; the others have the paper there
      @gfx.fill_rect(x, 2, SWATCH, SWATCH, ink(i))
      @gfx.fill_rect(x, 3 + SWATCH, SWATCH, 2, i == @color ? theme_fg : theme_bg)
      i += 1
    end
  end

  def ink(i)
    COLORS[i] || theme_fg
  end

  def palette_hit(px, py)
    return nil if py < 2 || py >= 2 + SWATCH
    i = 0
    while i < COLORS.size
      sx = 2 + i * (SWATCH + 2)
      return i if px >= sx && px < sx + SWATCH
      i += 1
    end
    nil
  end

  def on_event(ev)
    case ev[:type]
    when :mouse_down
      if ev[:button] == 3
        draw_screen
      elsif ev[:button] == 1
        hit = palette_hit(ev[:x], ev[:y])
        if hit
          @color = hit
          draw_palette
          @gfx.present
        else
          @drawing = true
          @last_x = ev[:x]
          @last_y = ev[:y]
        end
      end
    when :mouse_move
      if @drawing
        @gfx.draw_line(@last_x, @last_y, ev[:x], ev[:y], ink(@color))
        @last_x = ev[:x]
        @last_y = ev[:y]
        @gfx.present
      end
    when :mouse_up
      @drawing = false if ev[:button] == 1
    end
  end

  def on_update
    50
  end
end
