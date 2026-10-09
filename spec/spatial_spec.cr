require "./spec_helper"

def with_v2(&)
  with_world do |old|
    migrated = Migration.copy(old.snapshot, File.join(File.dirname(old.root), "v2"))
    yield migrated
  end
end

describe "spatial world v2" do
  it "migrates to a separate valid project and preserves the original byte for byte" do
    with_world do |old|
      before = old.snapshot
      upgraded = Migration.copy(before, File.join(File.dirname(old.root), "upgraded"))
      upgraded.analyze.valid?.should be_true
      upgraded.analyze.world.not_nil!.schema_version.should eq(2)
      upgraded.analyze.maps["heartlands/meadow"].surface.height_at(0, 0).should eq(0)
      old.snapshot.should eq(before)
      expect_raises(DocumentError) { Migration.copy(before, upgraded.root) }
      commented = before.dup
      commented["world.yaml"] += "\n# keep my prose\n"
      expect_raises(NormalizationRequired) { Migration.sources(commented) }
      Migration.sources(commented, true)["world.yaml"].should_not contain("# keep my prose")
    end
  end

  it "edits height, ramps, walls and upper-floor terrain through document history" do
    with_v2 do |p|
      doc = map_document(p)
      doc.edit("Floor") { |value| m = value.as(Map); m.surfaces << Surface.blank("floor", "floor", m.width, m.height, 6) }
      { {"terrain", "floor", "floor"}, {"height", "7", "ground"}, {"shape", "e", "ground"}, {"wall", "wall:N:4", "ground"} }.each do |layer, value, surface|
        stroke = Stroke.new(doc, layer, value, false, surface)
        stroke.visit(2, 2)
        stroke.commit
      end
      map = doc.model.as(Map)
      map.surface.height_at(2, 2).should eq(7)
      map.surface.z(2, 2).should eq(7.5)
      map.surface("floor").symbol(2, 2).should eq("d")
      map.walls.size.should eq(1)
      doc.undo
      doc.model.as(Map).walls.should be_empty
      doc.redo
      doc.model.as(Map).walls.size.should eq(1)
      p.save_all
      Project.new(p.root).analyze.valid?.should be_true
    end
  end

  it "validates sprite palette, timing, dimensions and surface references" do
    with_v2 do |p|
      s = Sprite.new("actor.test", "Test", 3, 3)
      p.add_document("sprites/test.yaml", s.to_yaml)
      p.analyze.valid?.should be_true
      s.palette["x"].glyph = "😀"
      s.animations["idle"].directions["S"][0].duration_ms = 0
      p.documents["sprites/test.yaml"].replace(s.to_yaml)
      p.add_document("entities/npcs/test.yaml", entity_yaml.sub("schema_version: 1", "schema_version: 2").sub("  x: 2", "  surface: absent\n  x: 2"))
      codes = p.analyze.diagnostics.map(&.code)
      codes.should contain("sprite_glyph")
      codes.should contain("sprite_duration")
      codes.should contain("surface_reference")
    end
  end

  it "selects animation frames deterministically with fallback and non-looping clips" do
    sprite = Sprite.new("actor.test", "Test", 1, 1)
    a = sprite.animations["idle"]
    a.directions["S"] = [SpriteFrame.new(["x"], 100), SpriteFrame.new([" "], 200)]
    sprite.frame("idle", "NW", 99_i64).rows.should eq(["x"])
    sprite.frame("idle", "NW", 100_i64).rows.should eq([" "])
    sprite.frame("idle", "S", 300_i64).rows.should eq(["x"])
    a.loop = false
    sprite.frame("idle", "S", 1000_i64).rows.should eq([" "])
  end
end

describe "spatial compatibility and visibility" do
  it "creates v2 projects by default but keeps edited v1 documents free of new fields" do
    with_world do |legacy|
      fresh = Project.create(File.join(File.dirname(legacy.root), "fresh"), "Fresh")
      fresh.analyze.world.not_nil!.schema_version.should eq(2)
      fresh.analyze.valid?.should be_true
      doc = map_document(legacy)
      stroke = Stroke.new(doc, "terrain", "forest")
      stroke.visit(1, 1)
      stroke.commit
      node = YAML.parse(doc.text)
      node["schema_version"].as_i.should eq(1)
      node["surfaces"]?.should be_nil
      node["walls"]?.should be_nil
      node["layers"]["elevation"]?.should be_nil
    end
  end

  it "rejects unsupported v2 data on a v1 world and prevents new documents escaping through symlink directories" do
    with_world do |p|
      sources = p.snapshot
      map = Map.from_yaml(map_document(p).text)
      map.surfaces << Surface.blank("floor", "floor", map.width, map.height)
      sources[map_document(p).path] = map.to_yaml
      Analysis.new(sources).diagnostics.map(&.code).should contain("migration_required")
      outside = File.join(File.dirname(p.root), "outside")
      Dir.mkdir(outside)
      Dir.delete(File.join(p.root, "sprites"))
      File.symlink(outside, File.join(p.root, "sprites"))
      expect_raises(DocumentError, /escapes/) { p.add_document("sprites/no.yaml", Sprite.new("sprite.no", "No", 2, 2).to_yaml) }
    end
  end
end
