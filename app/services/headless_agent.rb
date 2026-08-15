require "open3"
require "json"
require "shellwords"

# One-shot headless Claude Code execution with stream-json parsing.
# The lowest-level seam shared by ticket phase runs (ClaudeCodeRunner) and
# the RFC investigation/planning jobs. Yields each parsed stream message to
# the optional block; returns a Result.
class HeadlessAgent
  Result = Struct.new(:ok, :error, :result_text, :cost, :duration_ms,
                      :log, :exit_status, :session_id, :raw, keyword_init: true)

  class << self
    def call(prompt:, chdir:, env: {}, timeout: nil, max_turns: nil, &on_message)
      bin = ClaudeCodeRunner.bin_path
      return Result.new(ok: false, error: "claude CLI not found", log: "") unless bin

      flags = (ENV["CLAUDE_FLAGS"].presence || ClaudeCodeRunner::DEFAULT_FLAGS).shellsplit
      command = [bin, "-p", prompt, "--output-format", "stream-json", "--verbose",
                 "--max-turns", (max_turns || ENV.fetch("CLAUDE_MAX_TURNS", "40")).to_s, *flags]
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) +
                 Float(timeout || ENV.fetch("CLAUDE_TIMEOUT", 900))

      log = +""
      final = nil
      session_id = nil
      timed_out = false
      status = nil

      Open3.popen3(env, *command, chdir: chdir) do |stdin, stdout, stderr, wait|
        stdin.close
        err_reader = Thread.new { stderr.read }
        buffer = +""

        loop do
          if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
            timed_out = true
            begin
              Process.kill("TERM", wait.pid)
            rescue Errno::ESRCH
            end
            break
          end

          ready = IO.select([stdout], nil, nil, 5)
          next unless ready

          chunk = stdout.read_nonblock(65_536, exception: false)
          break if chunk.nil?
          next if chunk == :wait_readable

          buffer << chunk
          while (newline = buffer.index("\n"))
            line = buffer.slice!(0..newline)
            log << line
            data = parse_line(line)
            next unless data

            session_id = data["session_id"] if data["type"] == "system" && data["session_id"]
            final = data if data["type"] == "result"
            on_message&.call(data)
          end
        end

        log << err_reader.value.to_s
        status = wait.value
      end

      if timed_out
        Result.new(ok: false, error: "timed out", log: log,
                   exit_status: status&.exitstatus, session_id: session_id)
      elsif status&.success? && final && !final["is_error"]
        Result.new(ok: true, result_text: final["result"].to_s, cost: final["total_cost_usd"].to_f,
                   duration_ms: final["duration_ms"].to_i, log: log,
                   exit_status: status.exitstatus, session_id: session_id, raw: final)
      else
        Result.new(ok: false, error: final&.dig("result").presence || "exit #{status&.exitstatus}",
                   log: log, exit_status: status&.exitstatus, session_id: session_id, raw: final)
      end
    rescue StandardError => e
      Result.new(ok: false, error: "#{e.class}: #{e.message}", log: log || "")
    end

    private

    def parse_line(line)
      JSON.parse(line)
    rescue JSON::ParserError
      nil
    end
  end
end
