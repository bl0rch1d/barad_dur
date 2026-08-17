require "json"

# Failed runs used to record $0 no matter what they had spent — the cost was
# only read on the success path. The money is still in each run's captured
# stream, so recover it rather than leaving the ledger understating reality.
# Idempotent: only touches runs still sitting at zero.
class BackfillFailedRunCosts < ActiveRecord::Migration[8.1]
  def up
    return unless table_exists?(:spend_entries)

    recovered = 0
    total = 0.0

    PhaseRun.where(status: "failed", cost: 0).find_each do |run|
      line = run.log.to_s.each_line.find { |l| l.include?('"type":"result"') }
      next unless line

      final = begin
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end
      cost = final&.dig("total_cost_usd").to_f.round(4)
      next unless cost.positive?

      run.update_columns(cost: cost)
      SpendEntry.create!(amount: cost, source: "phase", phase: run.phase,
                         ticket_code: run.ticket&.code, agent_id: run.ticket&.agent_id,
                         occurred_at: run.started_at || run.created_at,
                         created_at: Time.current, updated_at: Time.current)
      run.ticket&.increment!(:cost, cost)
      recovered += 1
      total += cost
    end

    say "recovered #{recovered} unbilled failed runs worth $#{format('%.2f', total)}" if recovered.positive?
  end

  def down
    # the entries are indistinguishable from ordinary charges by design
  end
end
