# Hello Store -- the smallest app the store can carry.
#
# The file only defines the class. Once it has been read, the firmware makes
# the one FmrbApp subclass it defines and starts it, so there is no
# `HelloStoreApp.new.start` at the end.
#
# No window, memory or stack keys in the .app.toml, so this also checks that
# an app arriving from the store still gets the defaults.

class HelloStoreApp < FmrbApp
  def on_create
    @n = 0
    draw_screen
  end

  # (0, 0) is the top left of the area inside the frame. The frame itself is
  # the firmware's to draw.
  def draw_screen
    clear_user_area
    # The default window is 100x100 and the font is 6 px wide, so about 15
    # characters fit on a line. An app that wants more has to ask for it in
    # its .app.toml; this one is here to show what the defaults give you.
    @gfx.draw_text(6, 6, "Hello!", theme_fg)
    @gfx.draw_text(6, 20, "clicks: #{@n}", theme_fg)
    @gfx.draw_text(6, 38, "Click me.", theme_border)
    @gfx.present
  end

  # Moving and closing the window have been dealt with before this is called.
  def on_event(ev)
    return unless ev[:type] == :mouse_up && ev[:button] == 1
    @n += 1
    draw_screen
  end

  def on_update
    100
  end
end
