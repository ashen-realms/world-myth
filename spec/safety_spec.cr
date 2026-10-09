require "./spec_helper"

class FailingPublication < Compiler
  protected def publish(staging : String, dist : String, backup : String)
    # Exercise the real rollback branch by making the final rename fail.
    super(File.join(staging, "does-not-exist"), dist, backup)
  end
end

describe "World format and persistence safeguards" do
  it "does not discard subsequent YAML documents" do
    expect_raises(DocumentError, /exactly one/) { Source.canonical("id: one\n---\nid: two\n") }
  end

  it "reports unsupported fields instead of silently dropping them" do
    with_world do |project|
      doc = map_document(project)
      doc.replace(doc.text + "surprise: data\n")
      doc.model.should be_nil
      project.analyze.diagnostics.map(&.code).should contain("yaml")
      doc.text.should contain("surprise: data")
    end
  end

  it "leaves bytes unchanged during validation" do
    with_world do |project|
      before = project.discover.to_h { |p| {p, File.read(File.join(project.root, p))} }
      project.analyze
      project.discover.to_h { |p| {p, File.read(File.join(project.root, p))} }.should eq(before)
    end
  end

  it "reads changed clean files and discovers additions/deletions in snapshots" do
    with_world do |project|
      path = map_document(project).path
      File.delete(File.join(project.root, path))
      project.analyze.diagnostics.map(&.code).should contain("missing_map")
      File.write(File.join(project.root, path), Project.map_template("meadow", "External name", 8, 5))
      project.analyze.maps["heartlands/meadow"].name.should eq("External name")
      File.write(File.join(project.root, "entities/npcs/new.yaml"), entity_yaml)
      project.analyze.entities.has_key?("npc.ulf").should be_true
    end
  end

  it "keeps dirty buffers when external changes are discovered" do
    with_world do |project|
      doc = map_document(project)
      doc.replace(doc.text + "\n# unsaved\n")
      File.write(File.join(project.root, doc.path), Project.map_template("meadow", "External", 8, 5))
      project.refresh_clean.should contain(doc.path)
      doc.text.should contain("# unsaved")
      expect_raises(ConflictError) { doc.save(project.root) }
    end
  end

  it "requires qualified references when map IDs are ambiguous" do
    with_world do |project|
      sources = project.snapshot
      sources["regions/coast/region.yaml"] = "schema_version: 1\nid: coast\nname: Coast\nmaps: [meadow]\n"
      sources["regions/coast/maps/beach.yaml"] = map_document(project).text
      sources["entities/npcs/ulf.yaml"] = entity_yaml(position: "meadow")
      a = Analysis.new(sources)
      a.diagnostics.map(&.code).should contain("map_reference")
      a.resolve_map("meadow").should be_nil
      a.resolve_map("coast/meadow").should eq("coast/meadow")
      sources["entities/npcs/ulf.yaml"] = entity_yaml(position: "coast/meadow")
      Analysis.new(sources).valid?.should be_true
    end
  end

  it "detects all map-layer and object reference problems" do
    with_world do |project|
      sources = project.snapshot
      map = map_document(project).model.as(Map)
      map.height = 0
      map.default_terrain = "absent"
      map.legend["gg"] = "missing"
      map.layers.collision[0] = "?" * map.width
      map.layers.objects << Placement.new("chest", "npc.ulf", 999, -1)
      map.layers.objects << Placement.new("chest", "missing", 0, 0)
      sources[map_document(project).path] = map.to_yaml
      codes = Analysis.new(sources).diagnostics.map(&.code)
      {"dimensions", "default_terrain", "legend_symbol", "terrain_reference", "layer_height", "undefined_symbol", "object_reference", "duplicate_placement", "coordinates"}.each do |code|
        codes.should contain(code)
      end
    end
  end

  it "rejects unsupported entity types and invalid presentation properties" do
    with_world do |project|
      sources = project.snapshot
      sources["entities/npcs/ulf.yaml"] = entity_yaml(type: "dragon").sub("name: Ulf", "name: ''").sub("greeting: Welcome", "glyph: two\n  foreground: nope")
      codes = Analysis.new(sources).diagnostics.map(&.code)
      {"entity_type", "entity_name", "entity_glyph", "entity_color"}.each { |code| codes.should contain(code) }
    end
  end

  it "rolls back publication failure without mixing old/new artifacts" do
    with_world do |project|
      dist = Compiler.new(project.root).build
      before = {File.read(File.join(dist, "world.sqlite")), File.read(File.join(dist, "manifest.json"))}
      project.documents["world.yaml"].edit("Rename") { |d| d.as(World).name = "Changed" }
      project.save_all
      expect_raises(File::NotFoundError) { FailingPublication.new(project.root).build }
      {File.read(File.join(dist, "world.sqlite")), File.read(File.join(dist, "manifest.json"))}.should eq(before)
    end
  end

  it "recovers an interrupted directory swap before publishing another valid build" do
    with_world do |project|
      dist = Compiler.new(project.root).build
      File.rename(dist, File.join(project.root, ".dist-backup"))
      Compiler.new(project.root).build
      File.file?(File.join(dist, "world.sqlite")).should be_true
      Dir.exists?(File.join(project.root, ".dist-backup")).should be_false
    end
  end

  it "bounds history and preserves Markdown bytes" do
    doc = Document.new("lore/story.md", "# First\n")
    120.times { |i| doc.replace("# Revision #{i}\n\n  exact spaces  \n") }
    doc.history.size.should eq(100)
    before = doc.text
    doc.undo
    doc.redo
    doc.text.should eq(before)
  end

  it "handles projects without Git and retrieves real modified paths" do
    with_world do |project|
      GitStatus.read(project.root).branch.should eq("No Git repository")
      Process.run("git", ["init", "-q", "-b", "main", project.root]).success?.should be_true
      status = GitStatus.read(project.root)
      status.branch.should contain("main")
      status.modified.should contain("world.yaml")
    end
  end

  it "compiles the checked-in example with every layer and entity type" do
    root = File.expand_path("../examples/example-world", __DIR__)
    Project.new(root).analyze.valid?.should be_true
    with_world do |project|
      source = Project.new(root)
      source.discover.each do |path|
        full = File.join(project.root, path)
        FileUtils.mkdir_p(File.dirname(full))
        File.write(full, File.read(File.join(root, path)))
      end
      database = File.join(Compiler.new(project.root).build, "world.sqlite")
      DB.open("sqlite3:#{database}?mode=ro") do |db|
        db.scalar("SELECT count(*) FROM maps").should eq(2_i64)
        db.scalar("SELECT count(DISTINCT type) FROM entities").should eq(4_i64)
        db.scalar("SELECT count(*) FROM objects").should eq(1_i64)
        db.scalar("SELECT collision FROM cells WHERE map_id='village' AND x=5 AND y=4").should eq(1_i64)
      end
    end
  end
