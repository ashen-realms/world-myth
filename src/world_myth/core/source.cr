module WorldMyth::Core
  # Parse the syntax tree first: duplicate mappings must not silently collapse.
  module Source
    extend self

    def tree(text : String) : YAML::Nodes::Node
      documents = YAML::Nodes.parse_all(text)
      raise DocumentError.new("Expected exactly one YAML document") unless documents.size == 1
      documents.first
    end

    def inspect_tree(node : YAML::Nodes::Node, &block : YAML::Nodes::Node ->)
      yield node
      case node
      when YAML::Nodes::Document, YAML::Nodes::Sequence, YAML::Nodes::Mapping
        node.nodes.each { |child| inspect_tree(child, &block) }
      end
    end

    def check_syntax(text : String)
      inspect_tree(tree(text)) do |node|
        if node.is_a?(YAML::Nodes::Mapping)
          keys = Set(String).new
          node.each do |key, _|
            raise DocumentError.new("Mapping keys must be strings") unless key.is_a?(YAML::Nodes::Scalar)
            raise DocumentError.new("Duplicate YAML key '#{key.value}' at line #{key.start_line}") unless keys.add?(key.value)
          end
        end
      end
    end

    # Node spans distinguish comments from # inside quoted/plain/block scalars.
    def sensitive?(text : String) : Bool
      spans = Hash(Int32, Array(Range(Int32, Int32))).new { |h, k| h[k] = [] of Range(Int32, Int32) }
      sensitive = false
      inspect_tree(tree(text)) do |node|
        sensitive ||= !!node.anchor || !!node.tag || node.is_a?(YAML::Nodes::Alias)
        if node.is_a?(YAML::Nodes::Scalar)
          (node.start_line..node.end_line).each do |line|
            start = line == node.start_line ? node.start_column : 0
            finish = line == node.end_line ? node.end_column : Int32::MAX
            spans[line] << (start...finish)
          end
        end
      end
      return true if sensitive
      text.lines.each_with_index do |line, y|
        line.each_char_with_index do |char, x|
          return true if char == '#' && !spans[y + 1].any?(&.includes?(x + 1))
        end
      end
      false
    end

    def kind(path : String) : String
      case path
      when "world.yaml"                               then "world"
      when "terrain.yaml"                             then "terrain"
      when /\Aregions\/[^\/]+\/region\.yaml\z/        then "region"
      when /\Aregions\/[^\/]+\/maps\/[^\/]+\.ya?ml\z/ then "map"
      when /\Aentities\/.+\.ya?ml\z/                  then "entity"
      when /\Alore\/.+\.md\z/                         then "lore"
      else                                                 "source"
      end
    end

    def parse(path : String, text : String) : Definition?
      return nil if kind(path) == "lore"
      check_syntax(text)
      case kind(path)
      when "world"   then World.from_yaml(text)
      when "terrain" then Catalog.from_yaml(text)
      when "region"  then Region.from_yaml(text)
      when "map"     then Map.from_yaml(text)
      when "entity"  then Entity.from_yaml(text)
      else                nil
      end
    end

    def canonical(text : String) : String
      check_syntax(text)
      canonical_value(YAML.parse(text)).to_yaml
    end

    def canonical_value(value : YAML::Any) : YAML::Any
      case raw = value.raw
      when Hash
        YAML::Any.new(raw.to_a.sort_by { |k, _| k.as_s }.to_h.transform_values { |v| canonical_value(v) })
      when Array
        YAML::Any.new(raw.map { |v| canonical_value(v) })
      else value
      end
    end
  end

  record Revision, before : String, after : String, label : String

  class Document
    getter path : String
    getter text : String
    getter revision : Int64 = 0_i64
    getter model : Definition?
    getter error : String?
    getter history = [] of Revision
    getter future = [] of Revision
    @baseline : String
    @fingerprint : String?

    def initialize(@path, @text, @fingerprint = nil)
      @baseline = @text
      reparse
    end

    def dirty? : Bool
      text != @baseline
    end

    def sensitive? : Bool
      Source.kind(path) != "lore" && Source.sensitive?(text)
    end

    def replace(text : String, label = "Edit source", expected_revision : Int64? = nil)
      raise ConflictError.new("Document changed since this edit began") if expected_revision && expected_revision != revision
      return if text == @text
      @history << Revision.new(@text, text, label)
      @history.shift if @history.size > 100
      @future.clear
      assign(text)
    end

    def normalize
      raise DocumentError.new(error) if error
      replace(Source.canonical(text), "Normalize YAML (comments removed)")
    end

    def edit(label : String, &block : Definition ->)
      raise DocumentError.new(error || "This document has no visual editor") unless value = model
      raise NormalizationRequired.new("Review and accept YAML normalization before visual editing") if sensitive?
      # Mutate a detached projection: failed operations never leak into the session.
      copy = Source.parse(path, text).not_nil!
      yield copy
      replace(copy.to_yaml, label)
    end

    def undo
      return unless change = history.pop?
      future << change
      assign(change.before)
    end

    def redo
      return unless change = future.pop?
      history << change
      assign(change.after)
    end

    def save(root : String)
      full = File.join(root, path)
      actual = File.file?(full) ? Digest::SHA256.hexdigest(File.read(full)) : nil
      raise ConflictError.new("#{path} changed on disk. Reload or save a copy.") unless actual == @fingerprint
      Persistence.write(full, text) do
        raise ConflictError.new("#{path} changed while saving. Reload or save a copy.") if external_change?(root)
      end
      @fingerprint = Digest::SHA256.hexdigest(text)
      @baseline = text
    end

    def external_change?(root : String) : Bool
      full = File.join(root, path)
      actual = File.file?(full) ? Digest::SHA256.hexdigest(File.read(full)) : nil
      actual != @fingerprint
    end

    def reload(root : String)
      content = File.read(File.join(root, path))
      @fingerprint = Digest::SHA256.hexdigest(content)
      @baseline = content
      @history.clear
      @future.clear
      assign(content)
    end

    private def assign(text : String)
      @text = text
      @revision += 1
      reparse
    end

    private def reparse
      @model = Source.parse(path, text)
      @error = nil
    rescue ex
      @model = nil
      @error = ex.message || ex.class.name
    end
  end

  module Persistence
    extend self

    def write(path : String, text : String)
      write(path, text) { }
    end

    def write(path : String, text : String, &before_replace : ->)
      directory = File.dirname(path)
      File.tempfile(".worldmyth-", ".tmp", dir: directory) do |file|
        file.print(text)
        file.flush
        file.fsync
        File.chmod(file.path, File.info(path).permissions) if File.exists?(path)
        before_replace.call
        File.rename(file.path, path)
      end
    end
  end
end
