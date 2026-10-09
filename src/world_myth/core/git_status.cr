module WorldMyth::Core
  record GitStatus, branch : String, modified : Array(String) do
    def self.read(root : String) : GitStatus
      output = IO::Memory.new
      result = Process.run("git", ["-C", root, "--no-optional-locks", "status", "--porcelain=v1", "-z", "--branch", "--untracked-files=normal", "--", "."], output: output, error: Process::Redirect::Close)
      return new("No Git repository", [] of String) unless result.success?
      entries = output.to_s.split('\0').reject(&.empty?)
      branch = entries.shift?.try(&.sub(/^## /, "").split("...").first) || "Detached HEAD"
      files = [] of String
      skip = false
      entries.each do |entry|
        if skip
          skip = false
          next
        end
        files << entry[3..] if entry.size >= 3
        skip = entry[0, 2].includes?('R') || entry[0, 2].includes?('C')
      end
      new(branch, files)
    rescue File::NotFoundError
      new("Git unavailable", [] of String)
    end
  end
end
