# Real X11 input integration check (XTest), isolated to a disposable project.
require "../src/world_myth"
require "../src/world_myth/gui/window"

@[Link("X11")]
lib CheckX11
  fun open = XOpenDisplay(name : UInt8*) : Void*
  fun root = XDefaultRootWindow(display : Void*) : UInt64
  fun translate = XTranslateCoordinates(display : Void*, from : UInt64, to : UInt64, x : Int32, y : Int32, ox : Int32*, oy : Int32*, child : UInt64*) : Int32
  fun focus = XSetInputFocus(display : Void*, window : UInt64, revert : Int32, time : UInt64) : Int32
  fun flush = XFlush(display : Void*) : Int32
  fun keysym = XStringToKeysym(name : UInt8*) : UInt64
  fun keycode = XKeysymToKeycode(display : Void*, symbol : UInt64) : UInt8
  fun close = XCloseDisplay(display : Void*) : Int32
end

@[Link("Xtst")]
lib CheckXTest
  fun motion = XTestFakeMotionEvent(display : Void*, screen : Int32, x : Int32, y : Int32, delay : UInt64) : Int32
  fun button = XTestFakeButtonEvent(display : Void*, button : UInt32, pressed : Int32, delay : UInt64) : Int32
  fun key = XTestFakeKeyEvent(display : Void*, keycode : UInt32, pressed : Int32, delay : UInt64) : Int32
end

@[Link("gtk-4")]
lib CheckGdkX11
  fun xid = gdk_x11_surface_get_xid(surface : Void*) : UInt64
end

