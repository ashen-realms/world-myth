module WorldMyth::Core
  class World
    include YAML::Serializable
    include YAML::Serializable::Strict
    property schema_version : Int32
    property id : String
    property name : String
    property version : String
    property description : String = ""
    property default_region : String
  end

  class Region
    include YAML::Serializable
    include YAML::Serializable::Strict
    property schema_version : Int32
    property id : String
    property name : String
    property maps : Array(String)
  end

  class Terrain
    include YAML::Serializable
    include YAML::Serializable::Strict
    property glyph : String
    property foreground : String
    property background : String = "#101816"
    property passable : Bool
    property movement_cost : Float64
    property sprite : String? = nil
    property side_sprite : String? = nil
  end

  class Catalog
    include YAML::Serializable
    include YAML::Serializable::Strict
    property schema_version : Int32
    property terrain : Hash(String, Terrain)
  end

  class Position
    include YAML::Serializable
    include YAML::Serializable::Strict
    property map : String
    property x : Int32
    property y : Int32
    property surface : String = "ground"
    property facing : String = "S"

    def initialize(@map, @x, @y)
    end
  end

  class Entity
    include YAML::Serializable
    include YAML::Serializable::Strict
    property schema_version : Int32
    property id : String
    property type : String
    property name : String
    property tags : Array(String) = [] of String
    property position : Position?
    property properties : Hash(String, YAML::Any) = {} of String => YAML::Any
    property sprite : String? = nil
    property animation : String = "idle"

    def glyph : String
      properties["glyph"]?.try(&.as_s?) || {"npc" => "@", "item" => "!", "monster" => "M", "object" => "+"}[type]? || "?"
    end

    def foreground : String
      properties["foreground"]?.try(&.as_s?) || "#e6b566"
    end
  end

  class Placement
    include YAML::Serializable
    include YAML::Serializable::Strict
    property id : String
    property entity : String
    property x : Int32
    property y : Int32
    property surface : String = "ground"
    property facing : String = "S"

    def initialize(@id, @entity, @x, @y)
    end
  end

  class Layers
    include YAML::Serializable
    include YAML::Serializable::Strict
    property terrain : Array(String)
    property collision : Array(String)
    property objects : Array(Placement) = [] of Placement
    property elevation : Array(String) = [] of String
    property shapes : Array(String) = [] of String
  end

  class Map
    include YAML::Serializable
    include YAML::Serializable::Strict
    property schema_version : Int32
    property id : String
    property name : String
    property width : Int32
    property height : Int32
    property default_terrain : String
    property legend : Hash(String, String)
    property layers : Layers
    property surfaces : Array(Surface) = [] of Surface
    property walls : Array(Wall) = [] of Wall

    def surface(id = "ground") : Surface
      return surfaces.find { |s| s.id == id } || raise DocumentError.new("Unknown surface #{id}") unless id == "ground"
      Surface.new("ground", "ground", layers.terrain, layers.collision, layers.elevation, layers.shapes)
    end

    def all_surfaces : Array(Surface)
      [surface] + surfaces
    end

    def inside?(x : Int32, y : Int32) : Bool
      x >= 0 && y >= 0 && x < width && y < height
    end

    def symbol_at(layer : String, x : Int32, y : Int32) : String
      raise ArgumentError.new("Coordinates outside map") unless inside?(x, y)
      rows = layer == "terrain" ? layers.terrain : layers.collision
      rows[y].byte_at(x).chr.to_s
    end

    def terrain_at(x : Int32, y : Int32) : String
      legend[symbol_at("terrain", x, y)]
    end

    def set_symbol(layer : String, x : Int32, y : Int32, symbol : String)
      raise ArgumentError.new("Coordinates outside map") unless inside?(x, y)
      raise ArgumentError.new("Expected one ASCII symbol") unless symbol.bytesize == 1 && symbol.ascii_only?
      rows = case layer
             when "terrain"   then layers.terrain
             when "collision" then layers.collision
             else                  raise ArgumentError.new("Unknown cell layer: #{layer}")
             end
      bytes = rows[y].to_slice.dup
      bytes[x] = symbol.to_slice[0]
      rows[y] = String.new(bytes)
    end

    def symbol_for(terrain : String) : String
      legend.key_for?(terrain) || raise ArgumentError.new("Terrain #{terrain} is absent from the map legend")
    end
  end

  alias Definition = World | Region | Catalog | Map | Entity | Sprite

  enum Severity
    Error
    Warning
  end

  record Diagnostic, severity : Severity, code : String, message : String,
    path : String, line : Int32? = nil, column : Int32? = nil do
    def to_s(io : IO)
      io << path
      io << ':' << line if line
      io << ':' << column if column
      io << ": " << severity.to_s.downcase << " [" << code << "] " << message
    end
  end

  class DocumentError < Exception
  end

  class ConflictError < DocumentError
  end

  class NormalizationRequired < DocumentError
  end
end
