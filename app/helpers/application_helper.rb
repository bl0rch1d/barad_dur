module ApplicationHelper
  STATE_META = {
    "draft"              => { name: "Draft",              tone: "var(--tx3)" },
    "ready"              => { name: "Ready",              tone: "var(--tx2)" },
    "investigation"      => { name: "Investigation",      tone: "var(--info)" },
    "planning"           => { name: "Planning",           tone: "var(--info)" },
    "ready_to_implement" => { name: "Ready to implement", tone: "var(--ok)" },
    "implementation"     => { name: "Implementation",     tone: "var(--accent)" },
    "review"             => { name: "Review",             tone: "var(--warn)" },
    "testing"            => { name: "Testing",            tone: "var(--warn)" },
    "deployment"         => { name: "Deployment",         tone: "var(--ok)" },
    "done"               => { name: "Done",               tone: "var(--ok)" }
  }.freeze

  def state_meta(state)
    STATE_META.fetch(state.to_s, STATE_META["draft"])
  end

  def short_duration(secs)
    secs = secs.to_i
    return "#{secs}s" if secs < 60

    mins = secs / 60
    return "#{mins}m" if mins < 60

    format("%dh %02dm", mins / 60, mins % 60)
  end

  # compact duration for the reckoning panel: 45s · 12m · 3.5h · 2.1d
  def duration_label(seconds)
    s = seconds.to_i
    return "#{s}s" if s < 60
    return "#{(s / 60.0).round}m" if s < 3600
    return "#{(s / 3600.0).round(1)}h" if s < 86_400

    "#{(s / 86_400.0).round(1)}d"
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

  # Six per-phase progress pips for a board card, from real phase runs.
  # [[colour, state], ...] — the current phase is marked so the board can
  # show it working rather than merely tinting it a brighter colour.
  def ticket_pips(ticket)
    done = ticket.phase_runs.select { |r| r.status == "done" }.map(&:phase)
    running = ticket.current_phase_run&.status == "running"
    failed = ticket.current_phase_run&.status == "failed"

    Ticket::PHASES.map do |phase|
      if done.include?(phase) then ["var(--ok)", nil]
      elsif phase == ticket.state
        next ["var(--err)", "failed"] if failed

        ["var(--accent)", running ? "running" : "current"]
      elsif ticket.state == "ready_to_implement" && %w[investigation planning].include?(phase)
        ["var(--ok)", nil]
      else ["var(--soft)", nil]
      end
    end
  end

  def card_button(ticket)
    case ticket.state
    when "draft"              then { label: "draft", tone: "var(--line)", fg: "var(--tx3)" }
    when "ready"              then { label: "queued", tone: "var(--line)", fg: "var(--tx2)" }
    when "ready_to_implement" then { label: "ready", tone: "var(--ok)", fg: "var(--ok)" }
    when "deployment"         then { label: "ship", tone: "var(--accent)", fg: "var(--accent)" }
    else                           { label: "open", tone: "var(--accent)", fg: "var(--accent)" }
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

  # Per-page flavor for the unbound-realm empty state (setup not finished).
  UNBOUND_FLAVOR = {
    "dashboard" => { quote: "“The palantír shows nothing… because you have not plugged it in.”",
                     sub: "Bind a workspace and the Cold Watch will have something to watch." },
    "board"     => { quote: "“One does not simply manage tickets that do not exist.”",
                     sub: "Even Sauron cannot micromanage an empty land. The board fills once a realm is bound." },
    "rfcs"      => { quote: "“Speak, friend, and enter — but first, tell the tower where your code lives.”",
                     sub: "Feature requests are investigated against a real workspace. There is none yet." },
    "specs"     => { quote: "“The archives are empty. Denethor would like a word.”",
                     sub: "Bind a workspace with openspec/ folders and the scrolls shall be indexed." },
    "agents"    => { quote: "“The Legion musters when there is a banner to march under.”",
                     sub: "Finish the setup and your harness agents take their posts." },
    "activity"  => { quote: "“You cannot pass… a message. The palantír is dark.”",
                     sub: "Chat threads open once the realm is bound and the runner is lit." }
  }.freeze

  def unbound_flavor
    UNBOUND_FLAVOR.fetch(controller_name,
                         { quote: "“Not all those who wander are lost — but this page is.”",
                           sub: "Run the setup wizard to bind a workspace." })
  end

  def screen?(name)
    controller_name == name || (name == "dashboard" && controller_name == "dashboard")
  end
end