class InputCheck
  @stage = 0
  @display : Pointer(Void)
  @workspace : WorldMyth::GUI::Window
  @directory : String
  @position = {0, 0}
  @failed = false
  @old_pan = 0.0
  @drag_delta = {0, 0}
  @old_zoom = 1.0
  @wait_ticks = 0

  def initialize(@app : Adw::Application)
    @directory = File.join(Dir.tempdir, "world-myth-input-#{Random::Secure.hex(8)}")
    p = WorldMyth::Core::Project.create(@directory, "Input Check")
    ENV["XDG_CONFIG_HOME"] = File.join(@directory, ".test-config")
    @workspace = WorldMyth::GUI::Window.new(@app)
    @workspace.present(p.root)
    @display = CheckX11.open(Pointer(UInt8).null)
    raise "No X11 display" if @display.null?
    Gtk::FileChooserDialog.g_type
    GLib.timeout_milliseconds(220_u32) { step }
  end

  def assert(condition : Bool, message : String)
    raise message unless condition
    puts "PASS #{message}"
  end

  def motion(x : Int32, y : Int32)
    CheckXTest.motion(@display, -1, x, y, 0_u64)
    CheckX11.flush(@display)
  end

  def button(button : UInt32, pressed : Bool)
    CheckXTest.button(@display, button, pressed ? 1 : 0, 0_u64)
    CheckX11.flush(@display)
  end

  def key(name : String, pressed : Bool)
    code = CheckX11.keycode(@display, CheckX11.keysym(name)).to_u32
    CheckXTest.key(@display, code, pressed ? 1 : 0, 0_u64)
    CheckX11.flush(@display)
  end

  def shortcut(name : String, shift = false)
    key("Control_L", true)
    key("Shift_L", true) if shift
    key(name, true)
    key(name, false)
    key("Shift_L", false) if shift
    key("Control_L", false)
  end

  def chooser : Gtk::FileChooserDialog
    windows = Gtk::Window.toplevels
    windows.n_items.times do |index|
      if dialog = windows.item(index).as?(Gtk::FileChooserDialog)
        return dialog if dialog.visible?
      end
    end
    raise "Native file chooser unavailable; run this check in a private D-Bus session with GTK_USE_PORTAL=0"
  end

  def step : Bool
    w = @workspace
    canvas = w.canvas
    case @stage
    when 0
      xid = CheckGdkX11.xid(w.window.surface.not_nil!)
      CheckX11.focus(@display, xid, 2, 0_u64)
      dx, dy = 0, 0
      child = 0_u64
      CheckX11.translate(@display, xid, CheckX11.root(@display), 0, 0, pointerof(dx), pointerof(dy), pointerof(child))
      point = LibGraphene::Point.new(x: 0_f32, y: 0_f32)
      translated = LibGraphene::Point.new
      LibGtk.gtk_widget_compute_point(canvas.widget, w.window, pointerof(point), pointerof(translated))
      v = canvas.viewport
      px, py = canvas.project_cell(2, 2)
      ex, ey = canvas.project_cell(6, 2)
      @drag_delta = {(ex - px).to_i, (ey - py).to_i}
      @position = {dx + translated.x.to_i + px.to_i, dy + translated.y.to_i + py.to_i}
      canvas.value = "forest"
      motion(*@position)
      button(1_u32, true)
    when 1
      motion(@position[0] + @drag_delta[0], @position[1] + @drag_delta[1])
    when 2
      button(1_u32, false)
    when 3
      assert(w.current.not_nil!.model.as(WorldMyth::Core::Map).terrain_at(4, 2) == "forest", "real mouse drag paints terrain")
      shortcut("z")
    when 4
      assert(w.current.not_nil!.model.as(WorldMyth::Core::Map).terrain_at(4, 2) == "grass", "Ctrl+Z undoes mouse stroke")
      shortcut("z", true)
    when 5
      assert(w.current.not_nil!.model.as(WorldMyth::Core::Map).terrain_at(4, 2) == "forest", "Ctrl+Shift+Z redoes mouse stroke")
      @old_pan = canvas.viewport.offset_x
      button(2_u32, true)
    when 6
      motion(@position[0] + @drag_delta[0] + 45, @position[1] + @drag_delta[1] + 35)
    when 7
      button(2_u32, false)
    when 8
      assert((canvas.viewport.offset_x - @old_pan - 45).abs < 2, "real middle-button drag pans")
      @old_zoom = canvas.viewport.zoom
      key("Control_L", true)
      button(4_u32, true)
      button(4_u32, false)
      key("Control_L", false)
    when 9
      assert(canvas.viewport.zoom > @old_zoom, "real Ctrl-scroll zooms")
      shortcut("s")
    when 10
      assert(!w.project.not_nil!.dirty?, "Ctrl+S saves")
      w.open_document("world.yaml")
      w.source_buffer.text = w.source_buffer.text + "\n# native edit\n"
      w.flush_source
      w.source_view.grab_focus
      shortcut("z")
    when 11
      assert(!w.current.not_nil!.text.includes?("# native edit"), "Ctrl+Z in source editor uses shared history")
      shortcut("n")
    when 12
      chooser.current_folder = Gio::File.new_for_path(File.dirname(@directory))
      chooser.current_name = File.basename(@directory) + "-new"
    when 13
      GC.collect
      chooser.response(Gtk::ResponseType::Accept.value)
    when 14
      unless File.file?(File.join(@directory + "-new", "world.yaml"))
        @wait_ticks += 1
        return true if @wait_ticks < 15
      end
      assert(File.file?(File.join(@directory + "-new", "world.yaml")), "Create World native dialog creates a valid project")
      assert(w.project.not_nil!.root == @directory + "-new", "new project opens in workspace")
      @wait_ticks = 0
      shortcut("o")
    when 15
      chooser.current_folder = Gio::File.new_for_path(@directory)
    when 16
      GC.collect
      chooser.response(Gtk::ResponseType::Accept.value)
    when 17
      unless w.project.not_nil!.root == @directory
        @wait_ticks += 1
        return true if @wait_ticks < 15
      end
      assert(w.project.not_nil!.root == @directory, "Open World native dialog loads selected project")
      puts "INPUT_CHECK_OK"
      @app.quit
      return false
    end
    @stage += 1
    true
  rescue ex
    STDERR.puts "INPUT_CHECK_FAILED stage=#{@stage}: #{ex.message}"
    @workspace.capture("/tmp/world-myth-input-failure.png") rescue nil
    @failed = true
    @app.quit
    false
  end

  def finish
    # Never leave modifiers held after a failed test.
    {"Control_L", "Shift_L"}.each { |name| key(name, false) }
    {1_u32, 2_u32}.each { |b| button(b, false) }
    CheckX11.close(@display)
    FileUtils.rm_r(@directory)
    FileUtils.rm_r(@directory + "-new") if Dir.exists?(@directory + "-new")
    @failed ? 1 : 0
  end
end

abort "Run with GDK_BACKEND=x11" unless ENV["GDK_BACKEND"]? == "x11"
app = Adw::Application.new("io.github.worldmyth.InputCheck", Gio::ApplicationFlags::NonUnique)
check : InputCheck? = nil
app.activate_signal.connect { check = InputCheck.new(app) }
app.run([] of String)
exit(check.try(&.finish) || 1)
