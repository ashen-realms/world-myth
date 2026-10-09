# Integration check: runs real GTK widgets on a display, using only disposable worlds.
require "../src/world_myth"
require "../src/world_myth/gui/window"

class GUICheck
  @stage = 0
  @ticks = 0
  @original = ""
  @root : String
  @workspace : WorldMyth::GUI::Window
  @failure = false

  def initialize(@app : Adw::Application)
    @root = File.join(Dir.tempdir, "world-myth-gui-check-#{Random::Secure.hex(8)}")
    Dir.mkdir(@root)
    ENV["XDG_CONFIG_HOME"] = File.join(@root, "config")
    source = File.expand_path("../examples/example-world", __DIR__)
    FileUtils.cp_r(source, File.join(@root, "world"))
    @workspace = WorldMyth::GUI::Window.new(app)
    @workspace.present(File.join(@root, "world"))
    GLib.timeout_milliseconds(450_u32) { step }
  end

  def assert(condition : Bool, message : String)
    raise message unless condition
    puts "PASS #{message}"
  end

  def find_button(widget : Gtk::Widget, caption : String) : Gtk::Button?
    if widget.is_a?(Gtk::Button) && widget.label == caption
      return widget
    end
    child = widget.first_child
    while child
      if found = find_button(child, caption)
        return found
      end
      child = child.next_sibling
    end
    nil
  end

  def entries(widget : Gtk::Widget) : Array(Gtk::Entry)
    values = [] of Gtk::Entry
    values << widget if widget.is_a?(Gtk::Entry)
    child = widget.first_child
    while child
      values.concat(entries(child))
      child = child.next_sibling
    end
    values
  end

  def click(caption : String, parent : Gtk::Widget = @workspace.window)
    found = find_button(parent, caption) || raise "Missing button: #{caption}"
    found.clicked_signal.emit
  end

  def paint(value : String, erase = false)
    canvas = @workspace.canvas
    canvas.layer = "terrain"
    canvas.value = value
    canvas.tool = erase ? "Eraser" : "Brush"
    v = canvas.viewport
    canvas.begin_gesture(*canvas.project_cell(2, 2))
    canvas.finish_gesture(*canvas.project_cell(6, 2))
  end

  def step : Bool
    @ticks += 1
    raise "GUI check timed out" if @ticks > 100
    w = @workspace
    case @stage
    when 0
      assert(w.window.mapped, "native window is mapped")
      assert(w.analysis.not_nil!.valid?, "example opens in GUI")
      w.capture("/tmp/world-myth-editor.png")
      paint("water")
      assert(w.current.not_nil!.model.as(WorldMyth::Core::Map).terrain_at(4, 2) == "water", "canvas stroke interpolates cells")
    when 1
      click("Undo")
      assert(w.current.not_nil!.model.as(WorldMyth::Core::Map).terrain_at(4, 2) != "water", "native Undo button changes model")
      click("Redo")
      assert(w.current.not_nil!.model.as(WorldMyth::Core::Map).terrain_at(4, 2) == "water", "native Redo button changes model")
      paint("water", true)
      assert(w.current.not_nil!.model.as(WorldMyth::Core::Map).terrain_at(4, 2) == "grass", "eraser restores default terrain")
      v = w.canvas.viewport
      previous = v.offset_x
      w.canvas.begin_gesture(100.0, 100.0, 2_u32)
      w.canvas.finish_gesture(130.0, 140.0)
      assert(v.offset_x == previous + 30, "pan changes viewport")
      w.canvas.zoom(1.2)
      assert(v.zoom > 1, "zoom changes viewport")
      click("Save")
      assert(!w.project.not_nil!.dirty?, "Save writes and clears modified state")
      w.open_project(File.join(@root, "world"))
    when 2
      click("Source")
      @original = w.current.not_nil!.text
      w.source_buffer.text = "layers: [\n"
      w.flush_source
      click("Validate")
    when 3
      return true if w.busy
      assert(w.diagnostics.any? { |d| d.code == "yaml" }, "malformed source appears in GUI diagnostics")
      w.source_buffer.text = @original
      w.flush_source
      w.source_buffer.text = "# hand-authored note\n" + @original
      w.flush_source
      click("Normalize YAML…")
    when 4
      GC.collect
      dialog = w.window.visible_dialog || raise "Missing normalization dialog"
      assert(dialog.is_a?(Adw::AlertDialog), "normalization requires a native confirmation with preview")
      click("Normalize", dialog)
    when 5
      assert(!w.current.not_nil!.sensitive?, "accepted normalization enables visual editing")
      click("Undo")
      assert(w.current.not_nil!.text.includes?("# hand-authored note"), "undo restores comments")
      click("Redo")
      w.open_document("entities/npcs/ulf.yaml")
    when 6
      name = entries(w.window).find { |e| e.text == "Ulf" } || raise "Missing entity name inspector"
      name.text = "Ulf the Smith"
      click("Apply entity changes")
      assert(w.current.not_nil!.model.as(WorldMyth::Core::Entity).name == "Ulf the Smith", "entity inspector edits shared model")
      click("Save")
      click("Build")
    when 7
      return true if w.busy
      manifest = JSON.parse(File.read(File.join(@root, "world/dist/manifest.json")))
      assert(manifest["world_id"] == "eldoria", "GUI Build produces runtime artifact")
      w.open_document("regions/heartlands/maps/meadow.yaml")
      doc = w.current.not_nil!
      large = WorldMyth::Core::Map.from_yaml(WorldMyth::Core::Project.map_template("meadow", "Large Map", 256, 256))
      doc.replace(large.to_yaml)
      w.refresh_document
      click("Map")
    when 8
      assert(w.canvas.visible_cells > 0 && w.canvas.visible_cells < 65_536, "256×256 canvas culls offscreen cells")
      puts "METRIC visible_cells=#{w.canvas.visible_cells} frame_ms=#{w.canvas.last_frame_ms.round(2)}"
      started = Time.instant
      paint("forest")
      puts "METRIC stroke_commit_ms=#{(Time.instant - started).total_milliseconds.round(2)}"
      w.capture("/tmp/world-myth-large-map.png")
      w.window.close
    when 9
      GC.collect
      dialog = w.window.visible_dialog || raise "Missing unsaved changes dialog"
      click("Cancel", dialog)
    when 10
      assert(w.window.visible? && w.project.not_nil!.dirty?, "Cancel close preserves unsaved changes")
      click("Save")
      w.window.close
      puts "GUI_CHECK_OK"
      @app.quit
      return false
    end
    @stage += 1
    true
  rescue ex
    STDERR.puts "GUI_CHECK_FAILED stage=#{@stage}: #{ex.message}\n#{ex.backtrace.join('\n')}"
    @workspace.capture("/tmp/world-myth-gui-failure.png") rescue nil
    @failure = true
    @app.quit
    false
  end

  def finish : Int32
    FileUtils.rm_r(@root)
    @failure ? 1 : 0
  end
end

app = Adw::Application.new("io.github.worldmyth.GUICheck", Gio::ApplicationFlags::NonUnique)
check : GUICheck? = nil
app.activate_signal.connect { check = GUICheck.new(app) }
app.run([] of String)
exit(check.try(&.finish) || 1)
