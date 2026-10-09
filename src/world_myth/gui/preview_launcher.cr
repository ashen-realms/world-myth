require "../core"

module WorldMyth::GUI
  module PreviewLauncher
    # Kitty keeps this process alive until its window closes, so a snapshot can
    # be removed reliably without racing terminal startup or shell quoting.
    def self.launch(sources : Hash(String, String), reference : String, &on_error : String -> Nil)
      terminal = Process.find_executable("kitty") || raise Core::DocumentError.new("Terminal Preview requires Kitty. Install it (sudo dnf install kitty), or run world-myth preview in your terminal.")
      sibling = File.join(File.dirname(Process.executable_path.not_nil!), "world-myth")
      cli = File::Info.executable?(sibling) ? sibling : Process.find_executable("world-myth")
      raise Core::DocumentError.new("Cannot find world-myth CLI. Build both applications with shards build.") unless cli
      snapshot = File.tempfile("world-myth-preview-", ".json")
      begin
        snapshot.chmod(0o600)
        sources.to_json(snapshot)
        snapshot.close
        errors = IO::Memory.new
        process = Process.new(terminal, ["--title", "World Myth — Preview", cli, "preview", "--map", reference, "--snapshot", snapshot.path], error: errors)
      rescue ex
        snapshot.close unless snapshot.closed?
        File.delete?(snapshot.path)
        raise ex
      end
      # Also remove snapshots if the editor closes before the preview window.
      at_exit { File.delete?(snapshot.path) }
      spawn do
        begin
          status = process.wait
          unless status.success?
            on_error.call("Terminal Preview exited with #{status.exit_code}.\n#{errors.to_s.byte_slice(0, 2000)}")
          end
        ensure
          File.delete?(snapshot.path)
        end
      end
    end
  end
end
