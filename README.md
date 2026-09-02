# family-mruby-apps

Apps for [Family mruby](https://github.com/family-mruby/family-mruby), and the
list the store reads.

Write an app in Ruby, open a pull request, and once it is merged the app shows
up in the browser store and can be installed on a device.

## What an app looks like

One directory under `apps/`, named after the app's id:

```
apps/paint_pad/
├─ paint_pad.app.toml   the manifest (optional -- see "One file" below)
├─ paint_pad.app.rb     the app itself
└─ paint_pad.png        a screenshot
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
task_stack_kb = 32

# What the store reads
app_id = "paint_pad"                 # must match the directory name
app_version = "1.0.0"
app_author = "your name"
app_description = "Draw with the mouse"
app_description_ja = "マウスで描く"
app_category = "tool"                # game tool education demo media
                                     # presentation iot robotics development other
app_env = ["retro", "modern", "web"] # where you have actually run it
app_min_width = 320                  # optional
app_min_height = 240
app_license = "MIT"                  # optional, SPDX
app_source = "https://..."           # optional
```

### Why a sidecar

The device does let a `.rb` carry its keys in a fenced `#---fmrb` comment at
the top, and that is fine for a script you launch yourself from the editor or
the shell. **It is not enough for an app someone installs.**

The launcher builds its list by walking `.toml` files; it never opens a `.rb`
looking for a fence. An app with only the inline form installs fine, runs fine
if you launch it by path, and **never appears in the launcher** -- so nobody
can find it. The firmware says as much when it sees one:

```
W: app_screen_name in the comment toml of hello_store.app.rb is ignored
   (launcher metadata needs a .toml sidecar)
```

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

## Submitting

```
rake            # selftest + validate + registry, exactly what CI runs
```

`registry.json` and the `*.thumb.bmp` files are generated. Run `rake registry`
and commit the result along with your app -- CI regenerates them and fails if
what you committed is not what the tools produce.

## Things that pass on a PC and fail on the machine

The device runs picoruby, not CRuby. `rake validate` catches these, but it is
quicker to not write them:

- **no `Regexp`** at all -- no literals, no `=~`, no `String#match`
- **no `defined?`** -- use `const_defined?` or `rescue`
- **no `Array#pack`**, **no `File.binread`**
- an app that never calls `.start` does nothing when it is launched
- blocks are expensive (about 0.4 ms a call); prefer `while` to `each` in a
  hot loop

## Licence

MIT, for this repository and everything in `apps/`. **Opening a pull request
here means publishing your app under the MIT licence.** If you would rather
use a different one, say so in the pull request -- put the SPDX identifier in
`app_license` and the full text next to your app.

The firmware is GPL-3.0, and that does not extend to apps: they are scripts it
reads and interprets at run time, not part of it.
