module WorldMyth::Core
  class Project
    getter root : String
    getter documents = {} of String => Document

    def initialize(path : String)
      @root = File.realpath(path)
      raise DocumentError.new("No world.yaml in #{@root}") unless File.file?(File.join(root, "world.yaml"))
      discover.each do |relative|
        content = File.read(File.join(root, relative))
        documents[relative] = Document.new(relative, content, Digest::SHA256.hexdigest(content))
      end
    end

    def discover : Array(String)
      files = ["world.yaml", "terrain.yaml"].select { |p| File.file?(File.join(root, p)) }
      {"regions", "entities", "lore"}.each do |directory|
        Dir.glob(File.join(root, directory, "**", "*")).sort.each do |full|
          next unless File.file?(full)
          relative = Path[full].relative_to(root).to_s
          next unless {".yaml", ".yml", ".md"}.includes?(File.extname(full))
          raise DocumentError.new("Source symlinks must stay inside the project: #{relative}") unless File.realpath(full).starts_with?(root + "/")
          files << relative
        end
      end
      files.sort
    end

    def snapshot : Hash(String, String)
      # Refresh discovery while retaining open/dirty buffers.
      paths = (discover + documents.values.select(&.dirty?).map(&.path)).uniq.sort
      paths.to_h do |path|
        document = documents[path]?
        {path, document && document.dirty? ? document.text : File.read(File.join(root, path))}
      end
    end

    def analyze : Analysis
      Analysis.new(snapshot)
    end

    def dirty? : Bool
      documents.values.any?(&.dirty?)
    end

    def save_all
      documents.each_value { |doc| doc.save(root) if doc.dirty? }
    end

    def refresh_clean : Array(String)
      conflicts = [] of String
      documents.each_value do |doc|
        next unless doc.external_change?(root)
        if doc.dirty? || !File.file?(File.join(root, doc.path))
          conflicts << doc.path
        else
          doc.reload(root)
        end
      end
      discover.each do |path|
        next if documents.has_key?(path)
        content = File.read(File.join(root, path))
        documents[path] = Document.new(path, content, Digest::SHA256.hexdigest(content))
      end
      conflicts
    end

    def self.create(path : String, name : String) : Project
      raise DocumentError.new("Destination already exists: #{path}") if File.exists?(path)
      id = name.downcase.gsub(/[^a-z0-9_.-]+/, "-").strip('-')
      id = "world-#{id}" unless id.matches?(/\A[a-z]/)
      raise DocumentError.new("World name cannot be empty") if name.strip.empty?
      parent = File.dirname(File.expand_path(path))
      raise DocumentError.new("Parent directory does not exist: #{parent}") unless Dir.exists?(parent)
      staging = File.join(parent, ".worldmyth-new-#{Random::Secure.hex(8)}")
      Dir.mkdir(staging)
      begin
        {"regions/heartlands/maps", "entities/npcs", "entities/items", "entities/monsters", "entities/objects", "lore", ".worldmyth"}.each do |directory|
          FileUtils.mkdir_p(File.join(staging, directory))
        end
        write = ->(file : String, text : String) { File.write(File.join(staging, file), text) }
        write.call("world.yaml", <<-YAML)
        schema_version: 1
        id: #{id.to_json}
        name: #{name.to_json}
        version: "0.1.0"
        description: "A world waiting for its stories."
        default_region: heartlands
        YAML
        write.call("terrain.yaml", <<-YAML)
        schema_version: 1
        terrain:
          grass:
            glyph: "."
            foreground: "#88aa66"
            background: "#101816"
            passable: true
            movement_cost: 1.0
          forest:
            glyph: "♣"
            foreground: "#447744"
            passable: true
            movement_cost: 1.5
          wall:
            glyph: "#"
            foreground: "#aaaaaa"
            passable: false
            movement_cost: 0.0
          water:
            glyph: "~"
            foreground: "#74b4e0"
            passable: false
            movement_cost: 0.0
          floor:
            glyph: "·"
            foreground: "#c6b895"
            passable: true
            movement_cost: 1.0
        YAML
        write.call("regions/heartlands/region.yaml", "schema_version: 1\nid: heartlands\nname: Heartlands\nmaps:\n  - meadow\n")
        write.call("regions/heartlands/maps/meadow.yaml", map_template("meadow", "Quiet Meadow", 32, 20))
        write.call("lore/introduction.md", "# #{name}\n\nEvery path begins with a story.\n")
        write.call(".worldmyth/project.yaml", "schema_version: 1\n")
        write.call(".gitignore", "dist/\n.dist-*/\n.worldmyth/*.local.yaml\n.worldmyth/build.lock\n")
        File.rename(staging, path)
      ensure
        FileUtils.rm_r(staging) if Dir.exists?(staging)
      end
      new(path)
    end

    def self.map_template(id : String, name : String, width : Int32, height : Int32) : String
      rows = Array.new(height) { "g" * width }
      collision = Array.new(height) { "." * width }
      <<-YAML
      schema_version: 1
      id: #{id.to_json}
      name: #{name.to_json}
      width: #{width}
      height: #{height}
      default_terrain: grass
      legend:
        g: grass
        f: forest
        w: wall
        a: water
        d: floor
      layers:
        terrain:
      #{rows.map { |r| "    - #{r.to_json}" }.join('\n')}
        collision:
      #{collision.map { |r| "    - #{r.to_json}" }.join('\n')}
        objects: []
      YAML
    end
  end
end
