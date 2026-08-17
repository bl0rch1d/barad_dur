# The runner column still defaulted to "demo" — a leftover from when a
# simulated driver existed alongside the real one. Every run is a real agent
# run now, so the default follows.
class DefaultPhaseRunRunnerToClaude < ActiveRecord::Migration[8.1]
  def up
    change_column_default :phase_runs, :runner, from: "demo", to: "claude"
    execute "UPDATE phase_runs SET runner = 'claude' WHERE runner = 'demo'"
  end

  def down
    change_column_default :phase_runs, :runner, from: "claude", to: "demo"
  end
end
