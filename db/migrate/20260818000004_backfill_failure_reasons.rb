require "json"

# Failed runs carried the agent's last line of narration as their "reason",
# which is why the board showed things like "Now the design.md corrections:"
# as an explanation. Rewrite the ones we can diagnose from their own stream.
class BackfillFailureReasons < ActiveRecord::Migration[8.1]
  def up
    PhaseRun.where(status: "failed").find_each do |run|
      line = run.log.to_s.each_line.find { |l| l.include?('"type":"result"') }
      final = begin
        line && JSON.parse(line)
      rescue JSON::ParserError
        nil
      end

      reason =
        if final&.dig("subtype").to_s.include?("max_turns")
          blocked = run.log.to_s.scan('"subtype":"permission_denied"').size
          hint = if blocked.positive?
                   " — #{blocked} command#{'s' if blocked > 1} needed permission it did not have, which burned turns"
                 else
                   " — raise CLAUDE_MAX_TURNS, or split the ticket into smaller ones"
                 end
          "ran out of turns after #{final['num_turns']}, still mid-work#{hint}"
        elsif run.exit_status == 143
          "the run was terminated (SIGTERM) before it finished — most likely the time limit"
        end

      run.update_columns(note: reason.truncate(200)) if reason
    end
  end

  def down
    # the original notes were the agent's narration and are no loss
  end
end
