require "./spec_helper"

describe WorldMyth do
  it "creates a valid independent project without overwriting an existing directory" do
    with_world do |project|
      analysis = project.analyze
      analysis.diagnostics.should be_empty
      analysis.world.not_nil!.id.should eq("test-world")
      analysis.maps.keys.should eq(["heartlands/meadow"])
      expect_raises(DocumentError) { Project.create(project.root, "Again") }
    end
  end

  it "round trips maps and preserves terrain IDs independently from glyphs" do
    with_world do |project|
      doc = map_document(project)
      map = doc.model.as(Map)
      Map.from_yaml(map.to_yaml).layers.terrain.should eq(map.layers.terrain)
      map.terrain_at(0, 0).should eq("grass")
      project.analyze.catalog.not_nil!.terrain["grass"].glyph.should eq(".")
    end
  end

  it "groups a continuous stroke and reverses model changes across save points" do
    with_world do |project|
      doc = map_document(project)
      before = doc.text
      stroke = Stroke.new(doc, "terrain", "forest")
      stroke.visit(0, 0)
      stroke.visit(10, 0)
      doc.text.should eq(before)
      stroke.commit
      doc.history.size.should eq(1)
      doc.model.as(Map).terrain_at(5, 0).should eq("forest")
      doc.save(project.root)
      doc.dirty?.should be_false
      doc.undo
      doc.text.should eq(before)
      doc.dirty?.should be_true
      doc.redo
      doc.dirty?.should be_false
      reopened = Project.new(project.root)
      map_document(reopened).model.as(Map).terrain_at(5, 0).should eq("forest")
    end
  end

  it "edits and erases each layer without affecting the others" do
    with_world do |project|
      doc = map_document(project)
      { {"terrain", "forest"}, {"collision", "#"}, {"objects", "object.chest"} }.each do |layer, value|
        stroke = Stroke.new(doc, layer, value)
        stroke.visit(2, 2)
        stroke.commit
      end
      map = doc.model.as(Map)
      map.terrain_at(2, 2).should eq("forest")
      map.symbol_at("collision", 2, 2).should eq("#")
      map.layers.objects.first.entity.should eq("object.chest")
      {"terrain", "collision", "objects"}.each do |layer|
        stroke = Stroke.new(doc, layer, "", true)
        stroke.visit(2, 2)
        stroke.commit
      end
      map = doc.model.as(Map)
      map.terrain_at(2, 2).should eq("grass")
      map.symbol_at("collision", 2, 2).should eq(".")
      map.layers.objects.should be_empty
    end
  end

  it "rejects stale gestures and discards redo after a new edit" do
    with_world do |project|
      doc = map_document(project)
      stroke = Stroke.new(doc, "terrain", "forest")
      stroke.visit(1, 1)
      doc.replace(doc.text + "\n")
      expect_raises(ConflictError) { stroke.commit }
      doc.undo
      doc.replace(doc.text + "\n\n")
      doc.future.should be_empty
    end
  end

  it "requires explicit comment normalization and restores comments on undo" do
    with_world do |project|
      doc = map_document(project)
      doc.replace("# handwritten note\n" + doc.text)
      doc.sensitive?.should be_true
      expect_raises(NormalizationRequired) { Stroke.new(doc, "terrain", "forest") }
      before = doc.text
      doc.normalize
      doc.sensitive?.should be_false
      doc.undo
      doc.text.should eq(before)
      Source.sensitive?("color: '#aabbcc'\nvalue: hello#world\ntext: |\n  # literal content\n").should be_false
      Source.sensitive?("color: '#aabbcc' # comment\n").should be_true
    end
  end

  it "preserves malformed text and reports precise YAML diagnostics" do
    with_world do |project|
      doc = map_document(project)
      doc.replace("layers: [\n")
      doc.model.should be_nil
      doc.save(project.root)
      Project.new(project.root).documents[doc.path].text.should eq("layers: [\n")
      diagnostics = project.analyze.diagnostics
      diagnostics.any? { |d| d.code == "yaml" && d.path == doc.path && !d.line.nil? }.should be_true
      doc.undo
      doc.model.should be_a(Map)
    end
  end

  it "refuses to overwrite externally changed or deleted files" do
    with_world do |project|
      doc = map_document(project)
      doc.replace(doc.text + "\n")
      full = File.join(project.root, doc.path)
      File.write(full, "external edit\n")
      expect_raises(ConflictError) { doc.save(project.root) }
      File.read(full).should eq("external edit\n")
      doc.dirty?.should be_true
    end
  end

  it "detects version, duplicate keys, invalid symbols, dimensions and terrain errors" do
    with_world do |project|
      sources = project.snapshot
      sources["world.yaml"] = sources["world.yaml"].sub("schema_version: 1", "schema_version: 99")
      map = map_document(project).model.as(Map)
      map.width = 4
      map.layers.terrain[0] = "zzzz"
      sources[map_document(project).path] = map.to_yaml
      sources["terrain.yaml"] = sources["terrain.yaml"].sub("#88aa66", "invalid")
      codes = Analysis.new(sources).diagnostics.map(&.code)
      codes.should contain("schema_version")
      codes.should contain("layer_width")
      codes.should contain("undefined_symbol")
      codes.should contain("terrain_color")
      expect_raises(DocumentError, /Duplicate YAML key/) { Source.check_syntax("id: one\nid: two\n") }
    end
  end

  it "resolves declared IDs, detects duplicates and missing/ambiguous references" do
    with_world do |project|
      sources = project.snapshot
      map_path = map_document(project).path
      sources[map_path.sub("meadow.yaml", "renamed-file.yaml")] = sources.delete(map_path).not_nil!
      Analysis.new(sources).valid?.should be_true
      sources["entities/npcs/ulf.yaml"] = entity_yaml
      Analysis.new(sources).valid?.should be_true
      sources["entities/npcs/duplicate.yaml"] = entity_yaml
      Analysis.new(sources).diagnostics.map(&.code).should contain("duplicate_id")
      sources.delete("entities/npcs/duplicate.yaml")
      sources["entities/npcs/ulf.yaml"] = entity_yaml(position: "missing")
      Analysis.new(sources).diagnostics.map(&.code).should contain("map_reference")
      sources.delete("regions/heartlands/region.yaml")
      Analysis.new(sources).diagnostics.map(&.code).should contain("default_region")
    end
  end

  it "validates entity bounds and supported property structure" do
    with_world do |project|
      sources = project.snapshot
      sources["entities/npcs/ulf.yaml"] = entity_yaml.sub("x: 2", "x: -1").sub("greeting: Welcome", "greeting: [nested]")
      codes = Analysis.new(sources).diagnostics.map(&.code)
      codes.should contain("coordinates")
      codes.should contain("entity_property")
    end
  end

  it "keeps the logical coordinate beneath the pointer stable during zoom" do
    viewport = Viewport.new
    before = viewport.cell(151.0, 200.0)
    viewport.zoom_at(1.5, 151.0, 200.0)
    viewport.cell(151.0, 200.0).should eq(before)
    viewport.zoom_at(1000.0, 0.0, 0.0)
    viewport.zoom.should eq(4.0)
  end

  it "compiles a complete read-only database with repeatable bytes" do
    with_world do |project|
      File.write(File.join(project.root, "entities/npcs/ulf.yaml"), entity_yaml)
      compiler = Compiler.new(project.root)
      dist = compiler.build
      database = File.join(dist, "world.sqlite")
      first = File.read(database)
      manifest = File.read(File.join(dist, "manifest.json"))
      DB.open("sqlite3:#{database}?mode=ro") do |db|
        db.scalar("PRAGMA user_version").should eq(1_i64)
        db.scalar("PRAGMA integrity_check").should eq("ok")
        db.scalar("SELECT count(*) FROM cells").should eq(640_i64)
        db.scalar("SELECT map_id FROM entity_positions").should eq("meadow")
        db.scalar("SELECT count(*) FROM lore").should eq(1_i64)
      end
      compiler.build
      File.read(database).should eq(first)
      File.read(File.join(dist, "manifest.json")).should eq(manifest)
      JSON.parse(manifest)["sha256"].as_s.should eq(Digest::SHA256.hexdigest(first))
      File.write(File.join(project.root, "world.yaml"), "invalid: [")
      expect_raises(DocumentError) { compiler.build }
      File.read(database).should eq(first)
      File.read(File.join(dist, "manifest.json")).should eq(manifest)
    end
  end

  it "provides useful CLI exit codes and conservative idempotent formatting" do
    with_world do |project|
      output = IO::Memory.new
      errors = IO::Memory.new
      WorldMyth::CLI.run(["validate", project.root], output, errors).should eq(0)
      WorldMyth::CLI.run(["unknown"], output, errors).should eq(2)
      doc = map_document(project)
      path = File.join(project.root, doc.path)
      commented = "# keep this\n" + doc.text
      File.write(path, commented)
      WorldMyth::CLI.run(["fmt", project.root], output, errors).should eq(0)
      File.read(path).should eq(commented)
      WorldMyth::CLI.run(["fmt", project.root, "--allow-comment-loss"], output, errors).should eq(0)
      Source.sensitive?(File.read(path)).should be_false
      WorldMyth::CLI.run(["fmt", project.root, "--check"], output, errors).should eq(0)
    end
  end
end
