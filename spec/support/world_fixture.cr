require "../../src/world_myth"

# Disposable test data. No checked-in world or external files are required.
module WorldFixture
  extend self
  include WorldMyth::Core

  def create(path : String) : Project
    project = Project.create(path, "Eldoria", 1)
    project.documents["regions/heartlands/region.yaml"].edit("Add test map") do |value|
      value.as(Region).maps << "village"
    end
    project.add_document("regions/heartlands/maps/village.yaml", Project.map_template("village", "Test Village", 32, 20))
    {"npcs"     => {"ulf", "npc.blacksmith.ulf", "npc", "Ulf", "@"},
     "items"    => {"lantern", "item.lantern", "item", "Lantern", "!"},
     "monsters" => {"wolf", "monster.wolf", "monster", "Wolf", "w"},
     "objects"  => {"forge", "object.forge", "object", "Forge", "⚒"}}.each do |directory, values|
      file, id, type, name, glyph = values
      project.add_document("entities/#{directory}/#{file}.yaml", <<-YAML)
      schema_version: 1
      id: #{id}
      type: #{type}
      name: #{name}
      properties:
        glyph: #{glyph.to_json}
      YAML
    end
    project.documents["entities/npcs/ulf.yaml"].edit("Position test NPC") do |value|
      value.as(Entity).position = Position.new("heartlands/village", 7, 5)
    end
    project.documents["regions/heartlands/maps/village.yaml"].edit("Place test object") do |value|
      map = value.as(Map)
      map.layers.objects << Placement.new("forge", "object.forge", 5, 4)
      map.set_symbol("collision", 5, 4, "#")
    end
    project.save_all
    project
  end

  def with_world(&)
    root = File.join(Dir.tempdir, "world-myth-fixture-#{Random::Secure.hex(8)}")
    begin
      yield create(root)
    ensure
      FileUtils.rm_r(root) if Dir.exists?(root)
    end
  end
end
