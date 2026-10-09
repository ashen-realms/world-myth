module WorldMyth::Core
  # A detached map preview; releasing a gesture commits one source transaction.
  class Stroke
    getter map : Map
    getter changed = false
    @revision : Int64
    @last : Tuple(Int32, Int32)?

    def initialize(@document : Document, @layer : String, @value : String, @erase = false)
      raise NormalizationRequired.new("Normalize this YAML before visual editing") if @document.sensitive?
      @map = Source.parse(@document.path, @document.text).as(Map)
      @revision = @document.revision
    end

    def visit(x : Int32, y : Int32)
      return unless map.inside?(x, y)
      if last = @last
        self.class.line(last[0], last[1], x, y) { |cx, cy| paint(cx, cy) }
      else
        paint(x, y)
      end
      @last = {x, y}
    end

    def commit
      @document.replace(map.to_yaml, @erase ? "Erase #{@layer}" : "Paint #{@layer}", @revision) if changed
    end

    def self.line(x0 : Int32, y0 : Int32, x1 : Int32, y1 : Int32, &)
      dx, dy = (x1 - x0).abs, -(y1 - y0).abs
      sx, sy = x0 < x1 ? 1 : -1, y0 < y1 ? 1 : -1
      error = dx + dy
      loop do
        yield x0, y0
        break if x0 == x1 && y0 == y1
        e2 = 2 * error
        if e2 >= dy
          error += dy
          x0 += sx
        end
        if e2 <= dx
          error += dx
          y0 += sy
        end
      end
    end

    private def paint(x : Int32, y : Int32)
      case @layer
      when "terrain", "collision"
        symbol = if @layer == "terrain"
                   map.symbol_for(@erase ? map.default_terrain : @value)
                 else
                   @erase ? "." : @value
                 end
        return if map.symbol_at(@layer, x, y) == symbol
        map.set_symbol(@layer, x, y, symbol)
      when "objects"
        existing = map.layers.objects.select { |p| p.x == x && p.y == y }
        return if @erase && existing.empty?
        return if !@erase && existing.size == 1 && existing.first.entity == @value
        map.layers.objects.reject! { |p| p.x == x && p.y == y }
        unless @erase
          id = "object-#{x}-#{y}"
          while map.layers.objects.any? { |p| p.id == id }
            id += "-copy"
          end
          map.layers.objects << Placement.new(id, @value, x, y)
        end
      else
        raise ArgumentError.new("Unknown layer #{@layer}")
      end
      @changed = true
    end
  end

  class Viewport
    property offset_x = 24.0
    property offset_y = 24.0
    property cell_width = 20.0
    property cell_height = 26.0
    getter zoom = 1.0

    def cell(x : Float64, y : Float64) : Tuple(Int32, Int32)
      {((x - offset_x) / (cell_width * zoom)).floor.to_i, ((y - offset_y) / (cell_height * zoom)).floor.to_i}
    end

    def zoom_at(factor : Float64, x : Float64, y : Float64)
      old = zoom
      @zoom = (zoom * factor).clamp(0.25, 4.0)
      @offset_x = x - (x - offset_x) * zoom / old
      @offset_y = y - (y - offset_y) * zoom / old
    end
  end
end
