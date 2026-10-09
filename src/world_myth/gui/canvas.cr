require "./native"
require "../core"

module WorldMyth::GUI
  class Canvas
    getter widget = Gtk::DrawingArea.new
    getter viewport = Core::Viewport.new
    getter selected = {0, 0}
    getter last_frame_ms = 0.0
    getter visible_cells = 0
    property layer = "terrain"
    property tool = "Brush"
    property value = "grass"
    property font = "Monospace"
    property show_grid = true
    property show_terrain = true
    property show_collision = true
    property show_objects = true
    property on_change : Proc(Nil) = -> { }
    property on_selection : Proc(Nil) = -> { }
    property on_select : Proc(Int32, Int32, Nil) = ->(x : Int32, y : Int32) { }
    property on_error : Proc(Exception, Nil) = ->(ex : Exception) { STDERR.puts ex.message }
    @document : Core::Document?
    @analysis : Core::Analysis?
    @map_key = ""
    @stroke : Core::Stroke?
    @layouts = {} of String => Pango::Layout
    @space = false
    @panning = false
    @origin = {0.0, 0.0}
    @pan_origin = {0.0, 0.0}
    @mouse = {0.0, 0.0}

    def initialize
      widget.hexpand = true
      widget.vexpand = true
      widget.focusable = true
      widget.draw_func = ->draw(Gtk::DrawingArea, Cairo::Context, Int32, Int32)
      drag = Gtk::GestureDrag.new
      drag.button = 0_u32
      drag.drag_begin_signal.connect do |x, y|
        begin_gesture(x, y, drag.current_button)
      end
      drag.drag_update_signal.connect { |x, y| update_gesture(@origin[0] + x, @origin[1] + y) }
      drag.drag_end_signal.connect { |x, y| finish_gesture(@origin[0] + x, @origin[1] + y) }
      drag.cancel_signal.connect do |_|
        @stroke = nil
        @panning = false
        widget.queue_draw
      end
      widget.add_controller(drag)
      motion = Gtk::EventControllerMotion.new
      motion.motion_signal.connect do |x, y|
        @mouse = {x, y}
        cx, cy = viewport.cell(x, y)
        on_select.call(cx, cy)
      end
      widget.add_controller(motion)
      scroll = Gtk::EventControllerScroll.new(Gtk::EventControllerScrollFlags::BothAxes)
      scroll.scroll_signal.connect do |dx, dy|
        if scroll.current_event_state.control_mask?
          viewport.zoom_at(dy < 0 ? 1.15 : 1.0 / 1.15, @mouse[0], @mouse[1])
          @layouts.clear
        else
          viewport.offset_x -= dx * 36
          viewport.offset_y -= dy * 36
        end
        widget.queue_draw
        true
      end
      widget.add_controller(scroll)
      keys = Gtk::EventControllerKey.new
      keys.key_pressed_signal.connect do |key, _, _|
        @space = true if key == 32_u32
        key == 32_u32
      end
      keys.key_released_signal.connect { |key, _, _| @space = false if key == 32_u32 }
      widget.add_controller(keys)
    end

    def load(document : Core::Document?, analysis : Core::Analysis?, reset = false)
      @stroke = nil
      @document = document
      @analysis = analysis
      @map_key = analysis.try(&.paths.find { |key, path| key.starts_with?("map:") && path == document.try(&.path) }).try(&.[0].sub("map:", "")) || ""
      if reset
        viewport.offset_x = 24.0
        viewport.offset_y = 24.0
        @selected = {0, 0}
      end
      @layouts.clear
      widget.queue_draw
    end

    def map : Core::Map?
      @stroke.try(&.map) || @document.try(&.model).as?(Core::Map)
    end

    def zoom(factor : Float64)
      viewport.zoom_at(factor, widget.width / 2.0, widget.height / 2.0)
      @layouts.clear
      widget.queue_draw
    end

    def begin_gesture(x : Float64, y : Float64, button = 1_u32)
      widget.grab_focus
      @origin = {x, y}
      @panning = button == 2 || @space
      @pan_origin = {viewport.offset_x, viewport.offset_y}
      return if @panning
      cx, cy = viewport.cell(x, y)
      return unless map.try(&.inside?(cx, cy))
      @selected = {cx, cy}
      on_select.call(cx, cy)
      on_selection.call
      unless tool == "Select"
        raise Core::DocumentError.new("No palette entries for this layer. Define a world object in entities/objects first.") if layer == "objects" && value.empty? && tool != "Eraser"
        if document = @document
          @stroke = Core::Stroke.new(document, layer, value, tool == "Eraser" || button == 3)
          @stroke.not_nil!.visit(cx, cy)
        end
      end
      widget.queue_draw
    rescue ex
      @stroke = nil
      on_error.call(ex)
    end

    def update_gesture(x : Float64, y : Float64)
      if @panning
        viewport.offset_x = @pan_origin[0] + x - @origin[0]
        viewport.offset_y = @pan_origin[1] + y - @origin[1]
      elsif stroke = @stroke
        cx, cy = viewport.cell(x, y)
        stroke.visit(cx, cy)
        @selected = {cx, cy} if stroke.map.inside?(cx, cy)
      end
      widget.queue_draw
    rescue ex
      @stroke = nil
      on_error.call(ex)
    end

    def finish_gesture(x : Float64, y : Float64)
      update_gesture(x, y)
      if stroke = @stroke
        stroke.commit
        @stroke = nil
        on_change.call if stroke.changed
      end
      @panning = false
      widget.queue_draw
    rescue ex
      @stroke = nil
      on_error.call(ex)
    end

    private def rgb(cr : Cairo::Context, color : String, alpha = 1.0)
      value = Core::Analysis::COLOR.matches?(color) ? color : "#ff66aa"
      WorldMythCairo.set_source_rgba(cr, value[1, 2].to_i(16) / 255.0, value[3, 2].to_i(16) / 255.0, value[5, 2].to_i(16) / 255.0, alpha)
    end

    private def glyph(cr : Cairo::Context, text : String, color : String, x : Float64, y : Float64, cw : Float64, ch : Float64)
      key = "#{text}:#{font}:#{viewport.zoom}"
      layout = @layouts[key] ||= begin
        item = PangoCairo.create_layout(cr)
        item.font_description = Pango::FontDescription.from_string("#{font} #{(14 * viewport.zoom).round(2)}")
        item.set_text(text, -1)
        item
      end
      width = 0
      height = 0
      LibPango.pango_layout_get_pixel_size(layout, pointerof(width), pointerof(height))
      WorldMythCairo.save(cr)
      WorldMythCairo.rectangle(cr, x, y, cw, ch)
      WorldMythCairo.clip(cr)
      rgb(cr, color)
      WorldMythCairo.move_to(cr, x + (cw - width) / 2, y + (ch - height) / 2)
      PangoCairo.show_layout(cr, layout)
      WorldMythCairo.restore(cr)
    end

    private def draw(area : Gtk::DrawingArea, cr : Cairo::Context, width : Int32, height : Int32) : Nil
      start = Time.instant
      rgb(cr, "#0c1212")
      WorldMythCairo.paint(cr)
      @visible_cells = 0
      return unless current = map
      analysis = @analysis
      return unless catalog = analysis.try(&.catalog)
      cw, ch = viewport.cell_width * viewport.zoom, viewport.cell_height * viewport.zoom
      ox, oy = viewport.offset_x, viewport.offset_y
      x0 = ((-ox / cw).floor.to_i).clamp(0, current.width)
      y0 = ((-oy / ch).floor.to_i).clamp(0, current.height)
      x1 = (((width - ox) / cw).ceil.to_i).clamp(0, current.width)
      y1 = (((height - oy) / ch).ceil.to_i).clamp(0, current.height)
      (y0...y1).each do |y|
        (x0...x1).each do |x|
          @visible_cells += 1
          px, py = ox + x * cw, oy + y * ch
          if tile = catalog.terrain[current.terrain_at(x, y)]?
            if show_terrain
              rgb(cr, tile.background)
              WorldMythCairo.rectangle(cr, px, py, cw, ch)
              WorldMythCairo.fill(cr)
              glyph(cr, tile.glyph, tile.foreground, px, py, cw, ch)
            end
          end
          if show_collision
            collision = current.symbol_at("collision", x, y)
            if collision != "."
              rgb(cr, collision == "#" ? "#d64f56" : "#53bda6", 0.27)
              WorldMythCairo.rectangle(cr, px, py, cw, ch)
              WorldMythCairo.fill(cr)
            end
          end
        end
      end
      if show_objects && analysis
        current.layers.objects.each do |placement|
          next unless placement.x >= x0 && placement.x < x1 && placement.y >= y0 && placement.y < y1
          if entity = analysis.entities[placement.entity]?
            glyph(cr, entity.glyph, entity.foreground, ox + placement.x * cw, oy + placement.y * ch, cw, ch)
          end
        end
        analysis.entities.each_value do |entity|
          if position = entity.position
            next unless analysis.resolve_map(position.map) == @map_key
            next unless position.x >= x0 && position.x < x1 && position.y >= y0 && position.y < y1
            glyph(cr, entity.glyph, entity.foreground, ox + position.x * cw, oy + position.y * ch, cw, ch)
          end
        end
      end
      if show_grid && viewport.zoom >= 0.5
        rgb(cr, "#657570", 0.16)
        WorldMythCairo.set_line_width(cr, 1.0)
        (x0..x1).each do |x|
          WorldMythCairo.move_to(cr, ox + x * cw, oy + y0 * ch)
          WorldMythCairo.line_to(cr, ox + x * cw, oy + y1 * ch)
        end
        (y0..y1).each do |y|
          WorldMythCairo.move_to(cr, ox + x0 * cw, oy + y * ch)
          WorldMythCairo.line_to(cr, ox + x1 * cw, oy + y * ch)
        end
        WorldMythCairo.stroke(cr)
      end
      if current.inside?(*selected)
        rgb(cr, "#f2cb7a")
        WorldMythCairo.set_line_width(cr, 2.0)
        WorldMythCairo.rectangle(cr, ox + selected[0] * cw + 1, oy + selected[1] * ch + 1, cw - 2, ch - 2)
        WorldMythCairo.stroke(cr)
      end
      @last_frame_ms = (Time.instant - start).total_milliseconds
    rescue ex
      STDERR.puts "Canvas: #{ex.message}"
    end
  end
end
