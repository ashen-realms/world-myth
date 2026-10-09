require "./native"
require "../core"

module WorldMyth::GUI
  class SpriteEditor
    getter widget = Gtk::Box.new(:vertical, 6)
    getter area = Gtk::DrawingArea.new
    property on_change : Proc(Nil) = -> { }
    property on_error : Proc(Exception, Nil) = ->(ex : Exception) { STDERR.puts ex.message }
    @document : Core::Document?
    @draft : Core::Sprite?
    @revision = 0_i64
    @clip = "idle"
    @direction = "S"
    @index = 0
    @playing = false
    @time = 0_i64
    @last_tick = Time.instant
    @loading = false
    @animations : Gtk::DropDown = Gtk::DropDown.new_from_strings(["idle"])
    @directions : Gtk::DropDown = Gtk::DropDown.new_from_strings(Core::DIRECTIONS)
    @tools : Gtk::DropDown = Gtk::DropDown.new_from_strings(["Brush", "Transparent eraser", "Anchor"])
    @inks : Gtk::DropDown = Gtk::DropDown.new_from_strings(["x █"])
    @ink_keys = ["x"]
    @glyph = Gtk::Entry.new
    @key = Gtk::Entry.new
    @foreground = Gtk::Entry.new
    @background = Gtk::Entry.new
    @duration = Gtk::Entry.new
    @clip_name = Gtk::Entry.new
    @width = Gtk::Entry.new
    @height = Gtk::Entry.new
    @info = Gtk::Label.new("")
    @names = ["idle"]
    @layouts = {} of String => Pango::Layout

    def initialize
      @key.text, @glyph.text, @foreground.text = "x", "█", "#e6b566"
      @background.placeholder_text = "Transparent background"
      @clip_name.placeholder_text = "Animation name"
      [@key, @glyph, @foreground, @background, @duration, @clip_name, @width, @height].each { |e| e.width_chars = 7; e.hexpand = true }
      row(@animations, @directions, action("Add direction") { edit("Add direction") { |s| s.animations[@clip].directions[@direction] ||= s.animations[@clip].directions[s.default_direction].map { |f| Core::SpriteFrame.from_yaml(f.to_yaml) } } })
      row(@clip_name, action("Add animation") do
        name = @clip_name.text.strip
        raise Core::DocumentError.new("Use a unique lowercase animation ID") unless Core::Analysis::ID.matches?(name) && !sprite.not_nil!.animations.has_key?(name)
        edit("Add animation") { |s| s.animations[name] = Core::Animation.new({s.default_direction => [Core::SpriteFrame.new(Array.new(s.height, " " * s.width))]}) }
        @clip = name
        load(@document)
      end, action("Play / Pause") { @playing = !@playing; @time = 0_i64 })
      row(action("Previous") { @index = Math.max(0, @index - 1); update_info }, action("Next") { @index = Math.min(frames.size - 1, @index + 1); update_info }, action("Duplicate") { edit("Duplicate frame") { |s| list = selected_frames(s); list.insert(@index + 1, Core::SpriteFrame.from_yaml(list[@index].to_yaml)) }; @index += 1; update_info }, action("Delete") { edit("Delete frame") { |s| list = selected_frames(s); raise Core::DocumentError.new("Keep at least one frame") if list.size == 1; list.delete_at(@index) } }, action("Earlier") { reorder(-1) }, action("Later") { reorder(1) })
      row(Gtk::Label.new("Duration ms"), @duration, action("Apply duration") { value = @duration.text.to_i; raise Core::DocumentError.new("Duration must be 1–60000") unless (1..60_000).includes?(value); edit("Frame timing") { |s| selected_frames(s)[@index].duration_ms = value } }, action("Loop / Once") { edit("Animation looping") { |s| s.animations[@clip].loop = !s.animations[@clip].loop } })
      row(@inks, Gtk::Label.new("Key / glyph / foreground / background"))
      row(@key, @glyph, @foreground, @background, action("Set ink") { set_ink })
      row(@tools, Gtk::Label.new("Width / height"), @width, @height, action("Resize") { resize })
      widget.append(@info)
      area.hexpand = true
      area.vexpand = true
      area.set_size_request(320, 240)
      area.draw_func = ->draw(Gtk::DrawingArea, Cairo::Context, Int32, Int32)
      scroll = Gtk::ScrolledWindow.new
      scroll.child = area
      scroll.vexpand = true
      widget.append(scroll)
      drag = Gtk::GestureDrag.new
      origin = {0.0, 0.0}
      drag.drag_begin_signal.connect do |x, y|
        safely do
          origin = {x, y}
          doc = @document.not_nil!
          raise Core::NormalizationRequired.new("Normalize this sprite in Source before visual editing") if doc.sensitive?
          @draft = Core::Sprite.from_yaml(doc.text)
          @revision = doc.revision
          paint(x, y)
        end
      end
      drag.drag_update_signal.connect { |dx, dy| safely { paint(origin[0] + dx, origin[1] + dy) } }
      drag.drag_end_signal.connect do |dx, dy|
        safely do
          paint(origin[0] + dx, origin[1] + dy)
          if draft = @draft
            @document.not_nil!.replace(draft.to_yaml, "Paint sprite", @revision)
            @draft = nil
            on_change.call
          end
        end
      end
      drag.cancel_signal.connect { |_| @draft = nil; area.queue_draw }
      area.add_controller(drag)
      @animations.notify_signal["selected"].connect do
        unless @loading
          @clip = @names[@animations.selected.to_i]? || "idle"
          @index = 0
          update_info
        end
      end
      @directions.notify_signal["selected"].connect do
        unless @loading
          @direction = Core::DIRECTIONS[@directions.selected.to_i]? || "S"
          @index = 0
          update_info
        end
      end
      @inks.notify_signal["selected"].connect { populate_ink unless @loading }
      GLib.timeout_milliseconds(33_u32) do
        now = Time.instant
        @time += (now - @last_tick).total_milliseconds.to_i64 if @playing
        @last_tick = now
        area.queue_draw if @playing && widget.mapped
        true
      end
    end

    private def row(*children : Gtk::Widget)
      box = Gtk::Box.new(:horizontal, 5)
      children.each { |child| box.append(child) }
      widget.append(box)
    end

    private def action(text : String, &block : ->) : Gtk::Button
      button = Gtk::Button.new_with_label(text)
      button.clicked_signal.connect { safely { block.call } }
      button
    end

    private def safely(&)
      yield
    rescue ex
      @draft = nil
      on_error.call(ex)
    end

    def sprite : Core::Sprite?
      @draft || @document.try(&.model).as?(Core::Sprite)
    end

    def load(@document : Core::Document?)
      @draft = nil
      @loading = true
      if s = sprite
        @names = s.animations.keys.sort
        @clip = "idle" unless @names.includes?(@clip)
        @animations.model = Gtk::StringList.new(@names)
        @animations.selected = (@names.index(@clip) || 0).to_u32
        @directions.selected = (Core::DIRECTIONS.index(@direction) || 4).to_u32
        @ink_keys = s.palette.keys.sort
        @inks.model = Gtk::StringList.new(@ink_keys.map { |key| "#{key}  #{s.palette[key].glyph}  #{s.palette[key].foreground}" })
        @inks.selected = (@ink_keys.index(@key.text) || 0).to_u32
        populate_ink
        @width.text, @height.text = s.width.to_s, s.height.to_s
        area.set_size_request(Math.max(500, s.width * 24 + 200), Math.max(240, s.height * 32 + 24))
        update_info
      end
      @loading = false
    end

    def selected_ink : String
      @key.text
    end

    private def populate_ink
      if s = sprite
        if key = @ink_keys[@inks.selected.to_i]?
          ink = s.palette[key]
          @key.text, @glyph.text = key, ink.glyph
          @foreground.text, @background.text = ink.foreground, ink.background || ""
        end
      end
    end

    private def frames : Array(Core::SpriteFrame)
      selected_frames(sprite.not_nil!)
    end

    private def selected_frames(s : Core::Sprite)
      animation = s.animations[@clip]
      animation.directions[@direction]? || animation.directions[s.default_direction]
    end

    private def update_info
      return unless s = sprite
      @index = @index.clamp(0, frames.size - 1)
      @duration.text = frames[@index].duration_ms.to_s
      fallback = s.animations[@clip].directions.has_key?(@direction) ? "" : " (default direction; Add direction to edit separately)"
      @info.text = "Frame #{@index + 1}/#{frames.size} · anchor #{s.anchor_x},#{s.anchor_y} · #{s.animations[@clip].loop ? "loop" : "once"}#{fallback}"
      area.queue_draw
    end

    private def edit(label : String, &block : Core::Sprite ->)
      return unless doc = @document
      doc.edit(label) { |value| block.call(value.as(Core::Sprite)) }
      on_change.call
      update_info
    end

    private def set_ink
      key, glyph, fg, bg = @key.text, @glyph.text, @foreground.text, @background.text
      raise Core::DocumentError.new("Palette key must be one non-space ASCII character") unless key.bytesize == 1 && key[0] >= '!' && key[0] <= '~'
      raise Core::DocumentError.new("Choose an ASCII, box, block or supported text symbol") unless Core::Glyphs.allowed?(glyph)
      raise Core::DocumentError.new("Colors must use #RRGGBB; leave background blank for transparency") unless Core::Analysis::COLOR.matches?(fg) && (bg.empty? || Core::Analysis::COLOR.matches?(bg))
      edit("Set sprite ink") { |s| s.palette[key] = Core::Ink.new(glyph, fg, bg.empty? ? nil : bg) }
    end

    private def resize
      width, height = @width.text.to_i, @height.text.to_i
      raise Core::DocumentError.new("Dimensions must be 1–64") unless (1..64).includes?(width) && (1..64).includes?(height)
      edit("Resize sprite") do |s|
        s.animations.each_value do |animation|
          animation.directions.each_value do |list|
            list.each { |f| f.rows = Array.new(height) { |y| ((f.rows[y]? || "") + " " * width)[0, width] } }
          end
        end
        s.width, s.height = width, height
        s.anchor_x, s.anchor_y = s.anchor_x.clamp(0, width - 1), s.anchor_y.clamp(0, height - 1)
      end
    end

    private def reorder(delta : Int32)
      index = @index
      other = index + delta
      return unless other >= 0 && other < frames.size
      edit("Reorder frames") { |s| list = selected_frames(s); list.swap(index, other) }
      @index = other
      update_info
    end

    def paint(px : Float64, py : Float64)
      return unless s = @draft
      x, y = ((px - 8) / 24).floor.to_i, ((py - 8) / 32).floor.to_i
      return unless x >= 0 && y >= 0 && x < s.width && y < s.height
      if @tools.selected == 2
        s.anchor_x, s.anchor_y = x, y
      else
        key = @tools.selected == 1 ? " " : @key.text
        raise Core::DocumentError.new("Set the palette ink before painting") unless key == " " || s.palette.has_key?(key)
        frame = selected_frames(s)[@index]
        bytes = frame.rows[y].to_slice.dup
        bytes[x] = key.byte_at(0)
        frame.rows[y] = String.new(bytes)
      end
      area.queue_draw
    end

    private def color(cr : Cairo::Context, hex : String)
      WorldMythCairo.set_source_rgb(cr, hex[1, 2].to_i(16) / 255.0, hex[3, 2].to_i(16) / 255.0, hex[5, 2].to_i(16) / 255.0)
    end

    private def ink(cr : Cairo::Context, key : String, x : Float64, y : Float64, w : Float64, h : Float64, s : Core::Sprite)
      item = s.palette[key]?
      color(cr, item.try(&.background) || "#26332f")
      WorldMythCairo.rectangle(cr, x, y, w - 1, h - 1)
      WorldMythCairo.fill(cr)
      return unless item
      color(cr, item.foreground)
      layout = @layouts[item.glyph] ||= begin
        result = PangoCairo.create_layout(cr)
        result.font_description = Pango::FontDescription.from_string("Monospace 14")
        result.set_text(item.glyph, -1)
        result
      end
      WorldMythCairo.move_to(cr, x + 3, y + 2)
      PangoCairo.show_layout(cr, layout)
    end

    private def draw(area : Gtk::DrawingArea, cr : Cairo::Context, width : Int32, height : Int32) : Nil
      color(cr, "#101816")
      WorldMythCairo.paint(cr)
      return unless s = sprite
      frames[@index].rows.each_with_index do |row, y|
        row.each_char_with_index { |key, x| ink(cr, key.to_s, 8.0 + x * 24, 8.0 + y * 32, 24.0, 32.0, s) }
      end
      color(cr, "#f2cb7a")
      WorldMythCairo.rectangle(cr, 8.0 + s.anchor_x * 24, 8.0 + s.anchor_y * 32, 23.0, 31.0)
      WorldMythCairo.stroke(cr)
      preview = @playing ? s.frame(@clip, @direction, @time) : frames[@index]
      preview.rows.each_with_index do |row, y|
        row.each_char_with_index { |key, x| ink(cr, key.to_s, 40.0 + s.width * 24 + x * 14, 8.0 + y * 28, 14.0, 28.0, s) }
      end
    rescue ex
      STDERR.puts "Sprite editor: #{ex.message}"
    end
  end
end
