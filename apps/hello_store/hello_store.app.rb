# Hello Store -- the smallest app the store can carry.
#
# The manifest is the .app.toml next to this file, and it has to be: an app
# whose keys live only in a fenced comment here is runnable by path but never
# appears in the launcher, because the launcher walks .toml files and never
# opens a .rb looking for a fence (measured 2026-09-02, report/p1b.md).
#
# No window, memory or stack keys anywhere, so this also checks that an app
# arriving from the store still gets the defaults.

class HelloStoreApp < FmrbApp
  def on_create
    @n = 0
    draw_screen
  end

  def draw_screen
    clear_user_area
    x = @user_area_x0 + 6
    y = @user_area_y0 + 6
    # The default window is 100x100 and the font is 6 px wide, so about 15
    # characters fit on a line. An app that wants more has to ask for it in
    # its .app.toml; this one is here to show what the defaults give you.
    @gfx.draw_text(x, y, "Hello!", theme_fg)
    @gfx.draw_text(x, y + 14, "clicks: #{@n}", theme_fg)
    @gfx.draw_text(x, y + 32, "Click me.", theme_fg)
    draw_window_frame
    @gfx.present
  end

  def on_event(ev)
    super(ev)
    return unless ev[:type] == :mouse_up && ev[:button] == 1
    @n += 1
    draw_screen
  end

  def on_update
    100
  end
end

begin
  app = HelloStoreApp.new
  app.start
rescue => e
  puts "hello_store: #{e.message}"
end
