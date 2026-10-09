module WorldMyth::Core
  module Migration
    def self.sources(input : Hash(String, String), allow_comment_loss = false) : Hash(String, String)
      analysis = Analysis.new(input)
      raise DocumentError.new(analysis.diagnostics.join('\n')) unless analysis.valid?
      input.to_h do |path, text|
        if definition = Source.parse(path, text)
          if Source.sensitive?(text) && !allow_comment_loss
            raise NormalizationRequired.new("#{path}: migration normalizes YAML; use --allow-comment-loss after reviewing your source")
          end
          definition.schema_version = 2
          if definition.is_a?(Map)
            definition.layers.elevation = Array.new(definition.height, Array.new(definition.width, 0).join(' ')) if definition.layers.elevation.empty?
            definition.layers.shapes = Array.new(definition.height, "." * definition.width) if definition.layers.shapes.empty?
          end
          {path, definition.to_yaml}
        else
          {path, text}
        end
      end
    end

    def self.copy(input : Hash(String, String), destination : String, allow_comment_loss = false) : Project
      raise DocumentError.new("Destination already exists") if File.exists?(destination)
      converted = sources(input, allow_comment_loss)
      analysis = Analysis.new(converted)
      raise DocumentError.new(analysis.diagnostics.join('\n')) unless analysis.valid?
      staging = File.join(File.dirname(File.expand_path(destination)), ".worldmyth-migrate-#{Random::Secure.hex(8)}")
      Dir.mkdir(staging, 0o700)
      begin
        converted.each do |path, text|
          # Public entry also accepts snapshots, never trust their paths.
          raise DocumentError.new("Unsafe source path") if Path[path].absolute? || path.split('/').includes?("..")
          full = File.join(staging, path)
          FileUtils.mkdir_p(File.dirname(full))
          File.write(full, text)
        end
        FileUtils.mkdir_p(File.join(staging, ".worldmyth"))
        File.write(File.join(staging, ".worldmyth/project.yaml"), "schema_version: 2\n")
        File.write(File.join(staging, ".gitignore"), "dist/\n.dist-*/\n.worldmyth/*.local.yaml\n.worldmyth/build.lock\n")
        File.rename(staging, destination)
      ensure
        FileUtils.rm_r(staging) if Dir.exists?(staging)
      end
      Project.new(destination)
    end
  end
end
