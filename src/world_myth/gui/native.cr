require "libadwaita"
GICrystal.require("GtkSource", "5")

# Cairo's GIR describes opaque handles but omits the drawing API.
# These signatures come from cairo.h; no separate context ownership is introduced.
@[Link("cairo")]
lib WorldMythCairo
  fun set_source_rgb = cairo_set_source_rgb(cr : Void*, r : Float64, g : Float64, b : Float64)
  fun set_source_rgba = cairo_set_source_rgba(cr : Void*, r : Float64, g : Float64, b : Float64, a : Float64)
  fun paint = cairo_paint(cr : Void*)
  fun rectangle = cairo_rectangle(cr : Void*, x : Float64, y : Float64, w : Float64, h : Float64)
  fun fill = cairo_fill(cr : Void*)
  fun stroke = cairo_stroke(cr : Void*)
  fun move_to = cairo_move_to(cr : Void*, x : Float64, y : Float64)
  fun line_to = cairo_line_to(cr : Void*, x : Float64, y : Float64)
  fun set_line_width = cairo_set_line_width(cr : Void*, width : Float64)
  fun save = cairo_save(cr : Void*)
  fun restore = cairo_restore(cr : Void*)
  fun clip = cairo_clip(cr : Void*)
end

module WorldMyth::GUI::NativeDialogs
  # GI-Crystal 0.26.0's AsyncPatternArgPlan boxes but does not register callbacks.
  # Keep the box rooted until the asynchronous native dialog completes.
  alias Completion = Proc(Gio::AsyncResult, Nil)

  CALLBACK = ->(_sender : Void*, result : Void*, data : Void*) {
    begin
      Box(Completion).unbox(data).call(Gio::AbstractAsyncResult.new(result, GICrystal::Transfer::None))
    rescue ex
      STDERR.puts "Native dialog callback: #{ex.message}"
    ensure
      GICrystal::ClosureDataManager.deregister(data)
    end
  }

  def self.select_folder(dialog : Gtk::FileDialog, parent : Gtk::Window, &block : Gio::AsyncResult -> Nil)
    data = GICrystal::ClosureDataManager.register(Box(Completion).box(block))
    LibGtk.gtk_file_dialog_select_folder(dialog, parent, Pointer(Void).null, CALLBACK.pointer, data)
  end

  def self.save(dialog : Gtk::FileDialog, parent : Gtk::Window, &block : Gio::AsyncResult -> Nil)
    data = GICrystal::ClosureDataManager.register(Box(Completion).box(block))
    LibGtk.gtk_file_dialog_save(dialog, parent, Pointer(Void).null, CALLBACK.pointer, data)
  end
end
