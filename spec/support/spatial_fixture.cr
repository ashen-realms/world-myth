require "./world_fixture"

# Authored integration-test scene, generated only in disposable directories.
module SpatialFixture
  extend self
  include WorldMyth::Core

  def sprite(project : Project, id : String, name : String, rows : Array(String), colors : Hash(String, String)) : Sprite
    s = Sprite.new(id, name, rows.first.size, rows.size)
    s.palette.clear
    rows.join.chars.uniq.reject(' ').each do |c|
      s.palette[c.to_s] = Ink.new(c.to_s, colors[c.to_s]? || "#d6bb8b")
    end
    s.animations["idle"].directions["S"] = [SpriteFrame.new(rows)]
    project.add_document("sprites/#{id}.yaml", s.to_yaml)
    s
  end

  def create(path : String) : Project
    project = WorldFixture.create(path)
    Migration.sources(project.snapshot).each { |file, text| project.documents[file].replace(text) }
    npc = sprite(project, "actor.ulf", "Ulf — eight directions", ["  o  ", " /█\\ ", "  █  ", " / \\ "], {"o" => "#e8bb87", "█" => "#65a6bd"})
    %w(^ > v < / \\).each { |c| npc.palette[c] = Ink.new(c, "#e8bb87") }
    %w(idle walk).each do |clip|
      directions = {} of String => Array(SpriteFrame)
      DIRECTIONS.each_with_index do |direction, i|
        head = ["^", "/", ">", "\\", "v", "/", "<", "\\"][i]
        first = ["  #{head}  ", " /█\\ ", "  █  ", " / \\ "]
        second = clip == "walk" ? ["  #{head}  ", " \\█/ ", "  █  ", " \\ / "] : ["  #{head}  ", " /█\\ ", "  █  ", " | | "]
        second.join.chars.reject(' ').each { |c| npc.palette[c.to_s] ||= Ink.new(c.to_s) }
        directions[direction] = [SpriteFrame.new(first, clip == "idle" ? 600 : 180), SpriteFrame.new(second, clip == "idle" ? 600 : 180)]
      end
      npc.animations[clip] = Animation.new(directions)
    end
    project.documents["sprites/actor.ulf.yaml"].replace(npc.to_yaml)
    sprite(project, "prop.tree", "Oak", ["   ▄▄▄   ", " ▄█████▄ ", "█████████", "  █████  ", "    ║    ", "   /║\\   "], {"█" => "#4b9858", "▄" => "#76b36b", "║" => "#a58462"})
    sprite(project, "prop.lantern", "Lantern", ["┌─┐", "│█│", "└─┘"], {"█" => "#ffde73"})
    sprite(project, "prop.forge", "Forge", [" ╔══╗ ", " ║██║ ", "╔╩══╩╗", "╚════╝"], {"█" => "#ed8b50"})
    sprite(project, "actor.wolf", "Wolf", [" /\\  ", "<███>", " / \\ "], {"█" => "#8e9ca8"})
    sprite(project, "material.grass", "Grass", [".   ,   ", "  .   ' "], {"." => "#739664", "," => "#5c8152", "'" => "#88aa66"})
    sprite(project, "material.floor", "Wood planks", ["──┬─────", "──┴─────"], {"─" => "#947753", "┬" => "#947753", "┴" => "#947753"})
    sprite(project, "material.stone", "Stone blocks", ["─┬───┬──", "─┴───┴──"], {"─" => "#788489", "┬" => "#657478", "┴" => "#657478"})
    project.documents["terrain.yaml"].edit("Assign material patterns") do |v|
      catalog = v.as(Catalog)
      catalog.terrain["grass"].sprite = "material.grass"
      catalog.terrain["forest"].sprite = "material.grass"
      catalog.terrain["floor"].sprite = "material.floor"
      catalog.terrain["wall"].sprite = "material.stone"
      catalog.terrain["wall"].side_sprite = "material.stone"
    end
    project.documents["entities/npcs/ulf.yaml"].edit("Assign sprite") { |v| v.as(Entity).sprite = npc.id }
    project.documents["entities/items/lantern.yaml"].edit("Assign sprite") { |v| v.as(Entity).sprite = "prop.lantern" }
    project.documents["entities/objects/forge.yaml"].edit("Assign sprite") { |v| v.as(Entity).sprite = "prop.forge" }
    project.documents["entities/monsters/wolf.yaml"].edit("Assign sprite") { |v| v.as(Entity).sprite = "actor.wolf" }
    project.add_document("entities/objects/tree.yaml", <<-YAML)
    schema_version: 2
    id: object.oak
    type: object
    name: Oak
    sprite: prop.tree
    YAML
    project.documents["regions/heartlands/maps/village.yaml"].edit("Author layered village") do |v|
      m = v.as(Map)
      ground = m.surface
      # Clear old schematic houses before constructing real walls and floors.
      m.height.times { |y| m.width.times { |x| ground.set("terrain", x, y, "g"); ground.set("collision", x, y, ".") } }
      (3..9).each { |y| (3..10).each { |x| ground.set("terrain", x, y, "d") } }
      upper = Surface.blank("upper-floor", "floor", m.width, m.height, 6)
      roof = Surface.blank("roof", "roof", m.width, m.height, 12)
      (3..9).each do |y|
        (3..10).each do |x|
          upper.set("terrain", x, y, "d")
          roof.set("terrain", x, y, "w")
          roof.set("shape", x, y, x < 7 ? "e" : "w")
          roof.set("height", x, y, (12 + (x < 7 ? x - 3 : 10 - x)).to_s)
        end
      end
      bridge = Surface.blank("bridge", "platform", m.width, m.height, 4)
      (13..22).each { |x| (11..12).each { |y| bridge.set("terrain", x, y, "d") } }
      m.surfaces = [upper, roof, bridge]
      ["ground", "upper-floor"].each do |surface|
        (3..10).each do |x|
          wall = Wall.new("#{surface}-back-#{x}", x, 3, "wall")
          wall.surface, wall.edge, wall.height = surface, "N", 6
          m.walls << wall
        end
        (3..9).each do |y|
          wall = Wall.new("#{surface}-side-#{y}", 3, y, "wall")
          wall.surface, wall.edge, wall.height = surface, "W", 6
          m.walls << wall
        end
      end
      (24..29).each do |x|
        (3..7).each do |y|
          ground.set("height", x, y, (x - 24).to_s)
          ground.set("shape", x, y, y == 5 ? "E" : "e")
        end
      end
      [{12, 6}, {16, 7}, {23, 16}, {27, 12}].each_with_index do |(x, y), i|
        m.layers.objects << Placement.new("oak-#{i}", "object.oak", x, y)
      end
    end
    base = project.documents["entities/npcs/ulf.yaml"].model.as(Entity)
    {"npc.bridge.top" => "bridge", "npc.bridge.below" => "ground", "npc.upper" => "upper-floor"}.each do |id, surface|
      entity = Entity.from_yaml(base.to_yaml)
      entity.id, entity.name = id, id.split('.').last.capitalize
      pos = Position.new("heartlands/village", surface == "upper-floor" ? 6 : 17, surface == "upper-floor" ? 6 : 11)
      pos.surface = surface
      entity.position = pos
      project.add_document("entities/npcs/#{id}.yaml", entity.to_yaml)
    end
    project.documents["world.yaml"].edit("Name demo") { |v| w = v.as(World); w.name = "Eldoria — Isometric"; w.version = "0.2.0" }
    project.documents.values.select { |doc| doc.model.is_a?(Sprite) }.each do |doc|
      doc.edit("Encode palette rows") do |value|
        s = value.as(Sprite)
        mapping = {} of String => String
        used = s.palette.keys.to_set
        s.palette.each do |key, ink|
          next if key.ascii_only?
          replacement = ('!'..'~').map(&.to_s).find { |candidate| !used.includes?(candidate) }.not_nil!
          used << replacement
          mapping[key] = replacement
        end
        s.palette = s.palette.to_h { |key, ink| {mapping[key]? || key, ink} }
        s.animations.each_value do |animation|
          animation.directions.each_value do |frames|
            frames.each { |frame| frame.rows = frame.rows.map { |row| row.chars.map { |c| mapping[c.to_s]? || c.to_s }.join } }
          end
        end
      end
    end
    project.save_all
    analysis = project.analyze
    raise analysis.diagnostics.join('\n') unless analysis.valid?
    project
  end

  def with_world(&)
    root = File.join(Dir.tempdir, "world-myth-spatial-fixture-#{Random::Secure.hex(8)}")
    begin
      yield create(root)
    ensure
      FileUtils.rm_r(root) if Dir.exists?(root)
    end
  end
end
