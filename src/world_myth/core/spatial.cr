module WorldMyth::Core
  DIRECTIONS = %w(N NE E SE S SW W NW)

  # Every source row stays compact; empty surface cells are ASCII spaces.
  class Surface
    include YAML::Serializable
    include YAML::Serializable::Strict
    property id : String
    property kind : String
    property terrain : Array(String)
    property collision : Array(String)
    property elevation : Array(String)
    property shapes : Array(String)
    @[YAML::Field(ignore: true)]
    @height_rows = {} of Int32 => Array(Int32)

    def initialize(@id, @kind, @terrain, @collision, @elevation, @shapes)
    end

    def self.blank(id : String, kind : String, width : Int32, height : Int32, z = 0)
      new(id, kind, Array.new(height, " " * width), Array.new(height, "." * width), Array.new(height, Array.new(width, z).join(' ')), Array.new(height, "." * width))
    end

    def symbol(x : Int32, y : Int32) : String
      terrain[y].byte_at(x).chr.to_s
    end

    def height_at(x : Int32, y : Int32) : Int32
      elevation.empty? ? 0 : (@height_rows[y] ||= elevation[y].split.map(&.to_i))[x]
    end

    def shape(x : Int32, y : Int32) : Char
      shapes.empty? ? '.' : shapes[y].byte_at(x).chr
    end

    def self.rise(shape : Char, u : Float64, v : Float64) : Float64
      value = case shape.downcase
              when 'n' then 1.0 - v
              when 's' then v
              when 'e' then u
              when 'w' then 1.0 - u
              else          0.0
              end
      shape.uppercase? ? (value * 4).floor / 4 : value
    end

    def z(x : Int32, y : Int32, u = 0.5, v = 0.5) : Float64
      height_at(x, y) + self.class.rise(shape(x, y), u, v)
    end

    def set(layer : String, x : Int32, y : Int32, value : String)
      if layer == "height"
        row = elevation[y].split
        row[x] = value.to_i.to_s
        elevation[y] = row.join(' ')
        @height_rows.delete(y)
      else
        rows = case layer
               when "terrain"   then terrain
               when "collision" then collision
               when "shape"     then shapes
               else                  raise DocumentError.new("Unknown surface layer #{layer}")
               end
        bytes = rows[y].to_slice.dup
        bytes[x] = value.byte_at(0)
        rows[y] = String.new(bytes)
      end
    end
  end

  class Wall
    include YAML::Serializable
    include YAML::Serializable::Strict
    property id : String
    property surface : String = "ground"
    property x : Int32
    property y : Int32
    property edge : String = "N"
    property height : Int32 = 4
    property material : String

    def initialize(@id, @x, @y, @material)
    end
  end

  class Ink
    include YAML::Serializable
    include YAML::Serializable::Strict
    property glyph : String
    property foreground : String = "#e6b566"
    property background : String? = nil

    def initialize(@glyph, @foreground = "#e6b566", @background = nil)
    end
  end

  class SpriteFrame
    include YAML::Serializable
    include YAML::Serializable::Strict
    property rows : Array(String)
    property duration_ms : Int32 = 150

    def initialize(@rows, @duration_ms = 150)
    end
  end

  class Animation
    include YAML::Serializable
    include YAML::Serializable::Strict
    property loop : Bool = true
    property directions : Hash(String, Array(SpriteFrame))

    def initialize(@directions)
    end

    def frame(direction : String, fallback : String, time_ms : Int64) : SpriteFrame
      frames = directions[direction]? || directions[fallback]
      total = frames.sum(&.duration_ms).to_i64
      time = loop ? time_ms % total : Math.min(time_ms, total - 1)
      frames.each do |frame|
        return frame if time < frame.duration_ms
        time -= frame.duration_ms
      end
      frames.last
    end
  end

  class Sprite
    include YAML::Serializable
    include YAML::Serializable::Strict
    property schema_version : Int32 = 2
    property id : String
    property name : String
    property width : Int32
    property height : Int32
    property anchor_x : Int32
    property anchor_y : Int32
    property default_direction : String = "S"
    property palette : Hash(String, Ink)
    property animations : Hash(String, Animation)

    def initialize(@id, @name, @width, @height)
      @anchor_x = width // 2
      @anchor_y = height - 1
      @palette = {"x" => Ink.new("█")}
      @animations = {"idle" => Animation.new({"S" => [SpriteFrame.new(Array.new(height, " " * width))]})}
    end

    def frame(animation : String, facing : String, time_ms : Int64)
      animations[animation].frame(facing, default_direction, time_ms)
    end
  end

  module Glyphs
    # Pinned art alphabet. Ambiguous-width text symbols are tested with Kitty
    # and a monospace font; emoji, bidi and combining sequences are not accepted.
    def self.allowed?(text : String) : Bool
      return false unless text.size == 1
      c = text[0]
      (c >= ' ' && c <= '~') || (c.ord >= 0x2500 && c.ord <= 0x259f) || "·♣♠♥♦⚒".includes?(c)
    end
  end
end
