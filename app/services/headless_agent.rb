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

  # 40 was not enough for real planning or implementation work: every
  # ticket in the first live run died at turn 41, mid-task, having spent
  # its money for nothing.
  DEFAULT_MAX_TURNS = "120".freeze
  DEFAULT_TIMEOUT = "2700".freeze

  class << self
    # the model these runs actually use, recorded against each charge
    def model_name
      ENV["CLAUDE_MODEL"].presence || Setting.instance.orchestrator_model
    end

    def call(prompt:, chdir:, env: {}, timeout: nil, max_turns: nil, model: nil, extra_args: [], &on_message)
      bin = ClaudeCodeRunner.bin_path
      return Result.new(ok: false, error: "claude CLI not found", log: "") unless bin

      flags = (ENV["CLAUDE_FLAGS"].presence || ClaudeCodeRunner::DEFAULT_FLAGS).shellsplit
      model = model.presence || model_name
      command = [bin, "-p", prompt, "--output-format", "stream-json", "--verbose",
                 "--model", model,
                 "--max-turns", (max_turns || ENV.fetch("CLAUDE_MAX_TURNS", DEFAULT_MAX_TURNS)).to_s,
                 *extra_args, *flags]
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) +
                 Float(timeout || ENV.fetch("CLAUDE_TIMEOUT", DEFAULT_TIMEOUT))

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

      # A failed run has still spent whatever it spent — carry cost and the
      # raw result through so it is charged and reported, never silently free.
      if timed_out
        Result.new(ok: false, error: timeout_reason(timeout), log: log, raw: final,
                   cost: final&.dig("total_cost_usd").to_f, duration_ms: final&.dig("duration_ms").to_i,
                   exit_status: status&.exitstatus, session_id: session_id)
      elsif status&.success? && final && !final["is_error"]
        Result.new(ok: true, result_text: final["result"].to_s, cost: final["total_cost_usd"].to_f,
                   duration_ms: final["duration_ms"].to_i, log: log,
                   exit_status: status.exitstatus, session_id: session_id, raw: final)
      else
        Result.new(ok: false, error: failure_reason(final, status, log, max_turns),
                   cost: final&.dig("total_cost_usd").to_f, duration_ms: final&.dig("duration_ms").to_i,
                   log: log, exit_status: status&.exitstatus, session_id: session_id, raw: final)
      end
    rescue StandardError => e
      Result.new(ok: false, error: "#{e.class}: #{e.message}", log: log || "")
    end

    private

    def timeout_reason(timeout)
      limit = (timeout || ENV.fetch("CLAUDE_TIMEOUT", DEFAULT_TIMEOUT)).to_i
      "hit the #{limit}s time limit while still working — raise CLAUDE_TIMEOUT, or split the ticket into smaller ones"
    end

    # The CLI reports a failure by setting is_error on its result message; the
    # useful part is why, which the old code replaced with the agent's last
    # line of narration.
    def failure_reason(final, status, log, max_turns)
      limit = (max_turns || ENV.fetch("CLAUDE_MAX_TURNS", DEFAULT_MAX_TURNS)).to_i
      turns = final&.dig("num_turns").to_i
      # the CLI names this failure itself — trust that over counting turns,
      # which says nothing once the limit is raised
      out_of_turns = final&.dig("subtype").to_s.include?("max_turns") ||
                     (turns.positive? && turns >= limit)

      if out_of_turns
        blocked = log.to_s.scan('"subtype":"permission_denied"').size
        hint = if blocked.positive?
                 " — #{blocked} command#{"s" if blocked > 1} needed permission it does not have, " \
                 "which burned turns; check CLAUDE_FLAGS"
               else
                 " — raise CLAUDE_MAX_TURNS, or split the ticket into smaller ones"
               end
        "ran out of turns after #{turns} of #{limit}, still mid-work#{hint}"
      elsif status&.exitstatus == 143
        "the run was terminated (SIGTERM) before it finished"
      elsif (text = final&.dig("result").presence)
        text.to_s.truncate(200)
      else
        "the agent exited with status #{status&.exitstatus.inspect} without a result"
      end
    end

    def parse_line(line)
      JSON.parse(line)
    rescue JSON::ParserError
      nil
    end
  end
end
