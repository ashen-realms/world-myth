module WorldMyth::Core
  class Analysis
    private def validate_spatial
      parsed.each do |path, value|
        if w = world
          error("schema_version", "Document version must match world version #{w.schema_version}", path) unless value.schema_version == w.schema_version
        end
        if value.schema_version == 1
          uses_v2 = case value
                    when Map     then !value.surfaces.empty? || !value.walls.empty? || !value.layers.elevation.empty? || !value.layers.shapes.empty? || value.layers.objects.any? { |o| o.surface != "ground" || o.facing != "S" }
                    when Entity  then !!value.sprite || !!value.position.try { |p| p.surface != "ground" || p.facing != "S" }
                    when Catalog then value.terrain.values.any? { |t| t.sprite || t.side_sprite }
                    when Sprite  then true
                    else              false
                    end
          error("migration_required", "Create a v2 copy before adding spatial features", path) if uses_v2
        end
      end
      sprites.each do |id, sprite|
        path = paths["sprite:#{id}"]
        unless (1..64).includes?(sprite.width) && (1..64).includes?(sprite.height)
          error("sprite_dimensions", "Sprite dimensions must be 1–64", path)
          next
        end
        error("sprite_anchor", "Anchor must be inside the sprite", path) unless (0...sprite.width).includes?(sprite.anchor_x) && (0...sprite.height).includes?(sprite.anchor_y)
        error("sprite_direction", "Default direction must be one of #{DIRECTIONS.join(", ")}", path) unless DIRECTIONS.includes?(sprite.default_direction)
        error("sprite_animation", "An idle animation is required", path) unless sprite.animations.has_key?("idle")
        sprite.palette.each do |key, ink|
          error("sprite_palette", "Palette keys must be one printable non-space ASCII character", path) unless key.bytesize == 1 && key[0] >= '!' && key[0] <= '~'
          error("sprite_glyph", "Unsupported art character #{ink.glyph.inspect}", path) unless Glyphs.allowed?(ink.glyph)
          error("sprite_color", "Colors must use #RRGGBB", path) unless COLOR.matches?(ink.foreground) && (!ink.background || COLOR.matches?(ink.background.not_nil!))
        end
        sprite.animations.each do |name, animation|
          identifier(name, path)
          error("sprite_direction", "Animation #{name} needs its default direction", path) unless animation.directions.has_key?(sprite.default_direction)
          animation.directions.each do |direction, frames|
            error("sprite_direction", "Unknown direction #{direction}", path) unless DIRECTIONS.includes?(direction)
            error("sprite_frames", "Animations need 1–256 frames per direction", path) unless (1..256).includes?(frames.size)
            frames.each do |frame|
              error("sprite_duration", "Frame duration must be 1–60000 milliseconds", path) unless (1..60_000).includes?(frame.duration_ms)
              error("sprite_dimensions", "Frame dimensions do not match sprite", path) unless frame.rows.size == sprite.height && frame.rows.all? { |row| row.ascii_only? && row.bytesize == sprite.width }
              error("sprite_palette", "Frame uses an undefined palette key", path) if frame.rows.any? { |row| row.chars.any? { |c| c != ' ' && !sprite.palette.has_key?(c.to_s) } }
            end
          end
        end
      end
      catalog.try(&.terrain.each do |id, terrain|
        [terrain.sprite, terrain.side_sprite].compact.each { |ref| sprite_reference(ref, "terrain.yaml") }
        unless Glyphs.allowed?(terrain.glyph)
          diagnostics << Diagnostic.new(Severity::Warning, "legacy_glyph", "Terrain #{id}: unsupported art glyph is shown as ?", "terrain.yaml")
        end
      end)
      maps.each do |key, map|
        path = paths["map:#{key}"]
        seen = Set{"ground"}
        map.surfaces.each do |surface|
          identifier(surface.id, path)
          error("duplicate_surface", "Duplicate surface #{surface.id}", path) unless seen.add?(surface.id)
        end
        error("surface_limit", "Maps support at most 32 surfaces", path) if map.surfaces.size > 31
        error("surface_limit", "All surfaces combined must contain at most 4,194,304 cells", path) if map.width.to_i64 * map.height * (map.surfaces.size + 1) > 4_194_304
        map.all_surfaces.each do |surface|
          error("surface_kind", "Surface kind must be ground, floor, platform or roof", path) unless %w(ground floor platform roof).includes?(surface.kind)
          {surface.terrain, surface.collision}.each do |rows|
            error("surface_dimensions", "#{surface.id}: rows must match map dimensions", path) unless rows.size == map.height && rows.all? { |r| r.ascii_only? && r.bytesize == map.width }
          end
          surface.terrain.each do |row|
            error("surface_terrain", "Undefined surface terrain", path) unless row.chars.all? { |c| c == ' ' || map.legend.has_key?(c.to_s) }
          end
          error("surface_collision", "Undefined collision symbol", path) unless surface.collision.all? { |r| r.chars.all? { |c| ".#+".includes?(c) } }
          if map.schema_version == 2 || !surface.elevation.empty?
            error("surface_elevation", "Elevation needs bounded integers (-64–64), one per cell", path) unless surface.elevation.size == map.height && surface.elevation.all? { |r| values = r.split; values.size == map.width && values.all? { |s| s.to_i?.try { |n| (-64..64).includes?(n) } } }
            error("surface_shapes", "Shapes must use . n e s w N E S W and match dimensions", path) unless surface.shapes.size == map.height && surface.shapes.all? { |r| r.ascii_only? && r.bytesize == map.width && r.chars.all? { |c| ".neswNESW".includes?(c) } }
          end
        end
        wall_ids = Set(String).new
        wall_edges = Set(Tuple(String, Int32, Int32, String)).new
        map.walls.each do |wall|
          identifier(wall.id, path)
          error("duplicate_wall", "Duplicate wall #{wall.id}", path) unless wall_ids.add?(wall.id)
          error("duplicate_wall", "Two walls occupy the same surface edge", path) unless wall_edges.add?({wall.surface, wall.x, wall.y, wall.edge})
          validate_surface_position(map, wall.surface, wall.x, wall.y, path)
          error("wall", "Walls need N/E/S/W edge, height 1–32 and a valid material", path) unless %w(N E S W).includes?(wall.edge) && (1..32).includes?(wall.height) && catalog.try(&.terrain.has_key?(wall.material))
        end
        map.layers.objects.each do |object|
          validate_surface_position(map, object.surface, object.x, object.y, path)
          error("direction", "Invalid facing #{object.facing}", path) unless DIRECTIONS.includes?(object.facing)
        end
      end
      entities.each do |id, entity|
        path = paths["entity:#{id}"]
        if ref = entity.sprite
          sprite_reference(ref, path, entity.animation)
        elsif !Glyphs.allowed?(entity.glyph)
          diagnostics << Diagnostic.new(Severity::Warning, "legacy_glyph", "Unsupported art glyph is shown as ?", path)
        end
        if pos = entity.position
          if key = resolve_map(pos.map)
            validate_surface_position(maps[key], pos.surface, pos.x, pos.y, path)
          end
          error("direction", "Invalid facing #{pos.facing}", path) unless DIRECTIONS.includes?(pos.facing)
        end
      end
    end

    private def sprite_reference(ref : String, path : String, animation = "idle")
      if sprite = sprites[ref]?
        error("sprite_animation", "Unknown animation #{animation} for #{ref}", path) unless sprite.animations.has_key?(animation)
      else
        error("sprite_reference", "Unknown sprite #{ref}", path)
      end
    end

    private def validate_surface_position(map : Map, id : String, x : Int32, y : Int32, path : String)
      surface = map.all_surfaces.find { |s| s.id == id }
      unless surface
        error("surface_reference", "Unknown surface #{id}", path)
        return
      end
      if map.inside?(x, y) && (row = surface.terrain[y]?) && row.bytesize > x && row.byte_at(x) != 32
        return
      end
      error("surface_position", "Position #{x},#{y} has no supporting surface #{id}", path)
    end
  end
end
