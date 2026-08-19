require "json"
require "fileutils"

# Where a phase writes its structured result.
#
# A contract that lives only in the agent's final message is lost whenever the
# run never reaches one — max turns, a timeout, a crash. Those are exactly the
# runs that did the most work. The same JSON is therefore written to a file the
# moment the agent knows it, and read from there first; the final message is
# the fallback for the ordinary case where both exist.
module PhaseOutput
  module_function

  def dir
    path = Pathname.new(ENV.fetch("PHASE_OUT_DIR", Rails.root.join("tmp/phase_out").to_s))
    FileUtils.mkdir_p(path)
    path
  end

  def path_for(run)
    dir.join("run-#{run.id}.json").to_s
  end

  def instruction(run)
    <<~TXT

      Write that same JSON to the file below as soon as you know it, and do it
      before you finish rather than after. If this run is cut short, that file
      is the only part of your answer that survives:
      #{path_for(run)}
    TXT
  end

  # The file first, the final message second: a truncated run has one and not
  # the other, and a complete run has the same content in both.
  def read(run, result_text = nil)
    from_file(run) || StructuredOutput.json_block(result_text, expect: run.phase)
  end

  def from_file(run)
    data = JSON.parse(File.read(path_for(run)))
    data.is_a?(Hash) ? data : nil
  rescue Errno::ENOENT, JSON::ParserError, SystemCallError
    nil
  end

  def clear(run)
    File.delete(path_for(run))
  rescue Errno::ENOENT, SystemCallError
    nil
  end
end
