require "./canvas"
require "./preferences"

module WorldMyth::GUI
  class Window
    getter window : Adw::ApplicationWindow
    getter canvas = Canvas.new
    getter project : Core::Project?
    getter current : Core::Document?
    getter analysis : Core::Analysis?
    getter source_buffer = GtkSource::Buffer.new(nil)
    getter source_view : GtkSource::View
    getter diagnostics = [] of Core::Diagnostic
    getter busy = false
    @preferences = Preferences.load
    @root_stack = Gtk::Stack.new
    @editor_stack = Gtk::Stack.new
    @explorer = Gtk::Box.new(:vertical, 2)
    @inspector = Gtk::Box.new(:vertical, 10)
    @diagnostics_box = Gtk::Box.new(:vertical, 2)
    @status = Gtk::Label.new("Ready")
    @coordinates = Gtk::Label.new("X: —  Y: —")
    @git_label = Gtk::Label.new("")
    @title = Gtk::Label.new("World Myth")
    @document_title = Gtk::Label.new("Choose a document")
    @palette : Gtk::DropDown = Gtk::DropDown.new_from_strings(["grass"])
    @layer : Gtk::DropDown = Gtk::DropDown.new_from_strings(["Terrain", "Objects", "Collision"])
    @tool : Gtk::DropDown = Gtk::DropDown.new_from_strings(["Brush", "Eraser", "Select"])
    @palette_values = ["grass"]
    @left_pane = Gtk::Paned.new(:horizontal)
    @right_pane = Gtk::Paned.new(:horizontal)
    @diagnostic_pane = Gtk::Paned.new(:vertical)
    @source_pending = false
    @syncing_source = false
    @source_tick = false
    @closing = false
    @refreshing = false
    @normalizing = false
    @buttons = {} of String => Gtk::Button

    def initialize(@app : Adw::Application)
      @window = Adw::ApplicationWindow.new(app)
      @source_view = GtkSource::View.new_with_buffer(source_buffer)
      window.title = "World Myth"
      window.set_default_size(@preferences.width.clamp(900, 3000), @preferences.height.clamp(600, 2000))
      canvas.viewport.cell_width = @preferences.cell_width.clamp(10.0, 64.0)
      canvas.viewport.cell_height = @preferences.cell_height.clamp(12.0, 80.0)
      canvas.font = @preferences.font
      canvas.show_grid = @preferences.grid
      canvas.show_terrain = @preferences.terrain
      canvas.show_collision = @preferences.collision
      canvas.show_objects = @preferences.objects
      build_ui
      connect_signals
      install_actions
      window.close_request_signal.connect do
        if @closing
          false
        else
          guard_unsaved do
            persist_preferences
            @closing = true
            window.close
          end
          true
        end
      end
      window.notify_signal["is-active"].connect do
        refresh_external if window.is_active? && project && !@refreshing
      end
    end

    def present(path : String? = nil)
      window.present
      open_project(path) if path
    end

    def button(label : String, &block : ->) : Gtk::Button
      result = Gtk::Button.new_with_label(label)
      result.clicked_signal.connect { safely { block.call } }
      result
    end

    def label(text : String, style : String? = nil) : Gtk::Label
      item = Gtk::Label.new(text)
      item.xalign = 0.0_f32
      item.wrap = true
      item.add_css_class(style) if style
      item
    end

    def scrolled(child : Gtk::Widget, width = -1, height = -1) : Gtk::ScrolledWindow
      scroll = Gtk::ScrolledWindow.new
      scroll.child = child
      scroll.hexpand = true
      scroll.vexpand = true
      scroll.set_size_request(width, height)
      scroll
    end

    private def margins(widget : Gtk::Widget, amount = 12)
      widget.margin_start = amount
      widget.margin_end = amount
      widget.margin_top = amount
      widget.margin_bottom = amount
    end

    private def build_ui
      shell = Gtk::Box.new(:vertical, 0)
      header = Adw::HeaderBar.new
      @title.add_css_class("heading")
      header.title_widget = @title
      {"New", "Open", "Save", "Undo", "Redo", "Validate", "Build", "Preferences"}.each do |name|
        control = button(name) { dispatch(name) }
        @buttons[name] = control
        if {"New", "Open", "Save"}.includes?(name)
          header.pack_start(control)
        else
          header.pack_end(control)
        end
      end
      @buttons["Build"].add_css_class("suggested-action")
      shell.append(header)
      @root_stack.hexpand = true
      @root_stack.vexpand = true
      build_welcome
      build_workspace
      shell.append(@root_stack)
      footer = Gtk::Box.new(:horizontal, 16)
      margins(footer, 8)
      @status.hexpand = true
      @status.xalign = 0.0_f32
      @status.ellipsize = :end
      footer.append(@status)
      footer.append(@git_label)
      footer.append(@coordinates)
      shell.append(footer)
      window.content = shell
      update_status
    end

    private def build_welcome
      welcome = Gtk::Box.new(:vertical, 18)
      welcome.halign = :center
      welcome.valign = :center
      margins(welcome, 32)
      title = Gtk::Label.new("World Myth")
      title.add_css_class("title-1")
      welcome.append(title)
      welcome.append(Gtk::Label.new("A home for worlds, maps, and the stories between them."))
      row = Gtk::Box.new(:horizontal, 12)
      create = button("Create World") { choose_new }
      create.add_css_class("suggested-action")
      row.append(create)
      row.append(button("Open World") { choose_open })
      row.halign = :center
      welcome.append(row)
      @preferences.recent.select { |p| File.file?(File.join(p, "world.yaml")) }.first(5).each do |path|
        welcome.append(button("Open #{File.basename(path)}") { open_project(path) })
      end
      @root_stack.add_named(welcome, "welcome")
    end

    private def build_workspace
      explorer_panel = Gtk::Box.new(:vertical, 8)
      margins(@explorer)
      explorer_panel.append(label("  WORLD EXPLORER", "heading"))
      explorer_panel.append(scrolled(@explorer, 180))
      @left_pane.start_child = explorer_panel
      @left_pane.position = @preferences.left_panel
      @left_pane.resize_start_child = false
      @left_pane.shrink_start_child = false
      @left_pane.end_child = @right_pane
      @right_pane.position = @preferences.center_panel
      @right_pane.resize_end_child = false
      @right_pane.shrink_end_child = false
      margins(@inspector)
      @right_pane.end_child = scrolled(@inspector, 240)
      editor = Gtk::Box.new(:vertical, 0)
      modebar = Gtk::Box.new(:horizontal, 8)
      margins(modebar, 8)
      @document_title.hexpand = true
      @document_title.xalign = 0.0_f32
      @document_title.ellipsize = :middle
      modebar.append(@document_title)
      modebar.append(button("Map") { show_map })
      modebar.append(button("Source") { show_source })
      modebar.append(button("Normalize YAML…") { normalize_current })
      editor.append(modebar)
      @editor_stack.vexpand = true
      @editor_stack.hexpand = true
      map_box = Gtk::Box.new(:vertical, 0)
      toolbar = Gtk::Box.new(:horizontal, 6)
      margins(toolbar, 8)
      toolbar.append(@layer)
      toolbar.append(@tool)
      @palette.hexpand = true
      @palette.enable_search = true
      toolbar.append(@palette)
      toolbar.append(button("−") { canvas.zoom(1.0 / 1.2) })
      toolbar.append(button("+") { canvas.zoom(1.2) })
      map_box.append(toolbar)
      visibility = Gtk::Box.new(:horizontal, 10)
      margins(visibility, 6)
      { {"Grid", canvas.show_grid}, {"Terrain", canvas.show_terrain}, {"Objects", canvas.show_objects}, {"Collision", canvas.show_collision} }.each do |name, active|
        check = Gtk::CheckButton.new_with_label(name)
        check.active = active
        check.toggled_signal.connect do
          case name
          when "Grid"      then canvas.show_grid = check.active?
          when "Terrain"   then canvas.show_terrain = check.active?
          when "Objects"   then canvas.show_objects = check.active?
          when "Collision" then canvas.show_collision = check.active?
          end
          canvas.widget.queue_draw
        end
        visibility.append(check)
      end
      map_box.append(visibility)
      map_box.append(canvas.widget)
      hint = label("  Paint: drag  ·  Pan: middle-drag / Space-drag  ·  Zoom: Ctrl-scroll", "dim-label")
      hint.margin_bottom = 6
      map_box.append(hint)
      @editor_stack.add_named(map_box, "map")
      source_view.monospace = true
      source_view.show_line_numbers = true
      source_view.auto_indent = true
      source_view.tab_width = 2_u32
      source_view.insert_spaces_instead_of_tabs = true
      source_view.hexpand = true
      source_view.vexpand = true
      source_view.left_margin = 8
      source_view.right_margin = 8
      source_buffer.enable_undo = false
      if scheme = GtkSource::StyleSchemeManager.default.scheme("Adwaita-dark")
        source_buffer.style_scheme = scheme
      end
      @editor_stack.add_named(scrolled(source_view), "source")
      editor.append(@editor_stack)
      @right_pane.start_child = editor
      @diagnostic_pane.start_child = @left_pane
      @diagnostic_pane.resize_end_child = false
      diagnostics_panel = Gtk::Box.new(:vertical, 6)
      diagnostics_panel.append(label("  DIAGNOSTICS", "heading"))
      margins(@diagnostics_box, 6)
      @diagnostics_box.append(label("Validate the world to check files and references.", "dim-label"))
      diagnostics_panel.append(scrolled(@diagnostics_box, -1, 90))
      @diagnostic_pane.end_child = diagnostics_panel
      @diagnostic_pane.position = @preferences.height - 220
      @root_stack.add_named(@diagnostic_pane, "workspace")
    end

    private def connect_signals
      @layer.notify_signal["selected"].connect { update_palette }
      @tool.notify_signal["selected"].connect { canvas.tool = {"Brush", "Eraser", "Select"}[@tool.selected.clamp(0_u32, 2_u32).to_i] }
      @palette.notify_signal["selected"].connect { canvas.value = @palette_values[@palette.selected.to_i64]? || "" }
      canvas.on_change = -> { refresh_document; nil }
      canvas.on_selection = -> { rebuild_inspector; nil }
      canvas.on_select = ->(x : Int32, y : Int32) {
        @coordinates.text = "X: #{x}  Y: #{y}"
        nil
      }
      canvas.on_error = ->(ex : Exception) {
        if ex.is_a?(Core::NormalizationRequired)
          normalize_current
        else
          error_dialog(ex.message || "Edit failed")
        end
        nil
      }
      source_buffer.changed_signal.connect do
        unless @syncing_source
          @source_pending = true
          @status.text = "Modified • source"
          window.title = "World Myth • Modified"
          unless @source_tick
            @source_tick = true
            GLib.timeout_milliseconds(300_u32) do
              @source_tick = false
              safely { flush_source }
              false
            end
          end
        end
      end
    end

    private def install_actions
      {"save" => {"Save", "<Control>s"}, "undo" => {"Undo", "<Control>z"}, "redo" => {"Redo", "<Control><Shift>z"}, "open" => {"Open", "<Control>o"}, "new" => {"New", "<Control>n"}, "validate" => {"Validate", "F5"}, "build" => {"Build", "F6"}}.each do |name, config|
        action = Gio::SimpleAction.new(name, nil)
        action.activate_signal.connect { |_| safely { dispatch(config[0]) } }
        window.add_action(action)
        @app.set_accels_for_action("win.#{name}", [config[1]])
      end
    end

    def dispatch(name : String)
      case name
      when "New"         then guard_unsaved { choose_new }
      when "Open"        then guard_unsaved { choose_open }
      when "Save"        then save_all
      when "Undo"        then undo
      when "Redo"        then redo
      when "Validate"    then validate_world
      when "Build"       then build_world
      when "Preferences" then preferences_dialog
      end
    end

    def open_project(path : String)
      safely do
        candidate = Core::Project.new(path)
        candidate_analysis = candidate.analyze
        @project = candidate
        @analysis = candidate_analysis
        @current = nil
        @preferences.recent.delete(candidate.root)
        @preferences.recent.unshift(candidate.root)
        @preferences.recent = @preferences.recent.first(8)
        @root_stack.visible_child_name = "workspace"
        rebuild_explorer
        display_diagnostics(candidate_analysis.diagnostics)
        first = candidate_analysis.paths.find { |key, _| key.starts_with?("map:") }.try(&.[1]) || "world.yaml"
        open_document(first)
        refresh_git
      end
    end

    def open_document(path : String)
      flush_source
      return unless doc = project.try(&.documents[path]?)
      @current = doc
      refresh_document(true)
      if doc.model.is_a?(Core::Map) && analysis.try(&.editable_map?(path))
        @editor_stack.visible_child_name = "map"
      else
        show_source
      end
    end

    private def rebuild_explorer
      clear(@explorer)
      return unless p = project
      {"World" => ["world.yaml", "terrain.yaml"], "Regions & maps" => p.documents.keys.select(&.starts_with?("regions/")), "Entities" => p.documents.keys.select(&.starts_with?("entities/")), "Lore" => p.documents.keys.select(&.starts_with?("lore/"))}.each do |heading, paths|
        section = label(heading, "heading")
        section.margin_top = 10
        @explorer.append(section)
        ordered = if heading == "Regions & maps"
                    paths.sort_by { |path| {path.split('/')[1], Core::Source.kind(path) == "region" ? 0 : 1, path} }
                  else
                    paths
                  end
        ordered.each do |path|
          next unless doc = p.documents[path]?
          value = doc.model
          name = case value
                 when Core::Map, Core::Region, Core::Entity, Core::World then value.name
                 else                                                         File.basename(path)
                 end
          prefix = value.is_a?(Core::Map) ? "    ▦ " : value.is_a?(Core::Entity) ? "◇ " : ""
          item = button("#{prefix}#{name}#{doc.dirty? ? " •" : ""}") { open_document(path) }
          item.add_css_class("flat")
          item.child = label("#{prefix}#{name}#{doc.dirty? ? " •" : ""}")
          item.tooltip_text = path
          item.halign = :fill
          @explorer.append(item)
        end
      end
    end

    def refresh_document(reset = false)
      return unless p = project
      @analysis = p.analyze
      display_diagnostics(@analysis.not_nil!.diagnostics)
      if doc = current
        sync_source
        @document_title.text = doc.path + (doc.dirty? ? " •" : "")
        canvas.load(analysis.not_nil!.editable_map?(doc.path) ? doc : nil, analysis, reset)
        update_palette
        rebuild_inspector
      end
      rebuild_explorer
      update_status
    end

    private def sync_source
      return unless doc = current
      @syncing_source = true
      source_buffer.text = doc.text unless source_buffer.text == doc.text
      source_buffer.language = GtkSource::LanguageManager.default.language(Core::Source.kind(doc.path) == "lore" ? "markdown" : "yaml")
      @syncing_source = false
    end

    def flush_source
      return unless @source_pending
      @source_pending = false
      current.try(&.replace(source_buffer.text, "Edit source"))
      refresh_document
    end

    private def show_source
      flush_source
      @editor_stack.visible_child_name = "source"
      source_view.grab_focus
    end

    private def show_map
      flush_source
      if doc = current
        if analysis.try(&.editable_map?(doc.path))
          @editor_stack.visible_child_name = "map"
          canvas.widget.grab_focus
        else
          display_diagnostics(analysis.try(&.diagnostics) || [] of Core::Diagnostic)
          @status.text = "Fix map errors in Source before visual editing."
        end
      end
    end

    private def update_palette
      index = @layer.selected.clamp(0_u32, 2_u32).to_i
      canvas.layer = {"terrain", "objects", "collision"}[index]
      labels = [] of String
      @palette_values = [] of String
      case canvas.layer
      when "terrain"
        if map = current.try(&.model).as?(Core::Map)
          map.legend.values.uniq.sort.each do |id|
            tile = analysis.try(&.catalog).try(&.terrain[id]?)
            @palette_values << id
            labels << "#{tile.try(&.glyph) || "?"}  #{id}"
          end
        end
      when "objects"
        analysis.try(&.entities.values.select { |e| e.type == "object" }.sort_by(&.id).each do |e|
          @palette_values << e.id
          labels << "#{e.glyph}  #{e.name}"
        end)
      when "collision"
        @palette_values = ["#", "+", "."]
        labels = ["Blocked", "Passable", "Inherit terrain"]
      end
      previous = canvas.value
      @palette.model = Gtk::StringList.new(labels.empty? ? ["No entries"] : labels)
      @palette.selected = (@palette_values.index(previous) || 0).to_u32
      canvas.value = @palette_values[@palette.selected.to_i64]? || ""
    end

    private def rebuild_inspector
      clear(@inspector)
      @inspector.append(label("INSPECTOR", "heading"))
      return unless doc = current
      case model = doc.model
      when Core::Map
        @inspector.append(label(model.name, "title-3"))
        @inspector.append(label("#{model.width} × #{model.height} cells\nID: #{model.id}", "dim-label"))
        x, y = canvas.selected
        @inspector.append(label("Selected cell: #{x}, #{y}"))
        if model.inside?(x, y) && analysis.try(&.editable_map?(doc.path))
          @inspector.append(label("Terrain: #{model.terrain_at(x, y)}\nCollision: #{model.symbol_at("collision", x, y)}"))
          model.layers.objects.select { |o| o.x == x && o.y == y }.each do |o|
            @inspector.append(label("Object: #{o.entity}"))
          end
          @inspector.append(button("Apply palette to selection") do
            begin
              stroke = Core::Stroke.new(doc, canvas.layer, canvas.value, canvas.tool == "Eraser")
              stroke.visit(x, y)
              stroke.commit
              refresh_document
            rescue ex : Core::NormalizationRequired
              normalize_current
            end
          end)
        end
        @inspector.append(label("Choose a layer and palette entry. Collision overlays: red blocks, green permits movement.", "dim-label"))
      when Core::Entity
        entity_inspector(doc, model)
      else
        @inspector.append(label(doc.path, "title-3"))
        @inspector.append(label(doc.error || "Edit this document in the source view.", "dim-label"))
      end
      @inspector.append(Gtk::Separator.new(:horizontal))
      @inspector.append(button("Reload from disk…") { reload_current })
      @inspector.append(button("Save a copy…") { save_copy })
    end

    private def entry(box : Gtk::Box, caption : String, value : String) : Gtk::Entry
      box.append(label(caption, "dim-label"))
      field = Gtk::Entry.new
      field.text = value
      box.append(field)
      field
    end

    private def entity_inspector(doc : Core::Document, entity : Core::Entity)
      @inspector.append(label("#{entity.type.upcase} · #{entity.id}", "heading"))
      name = entry(@inspector, "Name", entity.name)
      tags = entry(@inspector, "Tags (comma separated)", entity.tags.join(", "))
      map = entry(@inspector, "Map (blank removes position)", entity.position.try(&.map) || "")
      x = entry(@inspector, "X", (entity.position.try(&.x) || 0).to_s)
      y = entry(@inspector, "Y", (entity.position.try(&.y) || 0).to_s)
      @inspector.append(label("Properties (YAML scalar values)", "dim-label"))
      props = Gtk::TextView.new
      props.monospace = true
      props.buffer.text = entity.properties.to_yaml
      @inspector.append(scrolled(props, -1, 90))
      @inspector.append(button("Apply entity changes") do
        if doc.sensitive?
          normalize_current
        else
          doc.edit("Edit entity") do |value|
            updated = value.as(Core::Entity)
            updated.name = name.text
            updated.tags = tags.text.split(',').map(&.strip).reject(&.empty?)
            updated.position = map.text.strip.empty? ? nil : Core::Position.new(map.text.strip, x.text.to_i, y.text.to_i)
            updated.properties = Hash(String, YAML::Any).from_yaml(props.buffer.text)
            sources = project.not_nil!.snapshot
            sources[doc.path] = updated.to_yaml
            errors = Core::Analysis.new(sources).diagnostics.select { |d| d.path == doc.path && d.severity.error? }
            raise Core::DocumentError.new(errors.join('\n')) unless errors.empty?
          end
          refresh_document
        end
      end)
    end

    def undo
      flush_source
      current.try(&.undo)
      refresh_document
    end

    def redo
      flush_source
      current.try(&.redo)
      refresh_document
    end

    def save_all : Bool
      flush_source
      project.try(&.save_all)
      refresh_document
      refresh_git
      @status.text = "Saved"
      true
    rescue ex
      error_dialog(ex.message || "Save failed")
      false
    end

    def display_diagnostics(items : Array(Core::Diagnostic))
      @diagnostics = items
      clear(@diagnostics_box)
      if items.empty?
        @diagnostics_box.append(label("No errors. World is valid.", "success"))
      else
        items.each do |diagnostic|
          row = button(diagnostic.to_s.gsub('\n', ' ')) do
            open_document(diagnostic.path)
            show_source
            if line = diagnostic.line
              iter = source_buffer.iter_at_line((line - 1).clamp(0, source_buffer.line_count - 1))
              source_buffer.place_cursor(iter)
              source_view.scroll_to_iter(iter, 0.15, true, 0.0, 0.5)
            end
          end
          row.add_css_class("flat")
          caption = label(diagnostic.to_s.gsub('\n', ' '))
          caption.wrap = false
          caption.ellipsize = :end
          caption.width_chars = 1
          row.child = caption
          row.tooltip_text = diagnostic.to_s
          @diagnostics_box.append(row)
        end
      end
    end

    def validate_world
      flush_source
      return if busy
      return unless p = project
      sources = p.snapshot
      @busy = true
      @status.text = "Validating…"
      update_buttons
      spawn do
        result = Core::Analysis.new(sources)
        GLib.idle_add do
          @busy = false
          if project == p
            display_diagnostics(result.diagnostics)
            @status.text = p.snapshot == sources ? (result.valid? ? "World is valid" : "Validation found #{result.diagnostics.size} diagnostics") : "Validation finished; documents have changed since it started"
          end
          update_buttons
          false
        end
      rescue ex
        worker_error(ex)
      end
    end

    def build_world
      flush_source
      return if busy
      return unless p = project
      if p.dirty?
        ask("Save before building?", "Compilation uses saved world files.", {"cancel" => "Cancel", "save" => "Save All & Build"}) do |response|
          build_world if response == "save" && save_all
        end
        return
      end
      @busy = true
      @status.text = "Compiling world…"
      update_buttons
      spawn do
        output = Core::Compiler.new(p.root).build
        GLib.idle_add do
          @busy = false
          @status.text = "Built #{output}/world.sqlite" if project == p
          update_buttons
          false
        end
      rescue ex
        worker_error(ex)
      end
    end

    private def worker_error(ex : Exception)
      message = ex.message || ex.class.name
      GLib.idle_add do
        @busy = false
        update_buttons
        @status.text = "Operation failed"
        error_dialog(message)
        false
      end
    end

    private def update_buttons
      @buttons.each do |name, control|
        control.sensitive = case name
                            when "New", "Open", "Preferences" then !busy
                            when "Undo"                       then !!current.try { |d| !d.history.empty? }
                            when "Redo"                       then !!current.try { |d| !d.future.empty? }
                            when "Validate", "Build"          then !!project && !busy
                            else                                   !!project
                            end
      end
    end

    private def update_status
      title = analysis.try(&.world).try(&.name) || "World Myth"
      dirty = project.try(&.dirty?) || @source_pending
      @title.text = title + (dirty ? " •" : "")
      window.title = "World Myth — #{title}#{dirty ? " • Modified" : ""}"
      @status.text = dirty ? "Modified • Save to write world files" : "Ready"
      update_buttons
    end

    private def refresh_git
      return unless p = project
      spawn do
        status = Core::GitStatus.read(p.root)
        GLib.idle_add do
          if project == p
            @git_label.text = "#{status.branch} · #{status.modified.size} changed"
            @git_label.tooltip_text = status.modified.join('\n')
          end
          false
        end
      end
    end

    private def refresh_external
      return unless p = project
      @refreshing = true
      flush_source
      conflicts = p.refresh_clean
      refresh_document
      refresh_git
      @status.text = "External changes: #{conflicts.join(", ")} — reload or save a copy" unless conflicts.empty?
    rescue ex
      @status.text = ex.message || "Could not refresh project"
    ensure
      @refreshing = false
    end

    private def guard_unsaved(&block : ->)
      flush_source
      if project.try(&.dirty?)
        ask("Unsaved changes", "Save your world before continuing?", {"cancel" => "Cancel", "discard" => "Discard", "save" => "Save All"}) do |response|
          block.call if response == "discard" || (response == "save" && save_all)
        end
      else
        block.call
      end
    end

    private def choose_open
      dialog = Gtk::FileDialog.new
      dialog.title = "Open World — select its directory"
      NativeDialogs.select_folder(dialog, window) do |result|
        open_project(dialog.select_folder_finish(result).path.not_nil!.to_s)
      rescue ex : Gtk::DialogError::Dismissed | Gtk::DialogError::Cancelled
        @status.text = "Open cancelled"
      rescue ex
        error_dialog(ex.message || "Open failed")
      end
    end

    private def choose_new
      dialog = Gtk::FileDialog.new
      dialog.title = "Create World — choose a new directory name"
      dialog.initial_name = "new-world"
      dialog.accept_label = "Create World"
      NativeDialogs.save(dialog, window) do |result|
        path = dialog.save_finish(result).path.not_nil!.to_s
        Core::Project.create(path, File.basename(path))
        open_project(path)
      rescue ex : Gtk::DialogError::Dismissed | Gtk::DialogError::Cancelled
        @status.text = "Create cancelled"
      rescue ex
        error_dialog(ex.message || "Create failed")
      end
    end

    private def normalize_current
      flush_source
      return if @normalizing
      return unless doc = current
      raise Core::DocumentError.new("Fix source errors before normalization") if doc.error
      normalized = Core::Source.canonical(doc.text)
      @normalizing = true
      dialog = Adw::AlertDialog.new("Normalize YAML?", "Comments and YAML anchors will be removed. Review the normalized document below. This change can be undone.")
      buffer = Gtk::TextBuffer.new(nil)
      buffer.text = normalized
      view = Gtk::TextView.new_with_buffer(buffer)
      view.editable = false
      view.monospace = true
      scroll = scrolled(view, 600, 320)
      dialog.extra_child = scroll
      dialog.add_response("cancel", "Cancel")
      dialog.add_response("normalize", "Normalize")
      dialog.close_response = "cancel"
      dialog.default_response = "cancel"
      revision = doc.revision
      dialog.response_signal.connect do |response|
        @normalizing = false
        if response == "normalize"
          safely do
            doc.replace(normalized, "Normalize YAML (comments removed)", revision)
            refresh_document
          end
        end
      end
      dialog.present(window)
    rescue ex
      @normalizing = false
      error_dialog(ex.message || "Normalization failed")
    end

    private def reload_current
      return unless doc = current
      ask("Reload #{File.basename(doc.path)}?", "Unsaved changes and this document's undo history will be discarded.", {"cancel" => "Cancel", "reload" => "Reload"}) do |response|
        if response == "reload"
          safely do
            @source_pending = false
            doc.reload(project.not_nil!.root)
            refresh_document
          end
        end
      end
    end

    private def save_copy
      flush_source
      return unless doc = current
      dialog = Gtk::FileDialog.new
      dialog.initial_name = "copy-#{File.basename(doc.path)}"
      NativeDialogs.save(dialog, window) do |result|
        path = dialog.save_finish(result).path.not_nil!.to_s
        raise Core::ConflictError.new("Choose a new file for the copy") if File.exists?(path)
        Core::Persistence.write(path, doc.text)
        @status.text = "Saved copy: #{path}"
      rescue ex : Gtk::DialogError::Dismissed | Gtk::DialogError::Cancelled
        @status.text = "Save copy cancelled"
      rescue ex
        error_dialog(ex.message || "Save copy failed")
      end
    end

    private def preferences_dialog
      dialog = Adw::AlertDialog.new("Map preferences", "Typography and cell dimensions are independent of logical coordinates.")
      fields = Gtk::Box.new(:vertical, 8)
      font = entry(fields, "Font family", canvas.font)
      width = entry(fields, "Cell width (10–64 px)", canvas.viewport.cell_width.to_s)
      height = entry(fields, "Cell height (12–80 px)", canvas.viewport.cell_height.to_s)
      dialog.extra_child = fields
      dialog.add_response("cancel", "Cancel")
      dialog.add_response("apply", "Apply")
      dialog.close_response = "cancel"
      dialog.response_signal.connect do |response|
        if response == "apply"
          safely do
            w, h = width.text.to_f64, height.text.to_f64
            raise ArgumentError.new("Cell size is outside the allowed range") unless (10.0..64.0).includes?(w) && (12.0..80.0).includes?(h)
            raise ArgumentError.new("Choose a font family") if font.text.strip.empty?
            canvas.font = font.text.strip
            canvas.viewport.cell_width = w
            canvas.viewport.cell_height = h
            refresh_document
            persist_preferences
          end
        end
      end
      dialog.present(window)
    end

    private def persist_preferences
      @preferences.width = window.width
      @preferences.height = window.height
      @preferences.left_panel = @left_pane.position
      @preferences.center_panel = @right_pane.position
      @preferences.cell_width = canvas.viewport.cell_width
      @preferences.cell_height = canvas.viewport.cell_height
      @preferences.font = canvas.font
      @preferences.grid = canvas.show_grid
      @preferences.terrain = canvas.show_terrain
      @preferences.collision = canvas.show_collision
      @preferences.objects = canvas.show_objects
      @preferences.save
    rescue ex
      STDERR.puts "Preferences: #{ex.message}"
    end

    private def ask(title : String, body : String, responses : Hash(String, String), &block : String ->)
      dialog = Adw::AlertDialog.new(title, body)
      responses.each { |id, caption| dialog.add_response(id, caption) }
      dialog.close_response = "cancel"
      dialog.default_response = "cancel"
      dialog.response_signal.connect { |response| block.call(response) }
      dialog.present(window)
    end

    private def error_dialog(message : String)
      dialog = Adw::AlertDialog.new("World Myth", message)
      dialog.add_response("close", "Close")
      dialog.present(window)
    end

    private def safely(&)
      yield
    rescue ex
      error_dialog(ex.message || ex.class.name)
    end

    private def clear(box : Gtk::Box)
      while child = box.first_child
        box.remove(child)
      end
    end

    def capture(path : String)
      snapshot = Gtk::Snapshot.new
      Gtk::WidgetPaintable.new(window).snapshot(snapshot, window.width.to_f64, window.height.to_f64)
      if node = snapshot.to_node
        window.renderer.not_nil!.render_texture(node, nil).save_to_png(path)
      end
    end
  end
end
