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
    property on_entity_select : Proc(String, Nil) = ->(id : String) { }
    property on_select : Proc(Int32, Int32, Nil) = ->(x : Int32, y : Int32) { }
    property on_error : Proc(Exception, Nil) = ->(ex : Exception) { STDERR.puts ex.message }
    @document : Core::Document?
    @analysis : Core::Analysis?
    @map_key = ""
    @stroke : Core::Stroke?
    @layouts = {} of String => Pango::Layout
    getter camera = Core::SceneCamera.new
    getter frame : Core::GlyphFrame?
    property playing = true
    @renderer : Core::SceneRenderer?
    @time_ms = 0_i64
    @frame_u = 0.0
    @frame_v = 0.0
    @last_tick = Time.instant
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
        cx, cy = screen_cell(x, y)
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
      GLib.timeout_milliseconds(33_u32) do
        now = Time.instant
        @time_ms += (now - @last_tick).total_milliseconds.to_i64 if playing
        @last_tick = now
        widget.queue_draw if playing && widget.mapped && @renderer.try(&.animated)
        true
      end
    end

    def load(document : Core::Document?, analysis : Core::Analysis?, reset = false)
      @stroke = nil
      @document = document
      @analysis = analysis
      @map_key = analysis.try(&.paths.find { |key, path| key.starts_with?("map:") && path == document.try(&.path) }).try(&.[0].sub("map:", "")) || ""
      if reset
        viewport.offset_x = (widget.width > 0 ? widget.width / 2.0 : 300.0)
        viewport.offset_y = 60.0
        @selected = {0, 0}
      end
      @renderer = nil
      @frame = nil
      camera.active_surface = "ground" unless map.try(&.all_surfaces.any? { |s| s.id == camera.active_surface })
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
      if tool == "Select"
        if hit = scene_hit(x, y)
          if entity = hit.entity
            on_entity_select.call(entity)
            return
          end
        end
      end
      cx, cy = screen_cell(x, y)
      return unless map.try(&.inside?(cx, cy))
      @selected = {cx, cy}
      on_select.call(cx, cy)
      on_selection.call
      unless tool == "Select"
        raise Core::DocumentError.new("No palette entries for this layer. Define a world object in entities/objects first.") if layer == "objects" && value.empty? && tool != "Eraser"
        if document = @document
          @stroke = Core::Stroke.new(document, layer, value, tool == "Eraser" || button == 3, camera.active_surface)
          @stroke.not_nil!.visit(cx, cy)
          @renderer = nil
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
        cx, cy = screen_cell(x, y)
        stroke.visit(cx, cy)
        @renderer = nil
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
        item.font_description = Pango::FontDescription.from_string("#{font} #{(cw * 1.2).round(2)}")
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

    def char_width : Float64
      viewport.cell_width * viewport.zoom / 2
    end

    def char_height : Float64
      char_width * 2
    end

    def screen_cell(x : Float64, y : Float64) : Tuple(Int32, Int32)
      if frame = @frame
        if hit = frame.hit(((x - viewport.offset_x) / char_width - @frame_u).floor.to_i, ((y - viewport.offset_y) / char_height - @frame_v).floor.to_i)
          return {hit.x, hit.y} if hit.surface == camera.active_surface
        end
      end
      # Blank cells on a newly created elevated surface must still be paintable.
      level = map.try(&.surface(camera.active_surface).elevation.first?.try(&.split.first.to_f)) || 0.0
      Core::Isometric.cell((x - viewport.offset_x) / char_width, (y - viewport.offset_y) / char_height, level)
    end

    def scene_hit(x : Float64, y : Float64) : Core::Hit?
      return nil unless frame = @frame
      column = ((x - viewport.offset_x) / char_width - @frame_u).floor.to_i
      row = ((y - viewport.offset_y) / char_height - @frame_v).floor.to_i
      return nil unless column >= 0 && row >= 0 && column < frame.width && row < frame.height
      frame.cells[row * frame.width + column].hit
    end

    def project_cell(x : Int32, y : Int32) : Tuple(Float64, Float64)
      z = map.try(&.surface(camera.active_surface).z(x, y)) || 0.0
      p = Core::Isometric.project(x + 0.5, y + 0.5, z)
      {viewport.offset_x + p.u * char_width, viewport.offset_y + p.v * char_height}
    end

    private def draw(area : Gtk::DrawingArea, cr : Cairo::Context, width : Int32, height : Int32) : Nil
      start = Time.instant
      rgb(cr, "#0c1212")
      WorldMythCairo.paint(cr)
      @visible_cells = 0
      return unless current = map
      return unless analysis = @analysis
      return unless analysis.valid?
      @renderer ||= Core::SceneRenderer.new(current, analysis, @map_key)
      camera.u = -viewport.offset_x / char_width
      camera.v = -viewport.offset_y / char_height
      camera.terrain, camera.objects, camera.collision, camera.grid = show_terrain, show_objects, show_collision, show_grid
      cols, rows = (width / char_width).ceil.to_i, (height / char_height).ceil.to_i
      frame = @renderer.not_nil!.render(cols, rows, camera, @time_ms)
      @frame = frame
      @frame_u, @frame_v = camera.u, camera.v
      @visible_cells = @renderer.not_nil!.last_candidates
      frame.cells.each_with_index do |cell, index|
        x, y = (index % cols) * char_width, (index // cols) * char_height
        rgb(cr, cell.background)
        WorldMythCairo.rectangle(cr, x, y, char_width + 0.5, char_height + 0.5)
        WorldMythCairo.fill(cr)
        glyph(cr, cell.glyph, cell.foreground, x, y, char_width, char_height) unless cell.glyph == " "
        if hit = frame.surface_hits[index]
          if {hit.x, hit.y} == selected
            rgb(cr, "#f2cb7a", 0.25)
            WorldMythCairo.rectangle(cr, x, y, char_width, char_height)
            WorldMythCairo.fill(cr)
          end
        end
      end
      @last_frame_ms = (Time.instant - start).total_milliseconds
    rescue ex
      STDERR.puts "Canvas: #{ex.message}"
    end
  end
end
