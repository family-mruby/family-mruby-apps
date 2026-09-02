# Wide Only -- draws a ruler that only fits on a Modern-sized screen.

class WideOnlyApp < FmrbApp
  NEEDED_W = 400

  def on_create
    draw_screen
  end

  def draw_screen
    clear_user_area
    x = @user_area_x0 + 4
    y = @user_area_y0 + 4
    w = @user_area_x1 - @user_area_x0
    @gfx.draw_text(x, y, "user area is #{w} px wide", theme_fg)
    @gfx.draw_text(x, y + 12, "this app wants #{NEEDED_W}", theme_fg)

    # A tick every 50 px, so it is obvious where the screen ran out.
    ty = y + 30
    i = 0
    while i * 50 < NEEDED_W
      tx = x + i * 50
      @gfx.draw_line(tx, ty, tx, ty + 8, theme_fg)
      i += 1
    end
    @gfx.draw_line(x, ty, x + NEEDED_W, ty, theme_fg)

    draw_window_frame
    @gfx.present
  end

  def on_update
    200
  end
end

begin
  app = WideOnlyApp.new
  app.start
rescue => e
  puts "wide_only: #{e.message}"
end
