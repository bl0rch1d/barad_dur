# Shared behavior for the live RFC jobs: narration into the event feed,
# throttled progress notes, cost accrual and failure handling.
class RfcAgentJob < ApplicationJob
  queue_as :default

  private

  def narrate(rfc, data, tag, agent_name)
    return unless data["type"] == "assistant"

    Array(data.dig("message", "content")).each do |part|
      case part["type"]
      when "text"
        snippet = part["text"].to_s.strip.gsub(/\s+/, " ").truncate(140)
        next if snippet.blank?

        note_progress(rfc, snippet)
        Event.record!(phase_tag: tag, agent_name: agent_name, ticket_code: "RFC", meta: "claude", text: snippet)
      when "tool_use"
        brief = part.dig("input", "file_path") || part.dig("input", "pattern") || part.dig("input", "command")
        Event.record!(phase_tag: tag, agent_name: agent_name, ticket_code: "RFC", meta: "tool",
                      text: "→ #{part['name']} #{brief}".truncate(140))
      end
    end
  end

  def note_progress(rfc, snippet)
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    return if @last_note && now - @last_note < 0.5

    @last_note = now
    rfc.update!(progress_note: snippet.truncate(100))
    PipelineEngine.broadcast
  end

  def accrue(result, agent_name)
    cost = result.cost.to_f.round(4)
    return unless cost.positive?

    setting = Setting.instance
    setting.update!(spend_today: (setting.spend_today + cost).round(2))
    SpendSample.accrue!(cost)
    Agent.find_by(name: agent_name)&.increment!(:cost_today, cost.round(2))
  end

  def run_meta(result)
    "#{(result.duration_ms.to_i / 1000.0).round}s · $#{format('%.2f', result.cost.to_f)}"
  end

  def fail_rfc(rfc, tag, agent_name, error)
    rfc.update!(job_state: "failed", error: error.to_s.truncate(140), progress_note: nil)
    Event.record!(phase_tag: tag, tone: "var(--err)", agent_name: agent_name, ticket_code: "RFC",
                  text: "RFC #{tag == 'INVEST' ? 'investigation' : 'planning'} failed: #{error.to_s.truncate(120)}")
    PipelineEngine.broadcast
  end
end
