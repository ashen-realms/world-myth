module WorldMyth::Core
  record Hit, surface : String, x : Int32, y : Int32, z : Float64, entity : String? = nil
  record Vertex, u : Float64, v : Float64, depth : Float64

  module Isometric
    def self.project(x : Float64, y : Float64, z : Float64 = 0.0) : Vertex
      Vertex.new(4 * (x - y), x + y - z, x + y + z)
    end

    def self.cell(u : Float64, v : Float64, z = 0.0) : Tuple(Int32, Int32)
      {((v + z + u / 4) / 2).floor.to_i, ((v + z - u / 4) / 2).floor.to_i}
    end
  end

  class SceneCamera
    property u = -20.0
    property v = -4.0
    property active_surface = "ground"
    property cutaway = false
    property roofs = true
    property terrain = true
    property objects = true
    property collision = false
    property grid = false
    property animation : String? = nil
  end

  struct SceneCell
    property glyph = " "
    property foreground = "#88aa66"
    property background = "#0c1212"
    property depth : Float64 = -Float64::INFINITY
    property background_depth : Float64 = -Float64::INFINITY
    property background_order = -1
    property order = -1
    property hit : Hit? = nil
  end

  class GlyphFrame
    getter width : Int32
    getter height : Int32
    getter cells : Array(SceneCell)
    getter surface_hits : Array(Hit?)
    @surface_depth : Array(Float64)

    def initialize(@width, @height)
      @cells = Array.new(width * height) { SceneCell.new }
      @surface_hits = Array(Hit?).new(width * height, nil)
      @surface_depth = Array.new(width * height, -Float64::INFINITY)
    end

    def put(x : Int32, y : Int32, depth : Float64, order : Int32, glyph : String, fg : String, bg : String?, hit : Hit, active : Bool)
      return unless x >= 0 && y >= 0 && x < width && y < height
      index = y * width + x
      if active && depth >= @surface_depth[index]
        surface_hits[index] = hit
        @surface_depth[index] = depth
      end
      cell = cells[index]
      if bg && (depth > cell.background_depth || (depth == cell.background_depth && order >= cell.background_order))
        cell.background = bg
        cell.background_depth = depth
        cell.background_order = order
      end
      if depth > cell.depth || (depth == cell.depth && order >= cell.order)
        cell.glyph = glyph
        cell.foreground = fg
        cell.depth = depth
        cell.order = order
        cell.hit = hit
      end
      cells[index] = cell
    end

    def hit(x : Int32, y : Int32) : Hit?
      return nil unless x >= 0 && y >= 0 && x < width && y < height
      surface_hits[y * width + x]
    end
  end

  record Triangle, a : Vertex, b : Vertex, c : Vertex, material : String, side : Bool, hit : Hit, kind : String, blocked : Bool?, shape : Char
  record Billboard, vertex : Vertex, entity : Entity, facing : String, hit : Hit, kind : String
  alias Primitive = Triangle | Billboard

  class SceneRenderer
    getter map : Map
    getter primitives = [] of Primitive
    getter last_candidates = 0
    getter animated : Bool
    @buckets = Hash(Tuple(Int32, Int32), Array(Int32)).new { |h, k| h[k] = [] of Int32 }
    @surface_levels = {} of String => Int32
    @surfaces : Array(Surface)
    @prepared_tiles = Set(Tuple(String, Int32, Int32)).new
    @z_min = -1.0
    @z_max = 1.0

    def initialize(@map : Map, @analysis : Analysis, @reference : String)
      @surfaces = map.all_surfaces
      @animated = @analysis.sprites.values.any? { |s| s.animations.values.any? { |a| a.directions.values.any? { |f| f.size > 1 } } }
      prepare
    end

    private def add(primitive : Primitive, left : Float64, top : Float64, right : Float64, bottom : Float64)
      id = primitives.size
      primitives << primitive
      ((top / 8).floor.to_i..(bottom / 8).floor.to_i).each do |y|
        ((left / 16).floor.to_i..(right / 16).floor.to_i).each { |x| @buckets[{x, y}] << id }
      end
    end

    private def triangle(a : Vertex, b : Vertex, c : Vertex, material : String, side : Bool, hit : Hit, kind : String, blocked : Bool?, shape : Char)
      vertices = {a, b, c}
      add(Triangle.new(a, b, c, material, side, hit, kind, blocked, shape), vertices.min_of(&.u), vertices.min_of(&.v), vertices.max_of(&.u), vertices.max_of(&.v))
    end

    private def quad(vertices : Array(Vertex), material : String, side : Bool, hit : Hit, kind : String, blocked : Bool? = nil, shape = '.')
      triangle(vertices[0], vertices[1], vertices[2], material, side, hit, kind, blocked, shape)
      triangle(vertices[0], vertices[2], vertices[3], material, side, hit, kind, blocked, shape)
    end

    private def prepare_tiles(camera : SceneCamera, width : Int32, height : Int32)
      corners = [] of Tuple(Int32, Int32)
      {camera.u - 4, camera.u + width + 4}.each do |u|
        {camera.v - 2, camera.v + height + 2}.each do |v|
          {@z_min, @z_max}.each { |z| corners << Isometric.cell(u, v, z) }
        end
      end
      x0, x1 = corners.min_of(&.[0]).clamp(0, map.width - 1), corners.max_of(&.[0]).clamp(0, map.width - 1)
      y0, y1 = corners.min_of(&.[1]).clamp(0, map.height - 1), corners.max_of(&.[1]).clamp(0, map.height - 1)
      @surfaces.each do |surface|
        (y0..y1).each do |y|
          (x0..x1).each do |x|
            next unless @prepared_tiles.add?({surface.id, x, y})
            symbol = surface.symbol(x, y)
            next if symbol == " "
            material = map.legend[symbol]
            z = surface.z(x, y)
            hit = Hit.new(surface.id, x, y, z)
            collision = surface.collision[y].byte_at(x)
            blocked = collision == 35 ? true : collision == 43 ? false : nil
            shape = surface.shape(x, y)
            # Four narrow strips preserve the step profile of stairs.
            strips = shape.uppercase? ? 4 : 1
            strips.times do |step|
              lo, hi = step.to_f / strips, (step + 1).to_f / strips
              east = "eEwW".includes?(shape)
              uv = east ? [{lo, 0.0}, {hi, 0.0}, {hi, 1.0}, {lo, 1.0}] : [{0.0, lo}, {1.0, lo}, {1.0, hi}, {0.0, hi}]
              vertices = uv.map do |u, v|
                level = strips == 4 ? surface.z(x, y, east ? (lo + hi) / 2 : u, east ? v : (lo + hi) / 2) : surface.z(x, y, u, v)
                Isometric.project(x + u, y + v, level)
              end
              quad(vertices, material, false, hit, surface.kind, blocked, shape)
            end
            # Front-facing exposed sides of solid ground or a thin suspended slab.
            [{1.0, 0.0, 1.0, 1.0, x + 1, y}, {1.0, 1.0, 0.0, 1.0, x, y + 1}].each do |u0, v0, u1, v1, nx, ny|
              za, zb = surface.z(x, y, u0, v0), surface.z(x, y, u1, v1)
              bottom = surface.kind == "ground" ? -1.0 : Math.min(za, zb) - 0.25
              if map.inside?(nx, ny) && surface.symbol(nx, ny) != " "
                bottom = Math.max(bottom, surface.z(nx, ny))
              end
              next if bottom >= Math.max(za, zb)
              quad([Isometric.project(x + u0, y + v0, za), Isometric.project(x + u1, y + v1, zb), Isometric.project(x + u1, y + v1, bottom), Isometric.project(x + u0, y + v0, bottom)], material, true, hit, surface.kind)
            end
          end
        end
      end
    end

    private def prepare
      @surfaces.each do |surface|
        heights = surface.elevation.flat_map { |row| row.split.map(&.to_i) }
        @surface_levels[surface.id] = heights.min? || 0
        @z_min = Math.min(@z_min, (heights.min? || 0) - 1.0)
        @z_max = Math.max(@z_max, (heights.max? || 0) + 1.0)
      end
      map.walls.each do |wall|
        surface = map.surface(wall.surface)
        uv = case wall.edge
             when "N" then {0.0, 0.0, 1.0, 0.0}
             when "E" then {1.0, 0.0, 1.0, 1.0}
             when "S" then {1.0, 1.0, 0.0, 1.0}
             else          {0.0, 1.0, 0.0, 0.0}
             end
        x, y = wall.x, wall.y
        a, b = surface.z(x, y, uv[0], uv[1]), surface.z(x, y, uv[2], uv[3])
        quad([Isometric.project(x + uv[0], y + uv[1], a), Isometric.project(x + uv[2], y + uv[3], b), Isometric.project(x + uv[2], y + uv[3], b + wall.height), Isometric.project(x + uv[0], y + uv[1], a + wall.height)], wall.material, true, Hit.new(surface.id, x, y, a), surface.kind)
      end
      map.layers.objects.sort_by(&.id).each { |o| billboard(@analysis.entities[o.entity], o.surface, o.x, o.y, o.facing) }
      @analysis.entities.keys.sort.each do |id|
        entity = @analysis.entities[id]
        if position = entity.position
          billboard(entity, position.surface, position.x, position.y, position.facing) if @analysis.resolve_map(position.map) == @reference
        end
      end
    end

    private def billboard(entity : Entity, surface_id : String, x : Int32, y : Int32, facing : String)
      surface = map.surface(surface_id)
      z = surface.z(x, y)
      vertex = Isometric.project(x + 0.5, y + 0.5, z)
      sprite = entity.sprite.try { |id| @analysis.sprites[id]? }
      ax, ay = sprite.try(&.anchor_x) || 0, sprite.try(&.anchor_y) || 0
      width, height = sprite.try(&.width) || 1, sprite.try(&.height) || 1
      add(Billboard.new(vertex, entity, facing, Hit.new(surface_id, x, y, z, entity.id), surface.kind), vertex.u - ax, vertex.v - ay - 1, vertex.u - ax + width, vertex.v - ay + height)
    end

    def render(width : Int32, height : Int32, camera : SceneCamera, time_ms = 0_i64) : GlyphFrame
      prepare_tiles(camera, width, height)
      frame = GlyphFrame.new(width, height)
      ids = Set(Int32).new
      ((camera.v / 8).floor.to_i..((camera.v + height) / 8).floor.to_i).each do |by|
        ((camera.u / 16).floor.to_i..((camera.u + width) / 16).floor.to_i).each do |bx|
          @buckets[{bx, by}]?.try(&.each { |id| ids << id })
        end
      end
      @last_candidates = ids.size
      ids.each do |id|
        primitive = primitives[id]
        next if primitive.kind == "roof" && !camera.roofs
        next if camera.cutaway && @surface_levels[primitive.hit.surface] > (@surface_levels[camera.active_surface]? || 0)
        case primitive
        when Triangle
          order = @surfaces.index { |s| s.id == primitive.hit.surface }.not_nil! * map.width * map.height * 4 + (primitive.hit.y * map.width + primitive.hit.x) * 4 + (primitive.side ? 1 : 2)
          raster(frame, primitive, camera, order, time_ms) if camera.terrain
        when Billboard
          draw_sprite(frame, primitive, camera, map.width * map.height * 128 + id, time_ms) if camera.objects
        end
      end
      frame
    end

    private def raster(frame : GlyphFrame, t : Triangle, camera : SceneCamera, order : Int32, time_ms : Int64)
      a, b, c = t.a, t.b, t.c
      den = (b.v - c.v) * (a.u - c.u) + (c.u - b.u) * (a.v - c.v)
      return if den.abs < 0.00001
      x0 = Math.max(0, ({a.u, b.u, c.u}.min - camera.u).floor.to_i)
      x1 = Math.min(frame.width - 1, ({a.u, b.u, c.u}.max - camera.u).ceil.to_i)
      y0 = Math.max(0, ({a.v, b.v, c.v}.min - camera.v).floor.to_i)
      y1 = Math.min(frame.height - 1, ({a.v, b.v, c.v}.max - camera.v).ceil.to_i)
      material = @analysis.catalog.not_nil!.terrain[t.material]
      sprite = (t.side ? material.side_sprite : material.sprite).try { |ref| @analysis.sprites[ref]? }
      texture = sprite.try(&.frame("idle", sprite.not_nil!.default_direction, time_ms))
      (y0..y1).each do |y|
        (x0..x1).each do |x|
          u, v = x + camera.u + 0.5, y + camera.v + 0.5
          wa = ((b.v - c.v) * (u - c.u) + (c.u - b.u) * (v - c.v)) / den
          wb = ((c.v - a.v) * (u - c.u) + (a.u - c.u) * (v - c.v)) / den
          wc = 1 - wa - wb
          next if wa < -0.00001 || wb < -0.00001 || wc < -0.00001
          depth = wa * a.depth + wb * b.depth + wc * c.depth
          glyph = t.side ? "▒" : Glyphs.allowed?(material.glyph) ? material.glyph : "?"
          fg, bg = material.foreground, material.background
          if sprite && texture
            glyph = " "
            key = texture.rows[v.floor.to_i % sprite.height].byte_at(u.floor.to_i % sprite.width).chr.to_s
            if ink = sprite.palette[key]?
              glyph, fg, bg = ink.glyph, ink.foreground, ink.background || bg
            end
          end
          if camera.grid && !t.side
            local_x = ((depth + v) / 2 + u / 4) / 2 - t.hit.x
            local_y = ((depth + v) / 2 - u / 4) / 2 - t.hit.y
            if {local_x, 1 - local_x, local_y, 1 - local_y}.min < 0.12
              glyph = local_x < 0.12 || local_x > 0.88 ? "\\" : "/"
              fg = "#657570"
            end
          end
          bg = t.blocked ? "#653037" : "#245c4d" if camera.collision && !t.blocked.nil?
          frame.put(x, y, depth, order, glyph, fg, bg, t.hit, !t.side && camera.active_surface == t.hit.surface)
        end
      end
    end

    private def draw_sprite(frame : GlyphFrame, b : Billboard, camera : SceneCamera, order : Int32, time_ms : Int64)
      x, y = (b.vertex.u - camera.u).floor.to_i, (b.vertex.v - camera.v).floor.to_i - 1
      if sprite = b.entity.sprite.try { |id| @analysis.sprites[id]? }
        animation = camera.animation.try { |name| sprite.animations.has_key?(name) ? name : nil } || b.entity.animation
        image = sprite.frame(animation, b.facing, time_ms)
        image.rows.each_with_index do |row, sy|
          row.each_char_with_index do |key, sx|
            next if key == ' '
            ink = sprite.palette[key.to_s]
            depth = b.vertex.depth + b.vertex.v - camera.v - (y + sy - sprite.anchor_y + 0.5)
            frame.put(x + sx - sprite.anchor_x, y + sy - sprite.anchor_y, depth + 0.001, order, ink.glyph, ink.foreground, ink.background, b.hit, false)
          end
        end
      else
        frame.put(x, y, b.vertex.depth + b.vertex.v - camera.v - y - 0.5 + 0.001, order, Glyphs.allowed?(b.entity.glyph) ? b.entity.glyph : "?", b.entity.foreground, nil, b.hit, false)
      end
    end
  end
end