end

describe "Write failure handling" do
  it "keeps the old file if a pre-replacement check fails" do
    with_world do |project|
      path = File.join(project.root, "world.yaml")
      before = File.read(path)
      expect_raises(ConflictError) do
        Persistence.write(path, "replacement") { raise ConflictError.new("external edit detected") }
      end
      File.read(path).should eq(before)
      Dir.glob(File.join(project.root, ".worldmyth-*.tmp")).should be_empty
    end
  end

  it "recovers the previous package even when the next source validation fails" do
    with_world do |project|
      dist = Compiler.new(project.root).build
      bytes = File.read(File.join(dist, "world.sqlite"))
      File.rename(dist, File.join(project.root, ".dist-backup"))
      File.write(File.join(project.root, "terrain.yaml"), "invalid: [")
      expect_raises(DocumentError) { Compiler.new(project.root).build }
      File.read(File.join(dist, "world.sqlite")).should eq(bytes)
    end
  end

  it "rejects a second concurrent compiler without altering the existing output" do
    with_world do |project|
      dist = Compiler.new(project.root).build
      before = File.read(File.join(dist, "world.sqlite"))
      File.open(File.join(project.root, ".worldmyth/build.lock"), "w") do |lock|
        lock.flock_exclusive
        expect_raises(IO::Error) { Compiler.new(project.root).build }
      end
      File.read(File.join(dist, "world.sqlite")).should eq(before)
    end
  end
end
