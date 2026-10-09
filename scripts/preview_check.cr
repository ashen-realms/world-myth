# Real GTK button -> Kitty -> headless CLI integration, using a disposable world.
require "../src/world_myth"
require "../src/world_myth/gui/window"

class PreviewCheck
  @root : String
  @workspace : WorldMyth::GUI::Window
  @stage = 0
  @ticks = 0
  @failed = false
  @socket = ""
  @snapshots = [] of String
  @before : Array(String)
  @original : String

  def initialize(@app : Adw::Application)
    @root = File.join(Dir.tempdir, "world myth preview #{Random::Secure.hex(6)}")
    Dir.mkdir(@root, 0o700)
    ENV["XDG_CONFIG_HOME"] = File.join(@root, "config")
    ENV["KITTY_CONFIG_DIRECTORY"] = File.join(@root, "kitty")
    Dir.mkdir(ENV["KITTY_CONFIG_DIRECTORY"])
    # Remote control is enabled only for this test's isolated Kitty instance.
    File.write(File.join(ENV["KITTY_CONFIG_DIRECTORY"], "kitty.conf"), "allow_remote_control socket-only\nlisten_on unix:#{@root}/control\n")
    project = WorldMyth::Core::Project.create(File.join(@root, "world"), "Preview Check")
    @original = File.read(File.join(project.root, "regions/heartlands/maps/meadow.yaml"))
    @before = Dir.glob(File.join(Dir.tempdir, "world-myth-preview-*.json"))
    @workspace = WorldMyth::GUI::Window.new(@app)
    @workspace.present(project.root)
    GLib.timeout_milliseconds(300_u32) { step }
  end

  def find_button(widget : Gtk::Widget) : Gtk::Button?
    return widget if widget.is_a?(Gtk::Button) && widget.label == "Preview"
    child = widget.first_child
    while child
      if found = find_button(child)
        return found
      end
      child = child.next_sibling
    end
    nil
  end

  def remote(args : Array(String)) : String
    output = IO::Memory.new
    errors = IO::Memory.new
    status = Process.run("kitty", ["@", "--to", "unix:#{@socket}"] + args, output: output, error: errors)
    raise errors.to_s unless status.success?
    output.to_s
  end

  def step : Bool
    @ticks += 1
    raise "Preview timed out at stage #{@stage}" if @ticks > 70
    case @stage
    when 0
      @workspace.source_buffer.text = @original.sub("gggg", "fggg")
      control = find_button(@workspace.window) || raise "Preview button missing"
      raise "Preview button disabled" unless control.sensitive?
      control.clicked_signal.emit
      @stage = 1
    when 1
      return true unless socket = Dir.glob(File.join(@root, "control-*")).first?
      @socket = socket
      text = remote(["get-text"])
      return true unless text.includes?("World Myth | heartlands/meadow")
      raise "Unsaved source not visible in terminal" unless text.lines[1].starts_with?("♣")
      raise "Source was saved by preview" unless File.read(File.join(@root, "world/regions/heartlands/maps/meadow.yaml")) == @original
      @snapshots = Dir.glob(File.join(Dir.tempdir, "world-myth-preview-*.json")) - @before
      raise "Snapshot not created" if @snapshots.empty?
      @workspace.capture("/tmp/world-myth-preview-button.png")
      puts "PASS GTK Preview opens Kitty with unsaved source and unchanged world files"
      remote(["send-text", "\\e[Cs"])
      @stage = 2
    when 2
      text = remote(["get-text"])
      return true unless text.includes?("X:1 Y:1")
      puts "PASS terminal arrow and WASD pan"
      remote(["send-text", "q"])
      @stage = 3
    when 3
      return true if @snapshots.any? { |path| File.exists?(path) }
      puts "PASS Q exits and removes the preview snapshot"
      puts "PREVIEW_CHECK_OK"
      @app.quit
      return false
    end
    true
  rescue ex
    STDERR.puts "PREVIEW_CHECK_FAILED: #{ex.message}\n#{ex.backtrace.join('\n')}"
    remote(["close-window"]) rescue nil unless @socket.empty?
    @failed = true
    @app.quit
    false
  end

  def finish : Int32
    FileUtils.rm_r(@root)
    @failed ? 1 : 0
  end
end

app = Adw::Application.new("io.github.worldmyth.PreviewCheck", Gio::ApplicationFlags::NonUnique)
check : PreviewCheck? = nil
app.activate_signal.connect { check = PreviewCheck.new(app) }
app.run([] of String)
exit(check.try(&.finish) || 1)
