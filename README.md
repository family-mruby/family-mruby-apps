# family-mruby-apps

Apps for [Family mruby](https://github.com/family-mruby/family-mruby), and the
list the store reads.

Write an app in Ruby, open a pull request, and once it is merged the app shows
up in the browser store and can be installed on a device.

## What an app looks like

One directory under `apps/`, named after the app's id:

```
apps/paint_pad/
├─ paint_pad.app.toml   the manifest (required -- see "Why a sidecar")
├─ paint_pad.app.rb     the app itself
└─ paint_pad.png        a picture of the app
```

The manifest is the same `.app.toml` the device reads, plus the keys the store
needs. The device looks its keys up by name, so the store's extra keys are
ignored there.

```toml
# What the device reads
app_screen_name = "Paint Pad"
app_screen_name_ja = "おえかき"
default_window_mode = "window"
default_window_width = 260
default_window_height = 170

# What the store reads
app_id = "paint_pad"                 # must match the directory name
app_version = "1.0.0"
app_author = "your name"
app_description = "Draw with the mouse"
app_description_ja = "マウスで描く"
app_category = "tool"                # game tool education demo media presentation
                                     # iot robotics development stamp other
app_env = ["retro", "modern", "web"] # where you have actually run it
app_min_width = 320                  # optional
app_min_height = 240
app_license = "MIT"                  # optional, SPDX
app_source = "https://..."           # optional
```

The app itself only defines a class. Once the file has been read, the firmware
makes the one `FmrbApp` subclass in it and starts it, so there is no
`MyApp.new.start` at the end (with two subclasses in one file, name the one
to start with `class = "MyApp"` in the manifest). Coordinates are relative to
the area inside the window's frame, and the frame is the firmware's to draw:

```ruby
class HelloApp < FmrbApp
  def on_create
    @n = 0
    draw_screen
  end

  def draw_screen
    clear_user_area                      # the theme's paper colour
    @gfx.draw_text(6, 6, "clicks: #{@n}", theme_fg)
    @gfx.present
  end

  def on_event(ev)                       # moving and closing are already done
    return unless ev[:type] == :mouse_up && ev[:button] == 1
    @n += 1
    draw_screen
  end

  def on_update
    100                                  # ms until the next call
  end
end
```

`apps/hello_store`, `apps/paint_pad` and `apps/wide_only` are complete
examples of this shape.

### Why a sidecar

The device does let a `.rb` carry its keys in a fenced `#---fmrb` comment at
the top, and that is fine for a script you launch yourself from the editor or
the shell. **It is not enough for an app someone installs.**

The installed `<app_id>.app.toml` is the store's record of the install: the
store on the device reads `app_version` from it to tell whether an app is
installed and whether the list has a newer one, and removing an app is
removing that directory. An app whose keys live only in a fence would install
and then look as if it never had.

So `<app_id>.app.toml` is required here, and `rake validate` says so. It also
complains if you leave a fence in the `.rb` as well: the sidecar wins, and two
copies of the same keys drift apart without anyone noticing.

### Picture

Commit one PNG that shows what your app is: `<app_id>.png`. A capture of your
app's **window** is the obvious choice, but it does not have to be one --
drawn artwork or a title card is just as good, and often reads better small.

`rake registry` makes the small one -- `<app_id>.thumb.png`, 32x24 -- from
what you committed. You never make that file yourself, but you do commit what
the command produces.

Two things to know, both about being shrunk eight times over:

- **Areas of colour and large shapes survive; single-pixel lines mostly
  disappear.** If your app draws thin lines, catch it when there is something
  solid on screen, or draw something for it instead.
- **A capture of the whole desktop becomes a picture of the wallpaper.**
  `rake validate` stops a picture that is exactly the size of a screen,
  because that is nearly always a capture that was never cropped. If yours is
  that size on purpose -- the app runs fullscreen, or the artwork just is --
  say `default_window_mode = "fullscreen"` or `app_image_full_size = true`.

### Stack

`task_stack_kb` raises the app's C stack above the default 16 KB. **Leave it
out unless something actually overflows.** That stack is internal RAM, which
is the scarcest thing on a board: with WiFi and BLE both up, a NARYA v4
refused to start a 32 KB app at all -- *largest internal block 31744 < 40960
needed* -- while the same app runs fine on the default. An app that asks for
more than it needs is an app that will not start on a busy machine.

### Memory

Leave it out unless you know you need it. An app that fits Retro's 500 KB pool
fits everywhere else, and that is nearly every app.

```toml
required_heap_kb_esp32 = 700    # Retro / Modern
required_heap_kb_linux = 1400   # the Linux simulator and the browser
```

## Stamp packs

A stamp pack is pictures for the chat app, and no program. The chat app on
Modern and in the browser offers the pictures of every installed pack as
stamps, a tab per pack. Stamps are not part of the firmware image; this is
where they come from.

```
apps/stamps_basic/
├─ stamps_basic.app.toml   the manifest, with stamp_pack = true
├─ stamps_basic.png        the picture the store shows (not a stamp)
├─ 01_smile.png            the stamps, in the order of their names
├─ 02_laugh.png
└─ ...
```

```toml
app_screen_name = "Basic"            # the tab's name in the chat
app_screen_name_ja = "きほん"
stamp_pack = true

app_id = "stamps_basic"
app_version = "1.0.0"
app_author = "your name"
app_description = "15 stamps for the chat: faces, heart, star, OK and more"
app_category = "stamp"
app_env = ["modern", "web"]          # the chat does not run on Retro
app_license = "MIT"
```

Every `*.png` in the directory but `<app_id>.png` is a stamp, and goes to the
device with the manifest. There is no script: with none, the launcher does not
list the pack as an app. `rake validate` holds each stamp to what the chat
accepts:

- **48x48 at most and 8 KB at most.** 32x32 is a good size: the chat shows a
  stamp in a 32 px square, doubling 16x16 and leaving 24 and 32 as they are.
- **A PNG the device decodes**: 8-bit RGB or RGBA, or a palette (1 to 8
  bits), not interlaced.
- **Names of `[a-z0-9_]` ending in `.png`**, which keeps them inside the
  file-name length of the board's file system. A number in front (`01_`,
  `02_`) sets the order.

