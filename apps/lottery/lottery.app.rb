# Lottery -- draw names one at a time with a roulette.
#
# Names: /home/lottery/names.txt, one name per line (UTF-8, Japanese is
# fine). Blank lines and lines starting with # are left out. A name that is
# on two lines is two entries.
#
# Winners: /home/lottery/winners.txt, one line per winner, appended the
# moment the roulette stops. A winner is left out of later draws (one entry
# per line of winners.txt), so restarting the app or the board keeps the
# draw where it was. Resetting deletes the file.
#
# Keys
#   Space / Enter / click   draw (and draw again after a winner is shown)
#   R                       put everyone back (asks first: Y yes,
#                           N / Esc no; the buttons on screen do the same)
#   L                       read names.txt again
#   Esc                     close
#
# Logo (optional): a picture at /home/lottery/logo.png (a PNG, or an 8-bit
# BMP under that name) is shown small by the title and large on the card
# before the first draw. It is scaled by whole steps (1/2, 1/3, ... or 2x,
# 3x) to fit, and can have up to 65,536 pixels (256x256 or e.g. 320x200);
# transparent parts (alpha below 128) are left out. With no file the app
# looks as without it. L reads it again too.
#
# Drawing: the whole screen is drawn when something other than the name
# card changes; while the roulette spins or a winner is shown only the card
# is redrawn, about 30 times a second. While it spins a wheel of coloured
# slices turns behind the name (fill_arc), slowing down with the roulette,
# with lights round the rim and a pointer on top. When it stops the name
# card flips (its width follows a cosine), the screen shakes, the name zooms
# in through the text sizes with a small bounce of the card, rays (fill_arc
# wedges) turn behind it, confetti falls and the border flashes. Text cannot
# be rotated, so the turning is the wheel's and the rays'. Two small
# characters (sprites, drawn from the pixel art below) walk along the strip
# under the card, run while it spins and jump when a winner is shown. The
# timing is wall-clock time (Machine.board_millis), not frames.
#
# Sound: the APU through FmrbAudio#note_on / #note_off -- a short tick for
# each name shown, and a noise burst and a short fanfare when the roulette
# stops.

