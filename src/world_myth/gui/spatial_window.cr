module WorldMyth::GUI
  class Window
    getter sprite_editor = SpriteEditor.new
    @surfaces : Gtk::DropDown = Gtk::DropDown.new_from_strings(["ground"])
    @surface_ids = ["ground"]
    @loading_surfaces = false
    @scene_clips : Gtk::DropDown = Gtk::DropDown.new_from_strings(["Entity defaults"])
    @clip_names = [""]

    private def spatial_toolbar : Gtk::Widget
      box = Gtk::Box.new(:horizontal, 6)
      box.append(@surfaces)
      box.append(button("Add surface…") { surface_dialog })
      box.append(@scene_clips)
      {"Cut above active" => false, "Roofs" => true, "Animate" => true}.each do |name, active|
        check = Gtk::CheckButton.new_with_label(name)
        check.active = active
        check.toggled_signal.connect do
          case name
          when "Cut above active" then canvas.camera.cutaway = check.active?
          when "Roofs"            then canvas.camera.roofs = check.active?
          when "Animate"          then canvas.playing = check.active?
          end
          canvas.widget.queue_draw
        end
        box.append(check)
      end
      @surfaces.notify_signal["selected"].connect do
        unless @loading_surfaces
          select_surface(@surface_ids[@surfaces.selected.to_i]? || "ground")
        end
      end
      @scene_clips.notify_signal["selected"].connect do
        unless @loading_surfaces
          selected = @clip_names[@scene_clips.selected.to_i]? || ""
          canvas.camera.animation = selected.empty? ? nil : selected
          canvas.widget.queue_draw
        end
      end
      box
    end

    def select_surface(id : String)
      canvas.camera.active_surface = id
      update_surfaces
      canvas.widget.queue_draw
      rebuild_inspector
    end

    private def update_surfaces
      @loading_surfaces = true
      @surface_ids = canvas.map.try(&.all_surfaces.map(&.id)) || ["ground"]
      @surfaces.model = Gtk::StringList.new(@surface_ids)
      @surfaces.selected = (@surface_ids.index(canvas.camera.active_surface) || 0).to_u32
      @clip_names = [""] + (analysis.try(&.sprites.values.flat_map { |s| s.animations.keys }.uniq.sort) || [] of String)
      @scene_clips.model = Gtk::StringList.new(@clip_names.map { |name| name.empty? ? "Entity defaults" : name })
      @scene_clips.selected = (@clip_names.index(canvas.camera.animation || "") || 0).to_u32
      @loading_surfaces = false
    end

    private def fields_dialog(title : String, &block : Gtk::Box, Adw::AlertDialog ->)
      dialog = Adw::AlertDialog.new(title, nil)
      fields = Gtk::Box.new(:vertical, 6)
      dialog.extra_child = fields
      dialog.add_response("cancel", "Cancel")
      dialog.add_response("apply", "Create")
      dialog.close_response = "cancel"
      block.call(fields, dialog)
      dialog.present(window)
    end

    def create_sprite(id : String, name : String, width = 5, height = 5)
      p = project || raise Core::DocumentError.new("Open a world first")
      raise Core::DocumentError.new("Create a v2 copy first") unless analysis.try(&.world.try(&.schema_version)) == 2
      raise Core::DocumentError.new("Use a lowercase sprite ID and dimensions 1–64") unless Core::Analysis::ID.matches?(id) && (1..64).includes?(width) && (1..64).includes?(height)
      path = "sprites/#{id}.yaml"
      p.add_document(path, Core::Sprite.new(id, name, width, height).to_yaml)
      open_document(path)
    end

    private def new_sprite_dialog
      fields_dialog("Create Unicode sprite") do |fields, dialog|
        id = entry(fields, "ID", "sprite.new")
        name = entry(fields, "Name", "New sprite")
        width = entry(fields, "Width", "5")
        height = entry(fields, "Height", "5")
        dialog.response_signal.connect do |response|
          safely { create_sprite(id.text.strip, name.text, width.text.to_i, height.text.to_i) } if response == "apply"
        end
      end
    end

    def create_surface(id : String, kind : String, height : Int32)
      doc = current || return
      model = doc.model.as?(Core::Map) || raise Core::DocumentError.new("Open a map first")
      raise Core::DocumentError.new("Create a v2 copy first") unless model.schema_version == 2
      raise Core::DocumentError.new("Use a unique surface ID, ground/floor/platform/roof kind and height -64–64") unless Core::Analysis::ID.matches?(id) && !model.all_surfaces.any? { |s| s.id == id } && %w(ground floor platform roof).includes?(kind) && (-64..64).includes?(height)
      raise Core::DocumentError.new("At most 32 surfaces are supported") if model.all_surfaces.size >= 32
      doc.edit("Add surface") { |value| map = value.as(Core::Map); map.surfaces << Core::Surface.blank(id, kind, map.width, map.height, height) }
      canvas.camera.active_surface = id
      refresh_document
    end

    private def surface_dialog
      fields_dialog("Add surface") do |fields, dialog|
        id = entry(fields, "ID", "upper-floor")
        kind = entry(fields, "Kind: floor, platform, roof, ground", "floor")
        height = entry(fields, "Height", "6")
        dialog.response_signal.connect do |response|
          safely { create_surface(id.text.strip, kind.text.strip, height.text.to_i) } if response == "apply"
        end
      end
    end

    private def migrate_dialog
      flush_source
      p = project || return
      snapshot = p.snapshot
      sensitive = snapshot.any? { |path, text| Core::Source.kind(path) != "lore" && Core::Source.sensitive?(text) }
      choose = ->(allow : Bool) do
        dialog = Gtk::FileDialog.new
        dialog.title = "Create v2 copy — choose a new directory"
        dialog.initial_name = File.basename(p.root) + "-v2"
        NativeDialogs.save(dialog, window) do |result|
          safely do
            path = dialog.save_finish(result).path.not_nil!.to_s
            converted = Core::Migration.copy(snapshot, path, allow)
            open_project(converted.root)
          end
        rescue ex : Gtk::DialogError::Dismissed | Gtk::DialogError::Cancelled
        end
      end
      if sensitive
        ask("Normalize YAML in the copy?", "Migration preserves the original world. YAML comments, anchors and formatting in the NEW copy will be removed. Unsaved buffers are included.", {"cancel" => "Cancel", "copy" => "Create normalized copy"}) { |response| choose.call(true) if response == "copy" }
      else
        choose.call(false)
      end
    end

    private def material_inspector(doc : Core::Document, catalog : Core::Catalog)
      @inspector.append(label("Material sprites", "heading"))
      catalog.terrain.keys.sort.each do |id|
        tile = catalog.terrain[id]
        top = entry(@inspector, "#{id}: top sprite", tile.sprite || "")
        side = entry(@inspector, "#{id}: side sprite", tile.side_sprite || "")
        @inspector.append(button("Apply #{id}") do
          doc.edit("Assign material sprites") do |value|
            updated = value.as(Core::Catalog).terrain[id]
            updated.sprite = top.text.strip.empty? ? nil : top.text.strip
            updated.side_sprite = side.text.strip.empty? ? nil : side.text.strip
            sources = project.not_nil!.snapshot
            sources[doc.path] = value.to_yaml
            errors = Core::Analysis.new(sources).diagnostics.select(&.severity.error?)
            raise Core::DocumentError.new(errors.join('\n')) unless errors.empty?
          end
          refresh_document
        end)
      end
    end
  end
end
