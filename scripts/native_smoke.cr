require "../src/world_myth/gui/native"

app = Adw::Application.new("io.github.worldmyth.Smoke", Gio::ApplicationFlags::None)
app.activate_signal.connect do
  window = Adw::ApplicationWindow.new(app)
  window.title = "World Myth — Native toolchain check"
  window.set_default_size(640, 400)
  box = Gtk::Box.new(Gtk::Orientation::Vertical, 8)
  area = Gtk::DrawingArea.new
  area.content_height = 160
  area.draw_func = ->(_area : Gtk::DrawingArea, cr : Cairo::Context, w : Int32, h : Int32) {
    WorldMythCairo.set_source_rgb(cr, 0.05, 0.08, 0.07)
    WorldMythCairo.paint(cr)
    WorldMythCairo.set_source_rgb(cr, 0.55, 0.8, 0.4)
    WorldMythCairo.move_to(cr, 24.0, 24.0)
    layout = PangoCairo.create_layout(cr)
    layout.font_description = Pango::FontDescription.from_string("Monospace 22")
    layout.set_text(". ♣ # @ 界 — Crystal + GTK4", -1)
    PangoCairo.show_layout(cr, layout)
    puts "DRAW_OK #{w}x#{h}"
  }
  click = Gtk::GestureClick.new
  click.pressed_signal.connect { |_, x, y| puts "CLICK_OK #{x},#{y}" }
  area.add_controller(click)
  box.append(area)
  buffer = GtkSource::Buffer.new(nil)
  buffer.text = "schema_version: 1\nname: Native GTK4\n"
  buffer.language = GtkSource::LanguageManager.default.language("yaml")
  view = GtkSource::View.new_with_buffer(buffer)
  view.show_line_numbers = true
  box.append(view)
  button = Gtk::Button.new_with_label("Test native folder dialog")
  button.clicked_signal.connect do
    dialog = Gtk::FileDialog.new
    WorldMyth::GUI::NativeDialogs.select_folder(dialog, window) do |result|
      puts "FOLDER_OK #{dialog.select_folder_finish(result).try(&.path)}"
    rescue ex
      puts "DIALOG #{ex.message}"
    end
  end
  box.append(button)
  window.content = box
  window.present
  puts "WINDOW_OK"
  GLib.timeout_seconds(2_u32) do
    snapshot = Gtk::Snapshot.new
    Gtk::WidgetPaintable.new(window).snapshot(snapshot, window.width.to_f64, window.height.to_f64)
    if node = snapshot.to_node
      window.renderer.not_nil!.render_texture(node, nil).save_to_png("/tmp/world-myth-native-smoke.png")
      puts "CAPTURE_OK"
    end
    false
  end
end
exit(app.run)
