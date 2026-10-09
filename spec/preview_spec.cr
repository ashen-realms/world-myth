require "./spec_helper"

describe WorldMyth::Core::Preview do
  it "includes unsaved terrain and entities without writing source files" do
    with_world do |project|
      doc = map_document(project)
      original = File.read(File.join(project.root, doc.path))
      doc.edit("Paint") { |model| model.as(Map).set_symbol("terrain", 0, 0, "f") }
      File.write(File.join(project.root, "entities/npcs/ulf.yaml"), entity_yaml)
      preview = Preview.new(project.analyze, "meadow")
      preview.reference.should eq("heartlands/meadow")
      preview.cell(0, 0)[0].should eq("♣")
      preview.cell(2, 3)[0].should eq("@")
      File.read(File.join(project.root, doc.path)).should eq(original)
      doc.dirty?.should be_true
    end
  end

  it "renders object placements and refuses broken references" do
    project = Project.new(File.expand_path("../examples/example-world", __DIR__))
    preview = Preview.new(project.analyze, "heartlands/village")
    preview.cell(5, 4)[0].should eq("⚒")
    expect_raises(DocumentError, /Unknown or ambiguous map/) { Preview.new(project.analyze, "missing") }
    sources = project.snapshot
    sources["terrain.yaml"] = "invalid: ["
    expect_raises(DocumentError, /Preview requires a valid world/) { Preview.new(Analysis.new(sources), "heartlands/village") }
  end

  it "clips large maps to a viewport and keeps wide glyphs on fixed cell boundaries" do
    with_world do |project|
      map_document(project).replace(Project.map_template("meadow", "Large", 256, 256))
      catalog = project.documents["terrain.yaml"]
      catalog.replace(catalog.text.sub("glyph: \".\"", "glyph: \"界\""))
      viewer = WorldMyth::CLI::TerminalPreview.new(Preview.new(project.analyze, "meadow"))
      frame = viewer.frame(11, 6)
      frame.should_not contain("界")
      frame.should contain("?")
      frame.should contain("\e[2;1H")
      frame.should contain("\e[2;3H")
      frame.should_not contain("\e[2;12H")
      viewer.move(-10, -10)
      {viewer.x, viewer.y}.should eq({0, 0})
      viewer.move(1000, 1000)
      {viewer.x, viewer.y}.should eq({255, 255})
      viewer.frame(11, 6).should_not contain("界")
      viewer.frame(1, 1).should_not contain("界")
    end
  end

  it "reports CLI usage errors for missing map and preview options on other commands" do
    output = IO::Memory.new
    err = IO::Memory.new
    WorldMyth::CLI.run(["preview"], output, err).should eq(2)
    WorldMyth::CLI.run(["validate", "--map", "meadow"], output, err).should eq(2)
    WorldMyth::CLI.run(["preview", ".", "--map", "meadow", "--snapshot", "anything"], output, err).should eq(2)
  end
end
