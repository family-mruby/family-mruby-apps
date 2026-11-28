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
# Drawing: the whole screen is drawn when something other than the name
# changes; while the roulette spins only the name card is redrawn. Two small
# characters (sprites, drawn from the pixel art below) walk along the strip
# under the card, run while it spins and jump when a winner is shown. The
# timing is wall-clock time (Machine.board_millis), not frames.
#
# Sound: the APU through FmrbAudio#note_on / #note_off -- a short tick for
# each name shown and a short fanfare when the roulette stops.

class LotteryApp < FmrbApp
  DIR = "/home/lottery"
  NAMES = "/home/lottery/names.txt"
  WINNERS = "/home/lottery/winners.txt"

  SPIN_MS = 4500        # how long the roulette runs
  FIRST_GAP_MS = 45     # time between names at the start
  SLOW_MS = 420         # added to the gap by the end
  TICK_MS = 25          # length of one tick

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
    make_sprites
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
    @gfx.draw_text(@m, 3, tr("ちゅうせん", "Lottery"), COL_GOLD)
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
    when :result then draw_card_name(@winner, COL_WIN, true)
    when :spin then draw_card_name(@shown, COL_SPIN, false)
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
                "", tr("L キーかタップで読み直します", "L or tap to read it again")], COL_SPIN)
  end

  def draw_card_idle
    card_frame(COL_CARD_EDGE)
    if @cands.size == 0
      card_lines([tr("全員が当選しました", "Everyone has won"),
                  tr("R でリセットできます", "R puts everyone back")], COL_SPIN)
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

  def draw_card_name(name, color, won)
    card_frame(won ? COL_GOLD : COL_CARD_EDGE)
    if won
      small_font
      s = tr("おめでとう!", "Congratulations!")
      @gfx.draw_text(@card_x + (@card_w - @gfx.text_width(s)) / 2, @card_y + 8, s, COL_CHEER)
    end
    big_name(name || "", color)
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
    @fan_i = -1
    sound_off
    draw_hint
    @gfx.present
  end

  def spin_step(now)
    return if now < @next_switch
    elapsed = now - @spin_at
    if elapsed >= SPIN_MS
      finish_spin(now)
      return
    end
    @shown = pick_other(@shown)
    f = elapsed * 100 / SPIN_MS           # 0..99
    @next_switch = now + FIRST_GAP_MS + SLOW_MS * f * f / 10000
    draw_card_name(@shown, COL_SPIN, false)
    @gfx.present
    tick(now, 1400 + f * 4)
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
    save_winner(@winner)
    draw_all
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
    @tick_off_at = 0
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
  # in px per second, positions follow the wall clock.
  def sprite_step(now)
    dt = now - @sprite_at
    return if dt < (@state == :idle ? 80 : 33)
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
        y -= hop * @px * 3 / 150
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
    @gfx.present
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
    spin_step(now) if @state == :spin
    sound_step(now)
    sprite_step(now)
    if @state == :spin || @fan_i >= 0 || @tick_off_at > 0
      10
    else
      60
    end
  end
end
