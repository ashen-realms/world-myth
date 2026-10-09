require "../spec/support/spatial_fixture"
include WorldMyth::Core
sources = SpatialFixture.with_world { |project| project.snapshot }
map = Map.from_yaml(Project.map_template("meadow", "Benchmark", 256, 256))
map.schema_version = 2
map.layers.elevation = Array.new(256, Array.new(256, 0).join(' '))
map.layers.shapes = Array.new(256, "." * 256)
2.times do |i|
  surface = Surface.blank("floor-#{i}", "floor", 256, 256, (i + 1) * 5)
  (4..12).each { |y| (4..12).each { |x| surface.set("terrain", x, y, "d") } }
  map.surfaces << surface
end
sources["regions/heartlands/maps/meadow.yaml"] = map.to_yaml
100.times do |i|
  entity = Entity.from_yaml(sources["entities/npcs/ulf.yaml"])
  entity.id = "npc.benchmark.#{i}"
  entity.position = Position.new("heartlands/meadow", i % 10 + 4, i // 10 + 4)
  sources["entities/npcs/benchmark-#{i}.yaml"] = entity.to_yaml
end
start = Time.instant
analysis = Analysis.new(sources)
raise analysis.diagnostics.join('\n') unless analysis.valid?
puts "METRIC analysis_ms=#{(Time.instant - start).total_milliseconds.round(2)}"
start = Time.instant
renderer = SceneRenderer.new(map, analysis, "heartlands/meadow")
puts "METRIC prepare_ms=#{(Time.instant - start).total_milliseconds.round(2)} primitives=#{renderer.primitives.size}"
camera = SceneCamera.new
camera.u, camera.v = -60.0, 0.0
samples = Array.new(40) do |i|
  start = Time.instant
  renderer.render(120, 40, camera, i * 33_i64)
  (Time.instant - start).total_milliseconds
end.sort
puts "METRIC frame_p50_ms=#{samples[20].round(2)} frame_p95_ms=#{samples[38].round(2)} candidates=#{renderer.last_candidates}"
