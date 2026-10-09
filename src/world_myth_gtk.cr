require "./world_myth"
require "./world_myth/gui/window"

if ARGV.includes?("--help")
  puts "Usage: world-myth-gtk [world-directory]"
  exit
end
if ARGV.size > 1
  STDERR.puts "Usage: world-myth-gtk [world-directory]"
  exit 2
end
path = ARGV.first?.try { |p| File.expand_path(p) }
app = Adw::Application.new("io.github.worldmyth.Editor", Gio::ApplicationFlags::NonUnique)
workspace : WorldMyth::GUI::Window? = nil
app.activate_signal.connect do
  workspace ||= WorldMyth::GUI::Window.new(app)
  workspace.not_nil!.present(path)
end
exit(app.run([] of String))
