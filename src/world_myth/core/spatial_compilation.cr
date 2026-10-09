module WorldMyth::Core
  class Compiler
    private def compile_spatial(db : DB::Connection, a : Analysis)
      [
        "CREATE TABLE sprites (id TEXT PRIMARY KEY, name TEXT NOT NULL, width INTEGER NOT NULL, height INTEGER NOT NULL, anchor_x INTEGER NOT NULL, anchor_y INTEGER NOT NULL, default_direction TEXT NOT NULL, palette_json TEXT NOT NULL)",
        "CREATE TABLE animations (sprite_id TEXT NOT NULL REFERENCES sprites(id), id TEXT NOT NULL, looping INTEGER NOT NULL, PRIMARY KEY(sprite_id,id))",
        "CREATE TABLE sprite_frames (sprite_id TEXT NOT NULL, animation_id TEXT NOT NULL, direction TEXT NOT NULL, ordinal INTEGER NOT NULL, duration_ms INTEGER NOT NULL, rows_json TEXT NOT NULL, PRIMARY KEY(sprite_id,animation_id,direction,ordinal), FOREIGN KEY(sprite_id,animation_id) REFERENCES animations(sprite_id,id))",
        "CREATE TABLE surfaces (region_id TEXT NOT NULL, map_id TEXT NOT NULL, id TEXT NOT NULL, kind TEXT NOT NULL, PRIMARY KEY(region_id,map_id,id), FOREIGN KEY(region_id,map_id) REFERENCES maps(region_id,id))",
        "CREATE TABLE surface_cells (region_id TEXT NOT NULL, map_id TEXT NOT NULL, surface_id TEXT NOT NULL, x INTEGER NOT NULL, y INTEGER NOT NULL, elevation INTEGER NOT NULL, shape TEXT NOT NULL, terrain_id TEXT NOT NULL REFERENCES terrain(id), collision TEXT NOT NULL, PRIMARY KEY(region_id,map_id,surface_id,y,x), FOREIGN KEY(region_id,map_id,surface_id) REFERENCES surfaces(region_id,map_id,id)) WITHOUT ROWID",
        "CREATE TABLE walls (region_id TEXT NOT NULL, map_id TEXT NOT NULL, id TEXT NOT NULL, surface_id TEXT NOT NULL, x INTEGER NOT NULL, y INTEGER NOT NULL, edge TEXT NOT NULL, height INTEGER NOT NULL, material TEXT NOT NULL REFERENCES terrain(id), PRIMARY KEY(region_id,map_id,id), FOREIGN KEY(region_id,map_id,surface_id) REFERENCES surfaces(region_id,map_id,id))",
        "CREATE TABLE entity_visuals (entity_id TEXT PRIMARY KEY REFERENCES entities(id), sprite_id TEXT REFERENCES sprites(id), animation TEXT NOT NULL)",
        "CREATE TABLE terrain_visuals (terrain_id TEXT PRIMARY KEY REFERENCES terrain(id), sprite_id TEXT REFERENCES sprites(id), side_sprite_id TEXT REFERENCES sprites(id))",
        "CREATE TABLE placement_surfaces (region_id TEXT NOT NULL, map_id TEXT NOT NULL, placement_id TEXT NOT NULL, surface_id TEXT NOT NULL, facing TEXT NOT NULL, PRIMARY KEY(region_id,map_id,placement_id), FOREIGN KEY(region_id,map_id,placement_id) REFERENCES objects(region_id,map_id,id), FOREIGN KEY(region_id,map_id,surface_id) REFERENCES surfaces(region_id,map_id,id))",
        "CREATE TABLE position_surfaces (entity_id TEXT PRIMARY KEY REFERENCES entity_positions(entity_id), region_id TEXT NOT NULL, map_id TEXT NOT NULL, surface_id TEXT NOT NULL, facing TEXT NOT NULL, FOREIGN KEY(region_id,map_id,surface_id) REFERENCES surfaces(region_id,map_id,id))",
      ].each { |sql| db.exec(sql) }
      a.sprites.keys.sort.each do |id|
        s = a.sprites[id]
        palette = s.palette.keys.sort.to_h { |key| ink = s.palette[key]; {key, {"glyph" => ink.glyph, "foreground" => ink.foreground, "background" => ink.background}} }.to_json
        db.exec("INSERT INTO sprites VALUES (?,?,?,?,?,?,?,?)", id, s.name, s.width, s.height, s.anchor_x, s.anchor_y, s.default_direction, palette)
        s.animations.keys.sort.each do |name|
          animation = s.animations[name]
          db.exec("INSERT INTO animations VALUES (?,?,?)", id, name, animation.loop ? 1 : 0)
          animation.directions.keys.sort.each do |direction|
            animation.directions[direction].each_with_index do |frame, i|
              db.exec("INSERT INTO sprite_frames VALUES (?,?,?,?,?,?)", id, name, direction, i, frame.duration_ms, frame.rows.to_json)
            end
          end
        end
      end
      a.maps.keys.sort.each do |key|
        map = a.maps[key]
        region = key.split('/').first
        map.all_surfaces.sort_by(&.id).each do |s|
          db.exec("INSERT INTO surfaces VALUES (?,?,?,?)", region, map.id, s.id, s.kind)
          map.height.times do |y|
            map.width.times do |x|
              next if s.symbol(x, y) == " "
              db.exec("INSERT INTO surface_cells VALUES (?,?,?,?,?,?,?,?,?)", region, map.id, s.id, x, y, s.height_at(x, y), s.shape(x, y).to_s, map.legend[s.symbol(x, y)], s.collision[y].byte_at(x).chr.to_s)
            end
          end
        end
        map.walls.sort_by(&.id).each do |wall|
          db.exec("INSERT INTO walls VALUES (?,?,?,?,?,?,?,?,?)", region, map.id, wall.id, wall.surface, wall.x, wall.y, wall.edge, wall.height, wall.material)
        end
        map.layers.objects.sort_by(&.id).each do |object|
          db.exec("INSERT INTO placement_surfaces VALUES (?,?,?,?,?)", region, map.id, object.id, object.surface, object.facing)
        end
      end
      a.entities.keys.sort.each do |id|
        entity = a.entities[id]
        db.exec("INSERT INTO entity_visuals VALUES (?,?,?)", id, entity.sprite, entity.animation)
        if pos = entity.position
          region, map = a.resolve_map(pos.map).not_nil!.split('/')
          db.exec("INSERT INTO position_surfaces VALUES (?,?,?,?,?)", id, region, map, pos.surface, pos.facing)
        end
      end
      a.catalog.not_nil!.terrain.keys.sort.each do |id|
        tile = a.catalog.not_nil!.terrain[id]
        db.exec("INSERT INTO terrain_visuals VALUES (?,?,?)", id, tile.sprite, tile.side_sprite)
      end
    end
  end
end