class LotteryApp < FmrbApp
  DIR = "/home/lottery"
  NAMES = "/home/lottery/names.txt"
  WINNERS = "/home/lottery/winners.txt"
  LOGO = "/home/lottery/logo.png"
  LOGO_MAX = 65536      # pixels the picture store takes

  SPIN_MS = 4500        # how long the roulette runs
  FIRST_GAP_MS = 45     # time between names at the start
  SLOW_MS = 420         # added to the gap by the end
  TICK_MS = 25          # length of one tick
  FRAME_MS = 33         # the card's frame time while it moves
  SLOW_FRAME_MS = 66    # ... once the reveal has settled
  WHEEL_TURN = 1500     # degrees the wheel turns during a draw
  FLIP_MS = 420         # the reveal: the card flips,
  ZOOM_MS = 360         # then the name zooms in (sizes 1 to 4),
  BOUNCE_MS = 160       # then the card bounces once
  FX_MS = 3600          # confetti and the flashing border last this long
  CHEER_MS = 2500       # the characters jump higher this long
  NOISE_MS = 160        # the noise burst at the reveal
  CONFETTI = 30         # pieces

  # Colours (RGB332). The screen is the app's own picture, so the colours
  # are chosen here rather than taken from the theme.
  COL_BG = 0x06         # dark blue
  COL_BAR = 0x02
  COL_CARD = 0xFF
  COL_CARD_EDGE = 0x92
  COL_GOLD = 0xF8
  COL_CHEER = 0xE8      # "congratulations" on the white card
  COL_SPIN = 0x49       # the names while spinning
  COL_WIN = 0xC0        # the winner's name
  COL_TEXT = 0xFF
  COL_DIM = 0xB6
  COL_PANEL = 0x0A
  COL_BTN = 0x6D
  COL_BTN_YES = 0xC4
  SPRITE_KEY = 0x00     # transparent in the sprites; nothing in them is 0x00
  COL_STAGE = 0x21      # the card's ground while it spins / shows a winner
  COL_RAY_BG = 0xA0     # the disc behind the rays
  COL_RAY = 0xF8        # the rays
  COL_LAMP_ON = 0xFC
  COL_LAMP_OFF = 0x6D
  # the wheel's slices, two rounds of six
  SLICES = [0xE0, 0xF4, 0xFC, 0x1C, 0x1F, 0x63, 0xE0, 0xF4, 0xFC, 0x1C, 0x1F, 0x63]
  CONFETTI_COLS = [0xE0, 0xFC, 0x1C, 0x1F, 0xE3, 0xFF, 0xF4, 0x9F]
  FLASH_COLS = [0xF8, 0xE0, 0xFF, 0x1C]
  SHAKE = [4, -3, 3, -4, 2, -2, 1, -1, 0]

  # Fanfare: [frequency Hz, ms] on the second pulse channel, the last note
  # held over a triangle an octave down.
  FANFARE = [[523, 110], [659, 110], [784, 110], [1047, 520]]

  # Pixel art, 12x12. '.' is transparent; the other letters are in PALETTE.
  PALETTE = { "k" => 0x24, "w" => 0xFF, "p" => 0xF6, "r" => 0xE0,
              "b" => 0x17, "y" => 0xFC, "g" => 0xB6, "o" => 0xF0 }
  MOCHI = [
    ["....kkkk....",
     "..kkwwwwkk..",
     ".kwwwwwwwwk.",
     ".kwwkwwkwwk.",
     "kwwwkwwkwwwk",
     "kwpwwwwwwpwk",
     "kwwwwkkwwwwk",
     "kwwwwwwwwwwk",
     ".kwwwwwwwwk.",
     "..kkkkkkkk..",
     "..kk....kk..",
     "............"],
    ["............",
     "....kkkk....",
     "..kkwwwwkk..",
     ".kwwwwwwwwk.",
     ".kwwkwwkwwk.",
     "kwwwkwwkwwwk",
     "kwpwwwwwwpwk",
     "kwwwwkkwwwwk",
     ".kwwwwwwwwk.",
     "..kkkkkkkk..",
     "...kk..kk...",
     "............"],
    ["k..........k",
     ".k..kkkk..k.",
     "..kkwwwwkk..",
     ".kwwwwwwwwk.",
     ".kwkwwwwkwk.",
     "kwwwkwwkwwwk",
     "kwpwwwwwwpwk",
     "kwwwkrrkwwwk",
     ".kwwwkkwwwk.",
     "..kkkkkkkk..",
     "..kk....kk..",
     "............"]
  ]
  ROBO = [
    [".....yy.....",
     "......k.....",
     "..kkkkkkkk..",
     "..kbbbbbbk..",
     "..kbybbybk..",
     "..kbbbbbbk..",
     "..kbkkkkbk..",
     "..kkkkkkkk..",
     "...kggggk...",
     ".kkkggggkkk.",
     "...kggggk...",
     "...kk..kk..."],
    ["......yy....",
     "......k.....",
     "..kkkkkkkk..",
     "..kbbbbbbk..",
     "..kbybbybk..",
     "..kbbbbbbk..",
     "..kbkkkkbk..",
     "..kkkkkkkk..",
     "...kggggk...",
     ".kkkggggkkk.",
     "...kggggk...",
     "..kk....kk.."],
    ["k....yy....k",
     "k.....k....k",
     "k.kkkkkkkk.k",
     "kkkbbbbbbkkk",
     "..kbybbybk..",
     "..kbbbbbbk..",
     "..kbkookbk..",
     "..kkkkkkkk..",
     "...kggggk...",
     "...kggggk...",
     "...kggggk...",
     "...kk..kk..."]
  ]

  def on_create
    @audio = FmrbAudio.new(self)
    @ja = (FmrbApp.language == "ja")
    @state = :idle        # :idle :spin :result :confirm :empty
    @shown = nil          # the name on the card
    @winner = nil
    @spin_at = 0
    @next_switch = 0
    @tick_off_at = 0
    @fan_i = -1
    @fan_at = 0
    @noise_off_at = 0
    @frame_at = 0
    @fx_at = 0
    @wheel_deg = 0
    @tick_n = 0
    @nl_name = nil        # the name whose layout is in @nl_*
    @cf_x = []            # confetti: x in the card, start y, speed, colour
    @cf_y = []
    @cf_v = []
    @cf_c = []
    @logo = nil
    @sprites = []
    @images = []
    @hits = FmrbUI::HitAreas.new
    @gfx.set_font(:ja, 12)
    load_lists
    layout(@user_area_width, @user_area_height)
    draw_all
  end

  def on_resize(w, h)
    layout(w, h)
    draw_all
  end

  def on_destroy
    sound_off
    free_sprites
  end

  # ---- names and winners ------------------------------------------------

  def read_lines(path)
    out = []
    data = FmrbFile.read(path)
    return out unless data
    lines = data.split("\n")
    i = 0
    while i < lines.size
      s = lines[i].strip
      out << s if s.size > 0 && s[0] != "#"
      i += 1
    end
    out
  end

  def load_lists
    FmrbFile.mkdir(DIR) unless FmrbFile.exist?(DIR)
    @names_found = FmrbFile.exist?(NAMES)
    @names = read_lines(NAMES)
    @winners = read_lines(WINNERS)
    rebuild_candidates
    @state = @names.size == 0 ? :empty : :idle
    @shown = nil
    load_logo
  end

  # The optional logo: only its size is read here (the head of the file);
  # draw_picture reads the picture onto the display side the first time it
  # is drawn, and again when the file changes.
  def load_logo
    @logo = nil
    info = @gfx.picture_info(LOGO)
    return unless info
    w = info[:width].to_i
    h = info[:height].to_i
    return if w <= 0 || h <= 0
    if w * h > LOGO_MAX
      puts "lottery: #{LOGO} is #{w}x#{h}; up to #{LOGO_MAX} pixels (256x256) can be shown"
      return
    end
    @logo = LOGO
    @logo_w = w
    @logo_h = h
  end

  # [scale, width, height] for the logo inside bw x bh: the largest whole
  # step that fits (2x .. 4x up, 1/2 .. 1/32 down).
  def logo_fit(bw, bh)
    w = @logo_w
    h = @logo_h
    if w <= bw && h <= bh
      s = bw / w
      s = bh / h if bh / h < s
      s = 4 if s > 4
      s = 1 if s < 1
      return [s, w * s, h * s]
    end
    s = (w + bw - 1) / bw
    sh = (h + bh - 1) / bh
    s = sh if sh > s
    s = 2 if s < 2
    s = 32 if s > 32
    [-s, (w + s - 1) / s, (h + s - 1) / s]
  end

  def draw_logo(x, y, fit)
    @gfx.draw_picture(@logo, x, y, scale: fit[0])
  end

  # Everyone in names.txt, less one entry for each line of winners.txt.
  def rebuild_candidates
    left = @winners.dup
    @cands = []
    i = 0
    while i < @names.size
      n = @names[i]
      j = left.index(n)
      if j
        left.delete_at(j)
      else
        @cands << n
      end
      i += 1
    end
  end

  def save_winner(name)
    FmrbFile.mkdir(DIR) unless FmrbFile.exist?(DIR)
    FmrbFile.append(WINNERS, name + "\n")
    @winners << name
    rebuild_candidates
  end

  def reset_winners
    FmrbFile.delete(WINNERS) if FmrbFile.exist?(WINNERS)
    @winners = []
    rebuild_candidates
  end

  def tr(ja, en)
    @ja ? ja : en
  end

  # ---- layout -----------------------------------------------------------

  def layout(w, h)
    @w = w
    @h = h
    @big = h >= 300                       # 640x360 and up
    @fs = @big ? 16 : 12                  # the small text's font size
    @lh = @fs + (@big ? 6 : 4)            # a line of small text
    @m = @big ? 10 : 6                    # margin
    @bar_h = @lh + 4
    @hint_h = @lh + 2
    @px = @big ? 3 : 2                    # sprite pixel size
    @spr = 12 * @px                       # sprite side
    @panel_w = w * 30 / 100
    @panel_x = w - @panel_w
    @main_x = @m
    @main_w = @panel_x - @m * 2
    @stage_h = @spr + 4
    @stage_y = h - @hint_h - @stage_h
    @card_x = @main_x
    @card_y = @bar_h + @m
    @card_w = @main_w
    @card_h = @stage_y - @m - @card_y
    @wheel_r = @card_h / 2 - 12           # room for the lamps and the pointer
    @nl_name = nil
    make_lamps
    make_sprites
  end

  # The lamps round the wheel: fixed places, lit in turn.
  def make_lamps
    @lamp_dx = []
    @lamp_dy = []
    r = @wheel_r + 6
    i = 0
    while i < 16
      a = ::Math::PI * 2 * i / 16
      @lamp_dx << (::Math.cos(a) * r).round
      @lamp_dy << (::Math.sin(a) * r).round
      i += 1
    end
  end

  # ---- drawing ----------------------------------------------------------

  def draw_all
    @hits.clear
    @gfx.fill_rect(0, 0, @w, @h, COL_BG)
    draw_bar
    draw_panel
    draw_card
    draw_hint
    @gfx.present
  end

  def small_font
    @gfx.set_font(:ja, @fs)
    @gfx.set_text_size(1)
  end

  def draw_bar
    small_font
    @gfx.fill_rect(0, 0, @w, @bar_h, COL_BAR)
    tx = @m
    if @logo
      fit = logo_fit(@bar_h * 4, @bar_h - 4)
      tx += fit[1] + 6 if draw_logo(@m, (@bar_h - fit[2]) / 2, fit)
    end
    @gfx.draw_text(tx, 3, tr("ちゅうせん", "Lottery"), COL_GOLD)
    if @names.size > 0
      s = tr("のこり #{@cands.size} / #{@names.size} 人", "#{@cands.size} of #{@names.size} left")
      @gfx.draw_text(@panel_x - @m - @gfx.text_width(s), 3, s, COL_TEXT)
    end
  end

  def draw_panel
    small_font
    x = @panel_x
    y = @bar_h
    ph = @h - @bar_h
    @gfx.fill_rect(x, y, @panel_w, ph, COL_PANEL)
    @gfx.draw_text(x + @m, y + 4, tr("当選 #{@winners.size} 人", "Winners: #{@winners.size}"), COL_GOLD)
    btn_h = @lh + 2
    btn_y = @h - btn_h - @m / 2
    rows = (btn_y - (y + 4 + @lh) - 4) / @lh
    rows = 0 if rows < 0
    # newest first, numbered in the order they won
    k = @winners.size - 1
    ly = y + 4 + @lh + 2
    shown = 0
    while k >= 0 && shown < rows
      line = "#{k + 1}. #{@winners[k]}"
      line = @gfx.fit_text(line, @panel_w - @m * 2, "..")
      @gfx.draw_text(x + @m, ly, line, k == @winners.size - 1 && @state == :result ? COL_GOLD : COL_TEXT)
      ly += @lh
      shown += 1
      k -= 1
    end
    if @winners.size > 0
      bw = @panel_w - @m * 2
      @gfx.draw_button(x + @m, btn_y, bw, btn_h, tr("リセット (R)", "Reset (R)"), COL_BTN, COL_TEXT)
      @hits.add(:reset, x + @m, btn_y, bw, btn_h)
    end
  end

  def draw_hint
    small_font
    y = @h - @hint_h
    @gfx.fill_rect(0, y, @panel_x, @hint_h, COL_BAR)
    s = case @state
        when :empty then tr("L: 読み直し   Esc: 終わる", "L: read again   Esc: close")
        when :confirm then tr("Y: はい   N: いいえ", "Y: yes   N: no")
        when :spin then tr("ちゅうせん中...", "Drawing...")
        else tr("Space・Enter・タップ: 引く  R: リセット  L: 読み直し", "Space/Enter/tap: draw  R: reset  L: reload")
        end
    s = @gfx.fit_text(s, @panel_x - @m * 2, "..")
    @gfx.draw_text(@m, y + 1, s, COL_DIM)
  end

  def card_frame(edge)
    @gfx.fill_rect(@card_x, @card_y, @card_w, @card_h, COL_BG)
    @gfx.fill_round_rect(@card_x, @card_y, @card_w, @card_h, 8, edge)
    @gfx.fill_round_rect(@card_x + 3, @card_y + 3, @card_w - 6, @card_h - 6, 6, COL_CARD)
  end

  def draw_card
    case @state
    when :empty then draw_card_empty
    when :confirm then draw_card_confirm
    when :result, :spin then draw_stage(Machine.board_millis)
    else draw_card_idle
    end
  end

  def card_lines(lines, color)
    small_font
    y = @card_y + (@card_h - lines.size * @lh) / 2
    i = 0
    while i < lines.size
      s = @gfx.fit_text(lines[i], @card_w - 12, "..")
      @gfx.draw_text(@card_x + (@card_w - @gfx.text_width(s)) / 2, y, s, color)
      y += @lh
      i += 1
    end
  end

  def draw_card_empty
    card_frame(COL_CARD_EDGE)
    first = @names_found ? tr("名前が 1 つもありません", "The list has no names") :
                           tr("名前のファイルがありません", "No list of names yet")
    card_lines([first, "", NAMES,
                tr("に 1 行に 1 人ずつ書いてください", "one name per line"),
                tr("(# で始まる行と空の行は読みません)", "(# lines and blank lines are skipped)"),
                tr("ブラウザ版: 画面の下の Add の Files... で", "In the browser: Add - Files... under the screen,"),
                tr("into を /home/lottery にして入れます", "into /home/lottery"),
                "", tr("L キーかタップで読み直します", "L or tap to read it again")], COL_SPIN)
  end

  def draw_card_idle
    card_frame(COL_CARD_EDGE)
    if @cands.size == 0
      card_lines([tr("全員が当選しました", "Everyone has won"),
                  tr("R でリセットできます", "R puts everyone back")], COL_SPIN)
    elsif @logo
      # the logo large, the word under it
      s = tr("ちゅうせん", "Ready")
      @gfx.set_font(:ja, 16)
      @gfx.set_text_size(2)
      th = 32
      bh = @card_h - th - 24
      fit = logo_fit(@card_w - 24, bh)
      ok = draw_logo(@card_x + (@card_w - fit[1]) / 2, @card_y + 8 + (bh - fit[2]) / 2, fit)
      @gfx.set_text_size(2)
      ty = ok ? @card_y + @card_h - th - 10 : @card_y + (@card_h - th) / 2
      @gfx.draw_text(@card_x + (@card_w - @gfx.text_width(s)) / 2, ty, s, COL_SPIN)
      @gfx.set_text_size(1)
    else
      big_name(tr("ちゅうせん", "Ready"), COL_SPIN)
    end
  end

  def draw_card_confirm
    card_frame(COL_WIN)
    small_font
    s = tr("当選者を全員もどしますか?", "Put all the winners back?")
    @gfx.draw_text(@card_x + (@card_w - @gfx.text_width(s)) / 2, @card_y + @card_h / 2 - @lh - 4, s, COL_SPIN)
    s = tr("(#{WINNERS} を消します)", "(deletes #{WINNERS})")
    s = @gfx.fit_text(s, @card_w - 12, "..")
    @gfx.draw_text(@card_x + (@card_w - @gfx.text_width(s)) / 2, @card_y + @card_h / 2 - 2, s, COL_CARD_EDGE)
    bw = @card_w / 3
    bh = @lh + 6
    by = @card_y + @card_h / 2 + @lh
    gap = @card_w / 12
    x1 = @card_x + @card_w / 2 - gap / 2 - bw
    x2 = @card_x + @card_w / 2 + gap / 2
    @gfx.draw_button(x1, by, bw, bh, tr("はい (Y)", "Yes (Y)"), COL_BTN_YES, COL_TEXT)
    @gfx.draw_button(x2, by, bw, bh, tr("いいえ (N)", "No (N)"), COL_BTN, COL_TEXT)
    @hits.add(:yes, x1, by, bw, bh)
    @hits.add(:no, x2, by, bw, bh)
  end

  # ---- the stage: the card while it spins and when a winner is shown -----

  # The card's picture for this moment. The wheel (spin) or the rays
  # (result) turn behind the plate with the name; the reveal's shake, flip,
  # zoom, bounce, confetti and flashing border are worked out from the time
  # since the roulette stopped. Draws only; the caller presents.
  def draw_stage(now)
    won = @state == :result
    t = won ? now - @fx_at : -1
    ox = 0
    oy = 0
    if t >= 0 && t < SHAKE.size * 45
      ox = SHAKE[t / 45]
      oy = SHAKE[(t / 45 + 3) % SHAKE.size]
    end
    @gfx.fill_rect(@card_x - 4, @card_y - 4, @card_w + 8, @card_h + 8, COL_BG)
    x = @card_x + ox
    y = @card_y + oy
    if won
      edge = t < FX_MS ? FLASH_COLS[(t / 90) % FLASH_COLS.size] : COL_GOLD
    else
      edge = @tick_n % 2 == 0 ? COL_GOLD : COL_CARD_EDGE
    end
    @gfx.fill_round_rect(x, y, @card_w, @card_h, 8, edge)
    @gfx.fill_round_rect(x + 3, y + 3, @card_w - 6, @card_h - 6, 6, COL_STAGE)
    cx = x + @card_w / 2
    cy = y + @card_h / 2
    if won
      draw_rays(cx, cy, t)
      draw_confetti(x, y, t) if t < FX_MS  # behind the name: it stays readable
      draw_plate(cx, cy, @winner || "", COL_WIN, t)
      draw_cheer(cx, y, t) if t >= FLIP_MS
    else
      draw_wheel(cx, cy)
      draw_plate(cx, cy, @shown || "", COL_SPIN, -1)
    end
  end

  def draw_wheel(cx, cy)
    r = @wheel_r
    a = @wheel_deg % 360
    i = 0
    while i < 12
      a0 = a + i * 30
      @gfx.fill_arc(cx, cy, 0, r, a0, a0 + 30, SLICES[i])
      i += 1
    end
    @gfx.draw_circle(cx, cy, r, COL_GOLD)
    @gfx.draw_circle(cx, cy, r + 1, COL_GOLD)
    lr = @big ? 3 : 2
    i = 0
    while i < 16
      c = (i + @tick_n) % 3 == 0 ? COL_LAMP_ON : COL_LAMP_OFF
      @gfx.fill_circle(cx + @lamp_dx[i], cy + @lamp_dy[i], lr, c)
      i += 1
    end
    # the pointer on top
    pw = @big ? 10 : 7
    ty = cy - r - 10
    @gfx.fill_triangle(cx - pw, ty, cx + pw, ty, cx, ty + pw * 2, COL_CARD)
    @gfx.draw_triangle(cx - pw, ty, cx + pw, ty, cx, ty + pw * 2, COL_WIN)
  end

  def draw_rays(cx, cy, t)
    r = @wheel_r + 8
    @gfx.fill_circle(cx, cy, r, COL_RAY_BG)
    a = (t * 40 / 1000) % 360             # 40 degrees a second
    i = 0
    while i < 8
      a0 = a + i * 45
      @gfx.fill_arc(cx, cy, 0, r, a0, a0 + 22, COL_RAY)
      i += 1
    end
  end

  # The plate with the name, centred on (cx, cy). t < 0: spinning, the name
  # at its size. t >= 0: the reveal -- flip (no name), zoom, bounce.
  def draw_plate(cx, cy, name, color, t)
    name_layout(name)
    size = @nl_size
    back = false
    wf = 1000                             # the plate's width, per mille
    grow = 0
    if t < 0
      size = 3 if size > 3 && !@big       # a small screen: leave some wheel showing
    elsif t < FLIP_MS
      c = ::Math.cos(::Math::PI * 3 * t / FLIP_MS)
      back = c < 0
      wf = (c.abs * 1000).to_i
      size = 0
    elsif t >= 0 && t < FLIP_MS + ZOOM_MS
      cap = 1 + (t - FLIP_MS) * 4 / ZOOM_MS
      size = cap if cap < size
    elsif t >= 0 && t < FLIP_MS + ZOOM_MS + BOUNCE_MS
      grow = @big ? 10 : 6
    end
    s = size < 1 ? @nl_size : size        # the plate's size even while flipping
    n = @nl_lines.size
    lh = 16 * s + 4
    th = n * lh - 4
    pw = @nl_wmax * s + 32 + grow * 2
    min = @card_w * 45 / 100
    pw = min if pw < min
    pw = @card_w - 10 if pw > @card_w - 10
    ph = th + 16 + grow * 2
    pw = pw * wf / 1000
    pw = 6 if pw < 6
    px = cx - pw / 2
    py = cy - ph / 2
    edge = t < 0 ? (@tick_n % 2 == 0 ? COL_WIN : COL_CARD_EDGE) : COL_GOLD
    @gfx.fill_round_rect(px - 2, py - 2, pw + 4, ph + 4, 8, edge)
    @gfx.fill_round_rect(px, py, pw, ph, 6, back ? COL_GOLD : COL_CARD)
    return if size < 1
    @gfx.set_font(:ja, 16)
    @gfx.set_text_size(size)
    lh = 16 * size + 4
    y = cy - (n * lh - 4) / 2
    i = 0
    while i < n
      @gfx.draw_text(cx - @nl_w1[i] * size / 2, y, @nl_lines[i], color)
      y += lh
      i += 1
    end
    @gfx.set_text_size(1)
  end

  def draw_cheer(cx, y, t)
    s = tr("おめでとう!", "Congratulations!")
    @gfx.set_font(:ja, 16)
    sz = @big ? 2 : 1
    @gfx.set_text_size(sz)
    w = @gfx.text_width(s)
    c = t < FX_MS ? FLASH_COLS[(t / 180) % 2] : COL_GOLD
    @gfx.draw_text(cx - w / 2, y + 6, s, c, COL_STAGE)
    @gfx.set_text_size(1)
  end

  def start_confetti
    @cf_x = []
    @cf_y = []
    @cf_v = []
    @cf_c = []
    i = 0
    while i < CONFETTI
      @cf_x << 6 + rand(@card_w - 16)
      @cf_y << -rand(@card_h * 2 / 3)      # start above the top
      @cf_v << @card_h * (45 + rand(50)) / 100   # px a second
      @cf_c << CONFETTI_COLS[i % CONFETTI_COLS.size]
      i += 1
    end
  end

  def draw_confetti(x, y, t)
    lo = 4
    hi = @card_h - 8
    i = 0
    while i < @cf_x.size
      py = @cf_y[i] + @cf_v[i] * t / 1000
      if py >= lo && py <= hi
        p = (t / 25 + i * 7) % 24            # a sway left and right
        dx = (p < 12 ? p : 24 - p) / 2 - 3
        if (t / 120 + i) % 2 == 0           # flutter: tall, then wide
          @gfx.fill_rect(x + @cf_x[i] + dx, y + py, 3, 6, @cf_c[i])
        else
          @gfx.fill_rect(x + @cf_x[i] + dx, y + py + 1, 6, 3, @cf_c[i])
        end
      end
      i += 1
    end
  end

  # How the name is laid out at its largest (the same rule as big_name),
  # kept until the name or the layout changes: @nl_size, @nl_lines, the
  # width of each line at size 1 (@nl_w1) and the widest (@nl_wmax).
  def name_layout(name)
    return if @nl_name == name
    @gfx.set_font(:ja, 16)
    @gfx.set_text_size(1)
    avail = @card_w - 16
    hmax = (@card_h - @lh * 2) / 16
    w1 = @gfx.text_width(name)
    w1 = 1 if w1 < 1
    size = avail / w1
    size = hmax if size > hmax
    size = 4 if size > 4
    lines = nil
    if size < 2 || (size < 4 && w1 > avail / 2)
      two = (hmax - 1) / 2
      two = 4 if two > 4
      while two > size
        @gfx.set_text_size(two)
        l2 = @gfx.wrap_text(name, avail)
        if l2.size == 2 && fits_whole(name, l2)
          lines = l2
          size = two
          break
        end
        two -= 1
      end
      @gfx.set_text_size(1)
    end
    size = 1 if size < 1
    if lines.nil?
      lines = [size == 1 ? @gfx.fit_text(name, avail, "..") : name]
    end
    @nl_w1 = []
    @nl_wmax = 0
    i = 0
    while i < lines.size
      w = @gfx.text_width(lines[i])
      @nl_w1 << w
      @nl_wmax = w if w > @nl_wmax
      i += 1
    end
    @nl_lines = lines
    @nl_size = size
    @nl_name = name
  end

  # The name as large as fits the card: the 16 px font at 1x to 4x on one
  # line, or on two lines when one line would need a smaller size than two.
  # (The firmware's largest text size is 4.)
  def big_name(name, color)
    @gfx.set_font(:ja, 16)
    @gfx.set_text_size(1)
    avail = @card_w - 16
    hmax = (@card_h - @lh * 2) / 16
    w1 = @gfx.text_width(name)
    w1 = 1 if w1 < 1
    size = avail / w1
    size = hmax if size > hmax
    size = 4 if size > 4
    if size < 2 || (size < 4 && w1 > avail / 2)
      two = (hmax - 1) / 2                # two lines with a gap between
      two = 4 if two > 4
      while two > size
        @gfx.set_text_size(two)
        lines = @gfx.wrap_text(name, avail)
        if lines.size == 2 && fits_whole(name, lines)
          lh = 16 * two + 4
          y = @card_y + (@card_h - lh * 2 + 4) / 2
          @gfx.draw_text(@card_x + (@card_w - @gfx.text_width(lines[0])) / 2, y, lines[0], color)
          @gfx.draw_text(@card_x + (@card_w - @gfx.text_width(lines[1])) / 2, y + lh, lines[1], color)
          @gfx.set_text_size(1)
          return
        end
        two -= 1
      end
    end
    size = 1 if size < 1
    @gfx.set_text_size(size)
    s = size == 1 ? @gfx.fit_text(name, avail, "..") : name
    tw = @gfx.text_width(s)
    @gfx.draw_text(@card_x + (@card_w - tw) / 2, @card_y + (@card_h - 16 * size) / 2, s, color)
    @gfx.set_text_size(1)
  end

  # Whether the two lines of wrap_text hold all of name: a cut second line
  # ends in the 3-byte mark wrap_text adds, and is shorter than the rest.
  def fits_whole(name, lines)
    l2 = lines[1]
    n = l2.bytesize
    if n >= 3 && l2.byteslice(n - 3, 3) == "\u2026"
      return false if lines[0].bytesize + n != name.bytesize
    end
    lines[0].bytesize + n + 1 >= name.bytesize
  end

  # ---- the draw ---------------------------------------------------------

  def start_spin
    if @cands.size == 0
      @state = :idle                      # shows "everyone has won"
      draw_all
      return
    end
    now = Machine.board_millis
    @winner = @cands[rand(@cands.size)]
    @state = :spin
    @spin_at = now
    @next_switch = now
    @frame_at = 0
    @wheel_deg = rand(360)
    @wheel_from = @wheel_deg
    @fan_i = -1
    sound_off
    draw_hint
    @gfx.present
  end

  # One step of the roulette: a new name when its time has come (with a
  # tick), and the card again every FRAME_MS for the wheel. The wheel's
  # angle is the integral of a speed falling as (1 - f)^2, so it stops
  # turning just as the roulette stops. true when it drew.
  def spin_step(now)
    elapsed = now - @spin_at
    if elapsed >= SPIN_MS
      finish_spin(now)
      return true
    end
    g = 1000 - elapsed * 1000 / SPIN_MS   # 1000..1
    g3 = g * g / 1000 * g / 1000
    @wheel_deg = @wheel_from + WHEEL_TURN - WHEEL_TURN * g3 / 1000
    changed = false
    if now >= @next_switch
      @shown = pick_other(@shown)
      f = elapsed * 100 / SPIN_MS         # 0..99
      @next_switch = now + FIRST_GAP_MS + SLOW_MS * f * f / 10000
      @tick_n += 1
      tick(now, 1400 + f * 4)
      changed = true
    end
    return false unless changed || now - @frame_at >= FRAME_MS
    @frame_at = now
    draw_stage(now)
    true
  end

  # The reveal goes on being drawn: fast while it moves, slower once only
  # the rays turn.
  def result_step(now)
    gap = now - @fx_at < FX_MS ? FRAME_MS : SLOW_FRAME_MS
    return false if now - @frame_at < gap
    @frame_at = now
    draw_stage(now)
    true
  end

  def pick_other(prev)
    n = @cands.size
    return @cands[0] if n == 1
    s = @cands[rand(n)]
    s = @cands[rand(n)] if s == prev
    s
  end

  def finish_spin(now)
    @state = :result
    @shown = @winner
    @fx_at = now
    @frame_at = now
    save_winner(@winner)
    start_confetti
    draw_all
    @audio.note_on_raw(FmrbAudio::CH_NOISE, 2000, 9, 0, 0)
    @noise_off_at = now + NOISE_MS
    start_fanfare(now)
  end

  # ---- sound ------------------------------------------------------------

  def tick(now, freq)
    @audio.note_on_raw(FmrbAudio::CH_PULSE1, freq, 7, 1, 0)
    @tick_off_at = now + TICK_MS
  end

  def start_fanfare(now)
    @fan_i = 0
    @fan_at = now
    play_fan_note
  end

  def play_fan_note
    note = FANFARE[@fan_i]
    @audio.note_on_raw(FmrbAudio::CH_PULSE2, note[0], 10, 2, 0)
    if @fan_i == FANFARE.size - 1
      @audio.note_on_raw(FmrbAudio::CH_TRIANGLE, note[0] / 2, 10, 2, 0)
    end
    @fan_at += note[1]
  end

  def sound_step(now)
    if @tick_off_at > 0 && now >= @tick_off_at
      @audio.note_off(FmrbAudio::CH_PULSE1)
      @tick_off_at = 0
    end
    if @noise_off_at > 0 && now >= @noise_off_at
      @audio.note_off(FmrbAudio::CH_NOISE)
      @noise_off_at = 0
    end
    return if @fan_i < 0 || now < @fan_at
    @fan_i += 1
    if @fan_i >= FANFARE.size
      @audio.note_off(FmrbAudio::CH_PULSE2)
      @audio.note_off(FmrbAudio::CH_TRIANGLE)
      @fan_i = -1
    else
      @audio.note_off(FmrbAudio::CH_PULSE2)
      play_fan_note
    end
  end

  def sound_off
    @audio.note_off(FmrbAudio::CH_PULSE1)
    @audio.note_off(FmrbAudio::CH_PULSE2)
    @audio.note_off(FmrbAudio::CH_TRIANGLE)
    @audio.note_off(FmrbAudio::CH_NOISE)
    @tick_off_at = 0
    @noise_off_at = 0
    @fan_i = -1
  end

  # ---- sprites ----------------------------------------------------------

  def art_image(rows)
    s = @px
    side = 12 * s
    buf = "\x00" * (side * side)
    y = 0
    while y < 12
      row = rows[y]
      x = 0
      while x < 12
        c = PALETTE[row[x]]
        if c
          dy = 0
          while dy < s
            base = (y * s + dy) * side + x * s
            dx = 0
            while dx < s
              buf.setbyte(base + dx, c)
              dx += 1
            end
            dy += 1
          end
        end
        x += 1
      end
      y += 1
    end
    img = SpriteImage.new(@gfx, width: side, height: side,
                          transparent_color: SPRITE_KEY, use_transparent: true)
    img.write_pixels(buf)
    @images << img
    img
  end

  def make_sprites
    free_sprites
    sets = [MOCHI, ROBO]
    @walk_x = []
    @walk_dir = []
    i = 0
    while i < sets.size
      art = sets[i]
      frames = [art_image(art[0]), art_image(art[1]), art_image(art[2])]
      x = @main_x + 4 + i * (@main_w / 2)
      @sprites << SpriteInstance.new(@gfx, frames, x: x, y: @stage_y + 2, z: 1)
      @walk_x << x * 16                   # 1/16 px
      @walk_dir << (i == 0 ? 1 : -1)
      i += 1
    end
    @sprite_at = Machine.board_millis
  end

  def free_sprites
    i = 0
    while i < @sprites.size
      @sprites[i].destroy
      i += 1
    end
    i = 0
    while i < @images.size
      @images[i].destroy
      i += 1
    end
    @sprites = []
    @images = []
  end

  # Walk (idle), run and hop (spin), jump with arms up (result). Speeds are
  # in px per second, positions follow the wall clock. true when they moved.
  def sprite_step(now)
    dt = now - @sprite_at
    return false if dt < (@state == :idle ? 80 : 33)
    @sprite_at = now
    dt = 100 if dt > 100
    speed = @state == :spin ? 70 * @px : 12 * @px
    lo = (@main_x + 2) * 16
    hi = (@main_x + @main_w - @spr - 2) * 16
    i = 0
    while i < @sprites.size
      x = @walk_x[i] + @walk_dir[i] * speed * dt * 16 / 1000
      if @state == :result
        # each runs to its own side (a quarter in from the left or the right)
        goal = (@main_x + @main_w * (i == 0 ? 1 : 3) / 4 - @spr / 2) * 16
        step = 70 * @px * dt * 16 / 1000
        x = @walk_x[i]
        if x < goal - step
          x += step
        elsif x > goal + step
          x -= step
        else
          x = goal
        end
      elsif x < lo
        x = lo
        @walk_dir[i] = 1
      elsif x > hi
        x = hi
        @walk_dir[i] = -1
      end
      @walk_x[i] = x
      y = @stage_y + 2
      if @state == :result
        ph = (now / 2 + i * 120) % 300   # a jump every 600 ms
        hop = ph < 150 ? ph : 300 - ph
        high = now - @fx_at < CHEER_MS ? 7 : 3   # higher just after the reveal
        y -= hop * @px * high / 150
        frame = 2
      elsif @state == :spin
        ph = (now + i * 90) % 240
        hop = ph < 120 ? ph : 240 - ph
        y -= hop * @px * 2 / 120
        frame = (now / 120 + i) % 2
      else
        frame = (now / 300 + i) % 2
      end
      sp = @sprites[i]
      sp.frame = frame
      sp.move(x / 16, y)
      i += 1
    end
    true
  end

  # ---- events -----------------------------------------------------------

  def on_event(ev)
    case ev[:type]
    when :key_down
      on_key(ev[:scancode])
    when :mouse_down
      on_click(ev[:x], ev[:y]) if ev[:button] == 1
    end
  end

  def on_key(sc)
    if @state == :confirm
      if sc == FmrbConst::KEY_Y           # not Enter: that is the draw key
        answer_reset(true)
      elsif sc == FmrbConst::KEY_N || sc == FmrbConst::KEY_ESC
        answer_reset(false)
      end
      return
    end
    if sc == FmrbConst::KEY_ESC
      sound_off
      stop
    elsif sc == FmrbConst::KEY_SPACE || sc == FmrbConst::KEY_ENTER
      start_spin if @state == :idle || @state == :result
    elsif sc == FmrbConst::KEY_R
      ask_reset
    elsif sc == FmrbConst::KEY_L
      reload
    end
  end

  def on_click(x, y)
    id = @hits.id_at(x, y)
    if @state == :confirm
      answer_reset(true) if id == :yes
      answer_reset(false) if id == :no
    elsif id == :reset
      ask_reset
    elsif @state == :empty
      reload
    elsif @state == :idle || @state == :result
      start_spin
    end
  end

  def ask_reset
    return if @state == :spin || @winners.size == 0
    @state = :confirm
    draw_all
  end

  def answer_reset(yes)
    reset_winners if yes
    @state = @names.size == 0 ? :empty : :idle
    @shown = nil
    draw_all
  end

  def reload
    return if @state == :spin
    sound_off
    load_lists
    draw_all
  end

  def on_update
    now = Machine.board_millis
    drew = false
    if @state == :spin
      drew = spin_step(now)
    elsif @state == :result
      drew = result_step(now)
    end
    sound_step(now)
    drew = true if sprite_step(now)
    @gfx.present if drew                  # one present for the card and the sprites
    if @state == :spin || @fan_i >= 0 || @tick_off_at > 0 ||
       (@state == :result && now - @fx_at < FX_MS)
      10
    elsif @state == :result
      30
    else
      60
    end
  end
end
