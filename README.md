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

### One file

A small app can carry the same keys in a fenced comment at the top of the `.rb`
and skip the `.app.toml` entirely. This is what the device's own launcher
supports, so it is not a store-only shortcut.

```ruby
#---fmrb
# app_screen_name = "Hello Store"
# app_id = "hello_store"
# app_version = "1.0.0"
# ...
#---
```

The device reads only the **first 512 bytes** of the file looking for the
fence, and the fence has to come before the first line that is not a comment.
Keep the block short; if it does not fit, use a `.app.toml`.

### Screenshot

Commit a PNG of the app running, at the size of the screen you ran it on
(320x240 on Retro, 426x240 on Modern and in the browser). `rake registry`
shrinks it into the small BMP the device's store shows in its list; do not
commit that file by hand, but do commit what the command produces.

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
