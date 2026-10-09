module WorldMyth::Core
  class Analysis
    ID    = /\A[a-z][a-z0-9_.-]*\z/
    COLOR = /\A#[0-9a-fA-F]{6}\z/
    getter sources : Hash(String, String)
    getter diagnostics = [] of Diagnostic
    getter world : World?
    getter catalog : Catalog?
    getter regions = {} of String => Region
    getter maps = {} of String => Map
    getter entities = {} of String => Entity
    getter paths = {} of String => String
    getter parsed = {} of String => Definition
    @region_folders = {} of String => String

    def initialize(@sources)
      load
      validate
      @diagnostics.sort_by! { |d| {d.path, d.line || 0, d.code, d.message} }
    end

    def valid? : Bool
      !diagnostics.any?(&.severity.error?)
    end

    def error(code : String, message : String, path : String, field : String? = nil)
      line = nil.as(Int32?)
      column = nil.as(Int32?)
      if field && (text = sources[path]?)
        Source.inspect_tree(Source.tree(text)) do |node|
          if line.nil? && node.is_a?(YAML::Nodes::Scalar) && node.value == field
            line, column = node.start_line, node.start_column
          end
        end
      end
      diagnostics << Diagnostic.new(Severity::Error, code, message, path, line, column)
    end

    def resolve_map(reference : String) : String?
      return maps.has_key?(reference) ? reference : nil if reference.includes?('/')
      matches = maps.keys.select { |key| key.split('/').last == reference }
      matches.size == 1 ? matches.first : nil
    end

    def editable_map?(path : String) : Bool
      parsed[path]?.is_a?(Map) && !diagnostics.any? { |d| d.path == path && d.severity.error? }
    end

    private def load
      {"world.yaml", "terrain.yaml"}.each do |file|
        error("missing_file", "Required file is missing", file) unless sources.has_key?(file)
      end
      sources.keys.sort.each do |path|
        next if Source.kind(path) == "lore"
        if Source.kind(path) == "source"
          error("unexpected_file", "Unrecognized world source location", path)
          next
        end
        begin
          if definition = Source.parse(path, sources[path])
            parsed[path] = definition
            error("schema_version", "Unsupported schema version #{definition.schema_version}; expected 1", path, "schema_version") unless definition.schema_version == 1
          end
        rescue ex : YAML::ParseException
          diagnostics << Diagnostic.new(Severity::Error, "yaml", ex.message || "Malformed YAML", path, ex.line_number, ex.column_number)
        rescue ex
          error("structure", ex.message || "Invalid document", path)
        end
      end
      parsed.each do |path, value|
        case value
        when World
          @world = value
          identifier(value.id, path)
        when Catalog
          @catalog = value
        when Region
          identifier(value.id, path)
          insert(regions, value.id, value, path, "region")
          @region_folders[File.dirname(path)] = value.id
        when Entity
          identifier(value.id, path)
          insert(entities, value.id, value, path, "entity")
        end
      end
      parsed.each do |path, value|
        next unless value.is_a?(Map)
        identifier(value.id, path)
        directory = File.dirname(File.dirname(path))
        if region = @region_folders[directory]?
          key = "#{region}/#{value.id}"
          insert(maps, key, value, path, "map")
        else
          error("missing_region", "No region.yaml for this map", path)
        end
      end
    end

    private def insert(hash : Hash(String, T), key : String, value : T, path : String, kind : String) forall T
      if hash.has_key?(key)
        error("duplicate_id", "Duplicate #{kind} ID #{key}; first defined in #{paths["#{kind}:#{key}"]}", path, "id")
      else
        hash[key] = value
        paths["#{kind}:#{key}"] = path
      end
    end

    private def identifier(id : String, path : String)
      error("invalid_id", "Invalid ID #{id.inspect}; expected #{ID.source}", path, "id") unless ID.matches?(id)
    end

    private def validate
      if w = world
        error("default_region", "Default region #{w.default_region.inspect} does not exist", "world.yaml", "default_region") unless regions.has_key?(w.default_region)
        error("world_name", "World name and version cannot be empty", "world.yaml") if w.name.strip.empty? || w.version.strip.empty?
      end
      regions.each do |id, region|
        path = paths["region:#{id}"]
        error("duplicate_reference", "Region contains duplicate map references", path, "maps") unless region.maps.uniq == region.maps
        region.maps.each do |map|
          error("missing_map", "Map #{id}/#{map} has no valid source file", path, "maps") unless maps.has_key?("#{id}/#{map}")
        end
        maps.each do |key, map|
          if key.starts_with?(id + "/") && !region.maps.includes?(map.id)
            error("unlisted_map", "Map #{key} is not listed by its region", paths["map:#{key}"], "id")
          end
        end
      end
      if terrain = catalog
        error("terrain_empty", "At least one terrain is required", "terrain.yaml") if terrain.terrain.empty?
        terrain.terrain.each do |id, tile|
          identifier(id, "terrain.yaml")
          error("terrain_glyph", "Terrain #{id} requires one printable grapheme", "terrain.yaml", id) unless glyph?(tile.glyph)
          error("terrain_color", "Terrain #{id} colors must use #RRGGBB", "terrain.yaml", id) unless COLOR.matches?(tile.foreground) && COLOR.matches?(tile.background)
          if !tile.movement_cost.finite? || tile.movement_cost < 0 || (tile.passable && tile.movement_cost <= 0)
            error("movement_cost", "Terrain #{id} needs a finite nonnegative cost, positive when passable", "terrain.yaml", id)
          end
        end
      end
      maps.each { |key, map| validate_map(key, map) }
      entities.each { |id, entity| validate_entity(id, entity) }
    end

    private def glyph?(value : String) : Bool
      value.graphemes.size == 1 && !value.each_char.any? { |c| c.control? }
    end

    private def validate_map(key : String, map : Map)
      path = paths["map:#{key}"]
      if map.width <= 0 || map.height <= 0 || map.width.to_i64 * map.height > 4_194_304
        error("dimensions", "Map dimensions must be positive and contain at most 4,194,304 cells", path, "width")
      end
      error("default_terrain", "Default terrain must exist in the legend", path, "default_terrain") unless map.legend.has_value?(map.default_terrain)
      map.legend.each do |symbol, terrain|
        unless symbol.bytesize == 1 && symbol.ascii_only? && symbol.byte_at(0) >= 33 && symbol.byte_at(0) <= 126
          error("legend_symbol", "Legend symbols must be single printable non-space ASCII characters", path, "legend")
        end
        error("terrain_reference", "Undefined terrain #{terrain}", path, "legend") unless catalog.try(&.terrain.has_key?(terrain))
      end
      {"terrain" => map.layers.terrain, "collision" => map.layers.collision}.each do |layer, rows|
        error("layer_height", "#{layer} has #{rows.size} rows; expected #{map.height}", path, layer) unless rows.size == map.height
        rows.each_with_index do |row, y|
          if row.bytesize != map.width || !row.ascii_only?
            error("layer_width", "#{layer} row #{y} must have #{map.width} ASCII symbols", path, layer)
            next
          end
          unknown = row.chars.uniq.reject { |c| layer == "terrain" ? map.legend.has_key?(c.to_s) : ".#+".includes?(c) }
          error("undefined_symbol", "#{layer} row #{y} contains undefined symbols #{unknown.join}", path, layer) unless unknown.empty?
        end
      end
      seen = Set(String).new
      map.layers.objects.each do |object|
        identifier(object.id, path)
        error("duplicate_placement", "Duplicate object placement #{object.id}", path, "objects") unless seen.add?(object.id)
        error("object_reference", "#{object.entity} must reference a world-object entity", path, "objects") unless entities[object.entity]?.try(&.type) == "object"
        error("coordinates", "Object #{object.id} is outside #{key}", path, "objects") unless map.inside?(object.x, object.y)
      end
    end

    private def validate_entity(id : String, entity : Entity)
      path = paths["entity:#{id}"]
      error("entity_type", "Supported types: npc, item, monster, object", path, "type") unless {"npc", "item", "monster", "object"}.includes?(entity.type)
      error("entity_name", "Entity name cannot be empty", path, "name") if entity.name.strip.empty?
      error("entity_tags", "Tags must be nonempty and unique", path, "tags") if entity.tags.any?(&.strip.empty?) || entity.tags.uniq != entity.tags
      if pos = entity.position
        if key = resolve_map(pos.map)
          error("coordinates", "Entity position (#{pos.x},#{pos.y}) is outside #{key}", path, "position") unless maps[key].inside?(pos.x, pos.y)
        else
          error("map_reference", "Unknown or ambiguous map #{pos.map}; use region/map", path, "position")
        end
      end
      entity.properties.each do |name, value|
        if name.empty? || value.raw.is_a?(Array) || value.raw.is_a?(Hash) || (value.raw.is_a?(Float64) && !value.as_f.finite?)
          error("entity_property", "Property #{name.inspect} must be a finite scalar with a nonempty key", path, "properties")
        end
      end
      if value = entity.properties["glyph"]?
        error("entity_glyph", "glyph must be one printable grapheme", path, "properties") unless value.as_s?.try { |s| glyph?(s) }
      end
      if value = entity.properties["foreground"]?
        error("entity_color", "foreground must use #RRGGBB", path, "properties") unless value.as_s?.try { |s| COLOR.matches?(s) }
      end
    end
  end
end
