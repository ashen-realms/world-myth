require "spec"
require "../src/world_myth"
require "../src/world_myth/cli/runner"

include WorldMyth::Core

def with_world(&)
  directory = File.join(Dir.tempdir, "world-myth-spec-#{Random::Secure.hex(8)}")
  Dir.mkdir(directory)
  begin
    project = Project.create(File.join(directory, "world"), "Test World", 1)
    yield project
  ensure
    FileUtils.rm_r(directory)
  end
end

def map_document(project)
  project.documents["regions/heartlands/maps/meadow.yaml"]
end

def entity_yaml(id = "npc.ulf", type = "npc", position = "heartlands/meadow")
  <<-YAML
  schema_version: 1
  id: #{id}
  type: #{type}
  name: Ulf
  tags: [human, blacksmith]
  position:
    map: #{position}
    x: 2
    y: 3
  properties:
    greeting: Welcome
  YAML
end

require "./support/world_fixture"
