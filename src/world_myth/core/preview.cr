module WorldMyth::Core
  # A read-only projection shared by terminal preview and the desktop launcher.
  class Preview
    getter map : Map
    getter reference : String
    getter catalog : Catalog
    getter analysis : Analysis
    getter entities = {} of Tuple(Int32, Int32) => Entity

    def initialize(@analysis : Analysis, reference : String)
      unless analysis.valid?
        raise DocumentError.new("Preview requires a valid world:\n" + analysis.diagnostics.select(&.severity.error?).join('\n'))
      end
      @reference = analysis.resolve_map(reference) || raise DocumentError.new("Unknown or ambiguous map: #{reference}")
      @map = analysis.maps[@reference]
      @catalog = analysis.catalog.not_nil!
      map.layers.objects.each { |object| entities[{object.x, object.y}] = analysis.entities[object.entity] }
      analysis.entities.keys.sort.each do |id|
        entity = analysis.entities[id]
        if position = entity.position
          if analysis.resolve_map(position.map) == @reference
            entities[{position.x, position.y}] = entity
          end
        end
      end
    end

    def cell(x : Int32, y : Int32) : Tuple(String, String, String)
      terrain = catalog.terrain[map.terrain_at(x, y)]
      if entity = entities[{x, y}]?
        {entity.glyph, entity.foreground, terrain.background}
      else
        {terrain.glyph, terrain.foreground, terrain.background}
      end
    end
  end
end
