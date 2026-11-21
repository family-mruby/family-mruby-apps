# Wide Only -- draws a ruler that only fits on a Modern-sized screen.
# The file only defines the class; the firmware starts it.

class WideOnlyApp < FmrbApp
  NEEDED_W = 400

  def on_create
    draw_screen
  end

  # Fullscreen: (0, 0) is the top left of the screen, and @user_area_width is
  # how wide it is.
  def draw_screen
    clear_user_area
    @gfx.draw_text(4, 4, "screen is #{@user_area_width} px wide", theme_fg)
    @gfx.draw_text(4, 16, "this app wants #{NEEDED_W}  (Esc to close)", theme_fg)

    # A tick every 50 px, so it is obvious where the screen ran out.
    ty = 34
    i = 0
    while i * 50 <= NEEDED_W
      tx = 4 + i * 50
      @gfx.draw_line(tx, ty, tx, ty + 8, theme_fg)
      @gfx.draw_text(tx + 2, ty + 10, (i * 50).to_s, theme_border)
      i += 1
    end
    @gfx.draw_line(4, ty, 4 + NEEDED_W, ty, theme_fg)
    @gfx.present
  end

  # A fullscreen app has no close button: Esc here, or Ctrl+Q anywhere.
  def on_event(ev)
    return unless ev[:type] == :key_down
    stop if ev[:scancode] == FmrbConst::KEY_ESC
  end

  def on_resize(_w, _h)
    draw_screen
  end

  def on_update
    200
  end
end
