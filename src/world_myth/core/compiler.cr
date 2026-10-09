require "sqlite3"

module WorldMyth::Core
  class Compiler
    SCHEMA_VERSION = 1
    getter root : String

    def initialize(@root)
    end

    def build : String
      project = Project.new(root)
      lock_path = File.join(root, ".worldmyth", "build.lock")
      FileUtils.mkdir_p(File.dirname(lock_path))
      File.open(lock_path, "w") do |lock|
        lock.flock_exclusive(blocking: false)
        dist = File.join(root, "dist")
        backup = File.join(root, ".dist-backup")
        raise DocumentError.new("Build output and backup must not be symlinks") if File.symlink?(dist) || File.symlink?(backup)
        File.rename(backup, dist) if Dir.exists?(backup) && !File.exists?(dist)
        analysis = project.analyze
        raise DocumentError.new(analysis.diagnostics.join('\n')) unless analysis.valid?
        build_locked(analysis)
      end
    end

    private def build_locked(analysis : Analysis) : String
      dist = File.join(root, "dist")
      backup = File.join(root, ".dist-backup")
      raise DocumentError.new("dist must be an ordinary directory") if File.symlink?(dist) || (File.exists?(dist) && !Dir.exists?(dist))
      File.rename(backup, dist) if Dir.exists?(backup) && !File.exists?(dist)
      staging = File.join(root, ".dist-stage-#{Random::Secure.hex(8)}")
      Dir.mkdir(staging)
      begin
        database = File.join(staging, "world.sqlite")
        compile_database(database, analysis)
        checksum = Digest::SHA256.hexdigest(File.read(database))
        manifest = JSON.build do |json|
          json.object do
            json.field "schema_version", SCHEMA_VERSION
            json.field "compiler_version", WorldMyth::VERSION
            json.field "world_id", analysis.world.not_nil!.id
            json.field "world_version", analysis.world.not_nil!.version
            json.field "database", "world.sqlite"
            json.field "sha256", checksum
          end
        end
        File.write(File.join(staging, "manifest.json"), manifest + "\n")
        # All source data must still match the immutable snapshot before publication.
        raise ConflictError.new("World files changed during compilation; retry the build") unless Project.new(root).snapshot == analysis.sources
        publish(staging, dist, backup)
        dist
      ensure
        FileUtils.rm_r(staging) if Dir.exists?(staging)
      end
    end

    protected def publish(staging : String, dist : String, backup : String)
      FileUtils.rm_r(backup) if Dir.exists?(backup)
      File.rename(dist, backup) if Dir.exists?(dist)
      begin
        File.rename(staging, dist)
      rescue ex
        File.rename(backup, dist) if Dir.exists?(backup) && !File.exists?(dist)
        raise ex
      end
      FileUtils.rm_r(backup) if Dir.exists?(backup)
    end

    private def compile_database(path : String, a : Analysis)
      DB.open("sqlite3:#{path}") do |db|
        db.exec("PRAGMA foreign_keys = ON")
        db.exec("PRAGMA user_version = #{SCHEMA_VERSION}")
        db.transaction do |tx|
          connection = tx.connection
          statements = [
            "CREATE TABLE world (id TEXT PRIMARY KEY, name TEXT NOT NULL, version TEXT NOT NULL, description TEXT NOT NULL, default_region TEXT NOT NULL REFERENCES regions(id))",
            "CREATE TABLE regions (id TEXT PRIMARY KEY, name TEXT NOT NULL)",
            "CREATE TABLE terrain (id TEXT PRIMARY KEY, glyph TEXT NOT NULL, foreground TEXT NOT NULL, background TEXT NOT NULL, passable INTEGER NOT NULL CHECK(passable IN (0,1)), movement_cost REAL NOT NULL)",
            "CREATE TABLE maps (region_id TEXT NOT NULL REFERENCES regions(id), id TEXT NOT NULL, name TEXT NOT NULL, width INTEGER NOT NULL, height INTEGER NOT NULL, default_terrain TEXT NOT NULL REFERENCES terrain(id), PRIMARY KEY(region_id,id))",
            "CREATE TABLE layers (region_id TEXT NOT NULL, map_id TEXT NOT NULL, kind TEXT NOT NULL, width INTEGER NOT NULL, height INTEGER NOT NULL, PRIMARY KEY(region_id,map_id,kind), FOREIGN KEY(region_id,map_id) REFERENCES maps(region_id,id))",
            "CREATE TABLE cells (region_id TEXT NOT NULL, map_id TEXT NOT NULL, x INTEGER NOT NULL, y INTEGER NOT NULL, terrain_id TEXT NOT NULL REFERENCES terrain(id), collision INTEGER CHECK(collision IN (0,1)), PRIMARY KEY(region_id,map_id,y,x), FOREIGN KEY(region_id,map_id) REFERENCES maps(region_id,id)) WITHOUT ROWID",
            "CREATE TABLE entities (id TEXT PRIMARY KEY, type TEXT NOT NULL, name TEXT NOT NULL, tags_json TEXT NOT NULL, properties_json TEXT NOT NULL)",
            "CREATE TABLE entity_positions (entity_id TEXT PRIMARY KEY REFERENCES entities(id), region_id TEXT NOT NULL, map_id TEXT NOT NULL, x INTEGER NOT NULL, y INTEGER NOT NULL, FOREIGN KEY(region_id,map_id) REFERENCES maps(region_id,id))",
            "CREATE TABLE objects (region_id TEXT NOT NULL, map_id TEXT NOT NULL, id TEXT NOT NULL, entity_id TEXT NOT NULL REFERENCES entities(id), x INTEGER NOT NULL, y INTEGER NOT NULL, PRIMARY KEY(region_id,map_id,id), FOREIGN KEY(region_id,map_id) REFERENCES maps(region_id,id))",
            "CREATE INDEX objects_at ON objects(region_id,map_id,y,x)",
            "CREATE INDEX entities_at ON entity_positions(region_id,map_id,y,x)",
            "CREATE TABLE lore (path TEXT PRIMARY KEY, markdown TEXT NOT NULL)",
          ]
          statements.each { |sql| connection.exec(sql) }
          a.regions.keys.sort.each { |id| connection.exec("INSERT INTO regions VALUES (?,?)", id, a.regions[id].name) }
          world = a.world.not_nil!
          connection.exec("INSERT INTO world VALUES (?,?,?,?,?)", world.id, world.name, world.version, world.description, world.default_region)
          a.catalog.not_nil!.terrain.to_a.sort_by(&.[0]).each do |id, tile|
            connection.exec("INSERT INTO terrain VALUES (?,?,?,?,?,?)", id, tile.glyph, tile.foreground, tile.background, tile.passable ? 1 : 0, tile.movement_cost)
          end
          a.entities.keys.sort.each do |id|
            entity = a.entities[id]
            properties = Source.canonical_value(YAML::Any.new(entity.properties.to_h { |k, v| {YAML::Any.new(k), v} })).to_json
            connection.exec("INSERT INTO entities VALUES (?,?,?,?,?)", id, entity.type, entity.name, entity.tags.to_json, properties)
          end
          a.maps.keys.sort.each do |key|
            map = a.maps[key]
            region = key.split('/').first
            connection.exec("INSERT INTO maps VALUES (?,?,?,?,?,?)", region, map.id, map.name, map.width, map.height, map.default_terrain)
            {"terrain", "collision", "objects"}.each { |kind| connection.exec("INSERT INTO layers VALUES (?,?,?,?,?)", region, map.id, kind, map.width, map.height) }
            map.height.times do |y|
              map.width.times do |x|
                collision = case map.symbol_at("collision", x, y)
                            when "#" then 1
                            when "+" then 0
                            else          nil
                            end
                connection.exec("INSERT INTO cells VALUES (?,?,?,?,?,?)", region, map.id, x, y, map.terrain_at(x, y), collision)
              end
            end
            map.layers.objects.sort_by(&.id).each do |object|
              connection.exec("INSERT INTO objects VALUES (?,?,?,?,?,?)", region, map.id, object.id, object.entity, object.x, object.y)
            end
          end
          a.entities.keys.sort.each do |id|
            if pos = a.entities[id].position
              key = a.resolve_map(pos.map).not_nil!.split('/')
              connection.exec("INSERT INTO entity_positions VALUES (?,?,?,?,?)", id, key[0], key[1], pos.x, pos.y)
            end
          end
          a.sources.keys.sort.select { |p| Source.kind(p) == "lore" }.each do |p|
            connection.exec("INSERT INTO lore VALUES (?,?)", p, a.sources[p])
          end
        end
        raise DocumentError.new("SQLite integrity check failed") unless db.scalar("PRAGMA integrity_check") == "ok"
        db.query("PRAGMA foreign_key_check") do |rows|
          rows.each { raise DocumentError.new("SQLite foreign-key check failed") }
        end
      end
    end
  end
end
