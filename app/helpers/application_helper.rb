module ApplicationHelper
  STATE_META = {
    "backlog"        => { name: "Not ready",      tone: "var(--tx3)" },
    "ready"          => { name: "Ready",          tone: "var(--tx2)" },
    "investigation"  => { name: "Investigation",  tone: "var(--info)" },
    "planning"       => { name: "Planning",       tone: "var(--info)" },
    "implementation" => { name: "Implementation", tone: "var(--accent)" },
    "review"         => { name: "Review",         tone: "var(--warn)" },
    "testing"        => { name: "Testing",        tone: "var(--warn)" },
    "deployment"     => { name: "Deployment",     tone: "var(--ok)" },
    "done"           => { name: "Done",           tone: "var(--ok)" }
  }.freeze

  def state_meta(state)
    STATE_META.fetch(state.to_s, STATE_META["backlog"])
  end

  def short_duration(secs)
    secs = secs.to_i
    return "#{secs}s" if secs < 60

    mins = secs / 60
    return "#{mins}m" if mins < 60

    format("%dh %02dm", mins / 60, mins % 60)
  end

  def ago_label(time)
    secs = Time.current - time
    if secs < 3600 then "#{[ (secs / 60).round, 1 ].max}m"
    elsif secs < 86_400 then "#{(secs / 3600).round}h"
    else "#{(secs / 86_400).round}d"
    end
  end

  def event_time(event)
    event.happened_at.strftime("%H:%M:%S")
  end

  # Six per-phase progress pips for a board card, as CSS color values.
  def ticket_pips(ticket)
    cur = ticket.phase_index
    Ticket::PHASES.each_index.map do |k|
      if cur.nil? then "var(--soft)"
      elsif k < cur then "var(--ok)"
      elsif k == cur then "var(--accent)"
      else "var(--soft)"
      end
    end
  end

  def card_button(ticket)
    if %w[backlog ready].include?(ticket.state)
      { label: "start", tone: "var(--line)", fg: "var(--tx2)" }
    elsif ticket.state == "deployment"
      { label: "ship", tone: "var(--accent)", fg: "var(--accent)" }
    else
      { label: "open", tone: "var(--accent)", fg: "var(--accent)" }
    end
  end

  def spend_bar_style(sample, max)
    pct = max.positive? ? ((sample.amount / max) * 100).clamp(6, 100).round : 6
    tone = pct > 65 ? "var(--warn)" : "var(--accent)"
    "height:#{pct}%;background:#{tone}"
  end

  def wizard_setup(key, default)
    @setting.setup.fetch(key.to_s, default).to_s
  end

  def screen?(name)
    controller_name == name || (name == "dashboard" && controller_name == "dashboard")
  end
end
