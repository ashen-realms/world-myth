require "option_parser"

module WorldMyth::CLI
  HELP = <<-TEXT
  World Myth — offline world authoring tools

  Usage:
    world-myth new <name-or-directory>
    world-myth validate [path]
    world-myth build [path]
    world-myth fmt [path] [--check] [--allow-comment-loss]
    world-myth --help | --version

  Paths default to the current directory. Exit codes: 0 success, 1 failure,
  2 usage error. fmt skips commented YAML unless explicitly authorized.
  TEXT

  def self.run(args = ARGV, output : IO = STDOUT, err : IO = STDERR) : Int32
    command = args.first?
    if command.nil? || {"--help", "-h", "help"}.includes?(command)
      output.puts HELP
      return 0
    end
    if command == "--version"
      output.puts WorldMyth::VERSION
      return 0
    end
    unless {"new", "validate", "build", "fmt"}.includes?(command)
      err.puts "Unknown command: #{command}\n#{HELP}"
      return 2
    end
    rest = args.skip(1).dup
    check = false
    allow = false
    help = false
    OptionParser.parse(rest) do |parser|
      parser.on("--check", "Check formatting without writing") { check = true }
      parser.on("--allow-comment-loss", "Explicitly allow YAML normalization") { allow = true }
      parser.on("--help", "Show help") { help = true }
    end
    if help
      output.puts HELP
      return 0
    end
    if rest.size > 1 || (command == "new" && rest.empty?) || (command != "fmt" && (check || allow))
      err.puts HELP
      return 2
    end
    path = File.expand_path(rest.first? || ".")
    case command
    when "new"
      Core::Project.create(path, File.basename(path))
      output.puts "Created #{path}"
    when "validate"
      analysis = Core::Project.new(path).analyze
      analysis.diagnostics.each { |d| output.puts d }
      output.puts(analysis.valid? ? "World is valid." : "Validation failed.")
      return analysis.valid? ? 0 : 1
    when "build"
      result = Core::Compiler.new(path).build
      output.puts "Built #{result}/world.sqlite and manifest.json"
    when "fmt"
      project = Core::Project.new(path)
      changed = false
      failed = false
      project.documents.each_value do |doc|
        next if Core::Source.kind(doc.path) == "lore"
        begin
          raise Core::DocumentError.new(doc.error) if doc.error
          if doc.sensitive? && !allow
            output.puts "Skipped #{doc.path}: normalization requires --allow-comment-loss"
            next
          end
          canonical = Core::Source.canonical(doc.text)
          next if canonical == doc.text
          changed = true
          output.puts "#{check ? "Would format" : "Formatted"} #{doc.path}"
          unless check
            doc.replace(canonical, "Format")
            doc.save(project.root)
          end
        rescue ex
          err.puts "#{doc.path}: #{ex.message}"
          failed = true
        end
      end
      return failed || (check && changed) ? 1 : 0
    end
    0
  rescue ex : OptionParser::Exception
    err.puts ex.message
    2
  rescue ex
    err.puts ex.message
    1
  end
end
