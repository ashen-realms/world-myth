module WorldMyth::GUI
  class Preferences
    include YAML::Serializable
    property width = 1280
    property height = 800
    property left_panel = 240
    property center_panel = 760
    property cell_width = 20.0
    property cell_height = 26.0
    property font = "Monospace"
    property grid = true
    property terrain = true
    property collision = true
    property objects = true
    property recent = [] of String

    def initialize
    end

    def self.path : String
      File.join(ENV["XDG_CONFIG_HOME"]? || File.join(Path.home.to_s, ".config"), "world-myth", "preferences.yaml")
    end

    def self.load : Preferences
      File.file?(path) ? from_yaml(File.read(path)) : new
    rescue
      new
    end

    def save
      FileUtils.mkdir_p(File.dirname(self.class.path))
      Core::Persistence.write(self.class.path, to_yaml)
    end
  end
end
