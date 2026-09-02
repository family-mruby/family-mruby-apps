#---fmrb
# app_screen_name = "Hello Store"
# app_screen_name_ja = "こんにちは"
# app_id = "hello_store"
# app_version = "1.0.0"
# app_author = "family-mruby"
# app_category = "demo"
# app_env = ["retro", "modern", "web"]
# app_description = "The smallest app the store can carry"
#---
#
# One file, no sidecar .app.toml: the keys above ride in the fenced comment
# block the spawner reads. Everything else (window size, memory, stack) is
# left out on purpose -- this app is here to prove the defaults still apply
# to an app that arrived from the store.

class HelloStoreApp < FmrbApp
  def on_create
    @n = 0
    draw_screen
  end

  def draw_screen
    clear_user_area
    x = @user_area_x0 + 6
    y = @user_area_y0 + 6
    @gfx.draw_text(x, y, "Hello from the store", theme_fg)
    @gfx.draw_text(x, y + 12, "clicks: #{@n}", theme_fg)
    @gfx.draw_text(x, y + 28, "Click anywhere.", theme_fg)
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
