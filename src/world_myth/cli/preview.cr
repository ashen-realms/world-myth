require "io/console"

# Linux terminal size API; no GTK initialization or external helper process.
lib WorldMythTerminal
  struct Size
    rows : UInt16
    columns : UInt16
    xpixel : UInt16
    ypixel : UInt16
  end

  fun ioctl(fd : Int32, request : UInt64, size : Size*) : Int32
end

module WorldMyth::CLI
  class TerminalPreview
    getter x = 0
    getter y = 0

    getter camera = Core::SceneCamera.new
    @renderer : Core::SceneRenderer
    @paused = false
    @time_ms = 0_i64
    @previous : Array(Tuple(String, String, String))? = nil
    @previous_size = {0, 0}

    def initialize(@preview : Core::Preview)
      @renderer = Core::SceneRenderer.new(@preview.map, @preview.analysis, @preview.reference)
    end

    def move(dx : Int32, dy : Int32)
      @x = (x + dx).clamp(0, @preview.map.width - 1)
      @y = (y + dy).clamp(0, @preview.map.height - 1)
    end

    def frame(columns : Int32, rows : Int32, incremental = false) : String
      camera.u = 4.0 * (x - y) - columns / 2.0
      camera.v = x + y - 3.0
      scene = @renderer.render(columns, Math.max(rows - 2, 0), camera, @time_ms)
      previous = incremental && @previous_size == {columns, rows} ? @previous : nil
      current = scene.cells.map { |c| {c.glyph, c.foreground, c.background} }
      @previous, @previous_size = current, {columns, rows}
      String.build do |io|
        io << (previous ? "\e[0m\e[H\e[2K" : "\e[0m\e[2J\e[H")
        title = "World Myth | #{@preview.reference} | X:#{x} Y:#{y} | #{camera.active_surface}"
        io << title[0, Math.max(columns - 1, 0)]
        scene.cells.each_with_index do |cell, index|
          next if previous && previous[index]? == current[index]
          io << "\e[#{index // columns + 2};#{index % columns + 1}H" << color(cell.background, 48) << color(cell.foreground, 38) << cell.glyph
        end
        if rows >= 2
          io << "\e[0m\e[#{rows};1H" << "WASD:pan Tab:floor C:cut R:roof Space:pause A:clip Q:exit"[0, Math.max(columns - 1, 0)]
        end
      end
    end

    private def color(hex : String, mode : Int32) : String
      "\e[#{mode};2;#{hex[1, 2].to_i(16)};#{hex[3, 2].to_i(16)};#{hex[5, 2].to_i(16)}m"
    end

    private def size(output : IO::FileDescriptor) : Tuple(Int32, Int32)
      dimensions = WorldMythTerminal::Size.new
      if WorldMythTerminal.ioctl(output.fd, 0x5413_u64, pointerof(dimensions)) == 0 && dimensions.columns > 0 && dimensions.rows > 0
        {dimensions.columns.to_i, dimensions.rows.to_i}
      else
        {80, 24}
      end
    end

    def run(input : IO::FileDescriptor = STDIN, output : IO::FileDescriptor = STDOUT)
      raise Core::DocumentError.new("Preview needs an interactive terminal.") unless input.tty? && output.tty?
      previous_timeout = input.read_timeout
      input.raw do
        begin
          output << "\e[?1049h\e[?25l"
          input.read_timeout = 33.milliseconds
          previous_time = Time.instant
          last_size = {0, 0}
          redraw = true
          escape = 0
          loop do
            now = Time.instant
            @time_ms += (now - previous_time).total_milliseconds.to_i64 unless @paused
            previous_time = now
            redraw ||= @renderer.animated && !@paused
            dimensions = size(output)
            if redraw || dimensions != last_size
              output << frame(*dimensions, true)
              output.flush
              last_size = dimensions
              redraw = false
            end
            begin
              byte = input.read_byte
              break unless byte
              case escape
              when 1
                escape = byte == 91 || byte == 79 ? 2 : 0
              when 2
                case byte
                when 65 then move(0, -1)
                when 66 then move(0, 1)
                when 67 then move(1, 0)
                when 68 then move(-1, 0)
                end
                escape = 0
              else
                case byte
                when 113, 81, 3, 4 then break
                when 9
                  surfaces = @preview.map.all_surfaces.map(&.id)
                  camera.active_surface = surfaces[((surfaces.index(camera.active_surface) || 0) + 1) % surfaces.size]
                when 32  then @paused = !@paused
                when 99  then camera.cutaway = !camera.cutaway
                when 114 then camera.roofs = !camera.roofs
                when 65
                  clips = @preview.analysis.sprites.values.flat_map { |s| s.animations.keys }.uniq.sort
                  camera.animation = clips[((clips.index(camera.animation) || -1) + 1) % clips.size] unless clips.empty?
                when 27      then escape = 1
                when 119, 87 then move(0, -1)
                when 115, 83 then move(0, 1)
                when 97      then move(-1, 0)
                when 100, 68 then move(1, 0)
                end
              end
              redraw = true
            rescue IO::TimeoutError
              break if escape == 1
              escape = 0
            end
          end
        ensure
          input.read_timeout = previous_timeout
          output << "\e[0m\e[?25h\e[?1049l"
          output.flush
        end
      end
    end
  end
end