**Transparency.** The screen has 256 colours (RGB332) and one of them, `0x01`
-- RGB(0, 0, 85) -- is drawn as see-through. A pixel whose alpha is below 128
reads as that colour, and so does a palette entry that `tRNS` makes
transparent. Draw with a transparent background and keep in mind that a
colour is cut to its top 3-3-2 bits on the device, so pick colours that
survive it.

The pictures of `stamps_basic` were drawn for this repository and are under
its licence (below), like everything else in `apps/`.

## Submitting

```
rake            # selftest + validate + registry, exactly what CI runs
```

`registry.json`, `registry.tsv` and the `*.thumb.png` files are generated. Run
`rake registry` and commit the result along with your app -- CI regenerates
them and fails if what you committed is not what the tools produce.

The two registries hold the same list. The store on a device reads the `.tsv`:
picoruby's JSON parser needed **7.6 seconds** for the 2.8 KB JSON on an
ESP32-P4, and splitting lines costs nothing. The `.json` is there for people
and for tools. Both come out of your `.app.toml` in the same pass, so they
cannot disagree -- and that is why a tab or a newline in a field is rejected.

## Licence

MIT, for this repository and everything in `apps/`. **Opening a pull request
here means publishing your app under the MIT licence.** If you would rather
use a different one, say so in the pull request -- put the SPDX identifier in
`app_license` and the full text next to your app.

The firmware is GPL-3.0, and that does not extend to apps: they are scripts it
reads and interprets at run time, not part of it.
