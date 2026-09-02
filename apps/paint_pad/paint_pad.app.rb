# Paint Pad -- drag to draw, right button to clear.
#
# The sample that carries every distribution key in a sidecar .app.toml.

class PaintPadApp < FmrbApp
  COLORS = [
    FmrbGfx::WHITE, FmrbGfx::RED, FmrbGfx::GREEN,
    FmrbGfx::BLUE, FmrbGfx::YELLOW
  ]
  SWATCH = 14

  def on_create
    @color = 0
    @drawing = false
    @last_x = 0
    @last_y = 0
    draw_screen
  end

  def draw_screen
    clear_user_area
    draw_palette
    draw_window_frame
    @gfx.present
  end

  def draw_palette
    x = @user_area_x0 + 2
    y = @user_area_y0 + 2
    i = 0
    while i < COLORS.size
      @gfx.fill_rect(x + i * (SWATCH + 2), y, SWATCH, SWATCH, COLORS[i])
      @gfx.draw_rect(x + i * (SWATCH + 2), y, SWATCH, SWATCH,
                     i == @color ? theme_fg : theme_border)
      i += 1
    end
  end

  def palette_hit(px, py)
    x = @user_area_x0 + 2
    y = @user_area_y0 + 2
    return nil if py < y || py >= y + SWATCH
    i = 0
    while i < COLORS.size
      sx = x + i * (SWATCH + 2)
      return i if px >= sx && px < sx + SWATCH
      i += 1
    end
    nil
  end

  def on_event(ev)
    super(ev)
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
        @gfx.draw_line(@last_x, @last_y, ev[:x], ev[:y], COLORS[@color])
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

begin
  app = PaintPadApp.new
  app.start
rescue => e
  puts "paint_pad: #{e.message}"
end
