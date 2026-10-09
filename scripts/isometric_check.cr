require "../spec/support/spatial_fixture"
require "../src/world_myth/gui/window"

class IsometricCheck
  @workspace : WorldMyth::GUI::Window
  @root : String
  @stage = 0
  @failed = false
  @sprite_before = ""
  @ticks = 0

  def initialize(@app : Adw::Application)
    @root = File.join(Dir.tempdir, "world-myth-isometric-check-#{Random::Secure.hex(6)}")
    project = SpatialFixture.create(@root)
    ENV["XDG_CONFIG_HOME"] = File.join(@root, ".test-config")
    @workspace = WorldMyth::GUI::Window.new(app)
    @workspace.present(project.root)
    @workspace.open_document("regions/heartlands/maps/village.yaml")
    @workspace.canvas.viewport.zoom_at(0.6, 0.0, 0.0)
    GLib.timeout_milliseconds(400_u32) { step }
  end

  def assert(condition : Bool, message : String)
    raise message unless condition
    puts "PASS #{message}"
  end

  def find(widget : Gtk::Widget, name : String) : Gtk::Button?
    return widget if widget.is_a?(Gtk::Button) && widget.label == name
    child = widget.first_child
    while child
      if found = find(child, name)
        return found
      end
      child = child.next_sibling
    end
    nil
  end

  def click(name : String)
    (find(@workspace.window, name) || raise "Missing button #{name}").clicked_signal.emit
    raise "Unexpected dialog after #{name}" if @workspace.window.visible_dialog
  end

  def step : Bool
    @ticks += 1
    raise "Isometric check timed out" if @ticks > 80
    w = @workspace
    case @stage
    when 0
      assert(w.window.mapped, "isometric native window mapped")
      assert(w.analysis.not_nil!.valid?, "layered example validates")
      w.canvas.camera.roofs = false
      w.select_surface("upper-floor")
      w.canvas.widget.queue_draw
    when 1
      return true unless w.capture("/tmp/world-myth-isometric-scene.png")
      assert(w.canvas.frame.not_nil!.cells.any? { |c| c.hit.try(&.surface) == "upper-floor" }, "upper floor rendered")
      puts "METRIC example_frame_ms=#{w.canvas.last_frame_ms.round(2)} candidates=#{w.canvas.visible_cells}"
      w.create_surface("test-floor", "floor", 5)
      assert(w.canvas.camera.active_surface == "test-floor", "new surface becomes active")
      canvas = w.canvas
      canvas.layer, canvas.value = "terrain", "floor"
      canvas.begin_gesture(*canvas.project_cell(12, 8))
      canvas.finish_gesture(*canvas.project_cell(12, 8))
      assert(w.current.not_nil!.model.as(WorldMyth::Core::Map).surface("test-floor").symbol(12, 8) == "d", "paint empty elevated surface")
      click("Undo")
      assert(w.current.not_nil!.model.as(WorldMyth::Core::Map).surface("test-floor").symbol(12, 8) == " ", "undo elevated paint")
      click("Redo")
      click("Save")
      w.open_document("sprites/actor.ulf.yaml")
    when 2
      assert(w.sprite_editor.widget.mapped, "sprite editor opens natively")
      @sprite_before = w.current.not_nil!.text
      controllers = w.sprite_editor.area.observe_controllers
      gesture : Gtk::GestureDrag? = nil
      controllers.n_items.times { |i| gesture = controllers.item(i).as(Gtk::GestureDrag) if controllers.item(i).is_a?(Gtk::GestureDrag) }
      # Set ink through the actual GTK button, then emit native gesture signals.
      click("Set ink")
      key = w.sprite_editor.selected_ink
      gesture.not_nil!.drag_begin_signal.emit(20.0, 20.0)
      gesture.not_nil!.drag_end_signal.emit(24.0, 0.0)
      assert(w.current.not_nil!.model.as(WorldMyth::Core::Sprite).animations["idle"].directions["S"][0].rows[0].starts_with?(key * 2), "sprite gesture paints model")
      click("Undo")
      assert(!w.current.not_nil!.model.as(WorldMyth::Core::Sprite).animations["idle"].directions["S"][0].rows[0].starts_with?(key * 2), "sprite stroke undo")
      click("Redo")
      click("Duplicate")
      assert(w.current.not_nil!.model.as(WorldMyth::Core::Sprite).animations["idle"].directions["S"].size == 3, "duplicate animation frame")
      click("Later")
      click("Play / Pause")
    when 3
      return true unless w.capture("/tmp/world-myth-isometric-sprite.png")
      click("Save")
      assert(WorldMyth::Core::Project.new(@root).analyze.valid?, "sprite edits save and reload validly")
      puts "ISOMETRIC_CHECK_OK"
      @app.quit
      return false
    end
    @stage += 1
    true
  rescue ex
    STDERR.puts "ISOMETRIC_CHECK_FAILED stage=#{@stage}: #{ex.message}\n#{ex.backtrace.join('\n')}"
    @workspace.capture("/tmp/world-myth-isometric-failure.png") rescue nil
    @failed = true
    @app.quit
    false
  end

  def finish
    FileUtils.rm_r(@root)
    @failed ? 1 : 0
  end
end

app = Adw::Application.new("io.github.worldmyth.IsometricCheck", Gio::ApplicationFlags::NonUnique)
check : IsometricCheck? = nil
app.activate_signal.connect { check = IsometricCheck.new(app) }
app.run([] of String)
exit(check.try(&.finish) || 1)
