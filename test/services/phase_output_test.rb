require "test_helper"

# The runs that die at the turn limit are the runs that did the most work.
# Everything they reported has to survive the death, or the retry starts from
# nothing and the money is spent twice.
class PhaseOutputTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir
    ENV["PHASE_OUT_DIR"] = @dir
    @ticket = Ticket.create!(code: "TST-O1", title: "Cache metadata", repo: "sample-repo",
                             state: :investigation)
    @run = @ticket.phase_runs.create!(phase: "investigation", status: "running", started_at: Time.current)
  end

  teardown do
    ENV.delete("PHASE_OUT_DIR")
    FileUtils.remove_entry(@dir)
  end

  def write_out(data)
    File.write(PhaseOutput.path_for(@run), JSON.generate(data))
  end

  test "the out-file is read when the run never produced a final message" do
    write_out({ "questions" => [{ "q" => "Cache where?", "opts" => %w[Memory Disk] }] })

    ClaudeCodeRunner.new(@ticket, @run).send(:handle_structured_output, nil)

    assert_equal 1, Question.where(ticket_code: "TST-O1").count,
                 "a run cut short still asked the user something"
  end

  test "the final message still works when nothing reached disk" do
    result = Struct.new(:result_text).new(<<~TXT)
      Here is what I found.
      ```json
      {"questions": [{"q": "Cache where?", "opts": ["Memory", "Disk"]}]}
      ```
    TXT

    ClaudeCodeRunner.new(@ticket, @run).send(:handle_structured_output, result)

    assert_equal 1, Question.where(ticket_code: "TST-O1").count
  end

  test "the file wins over the final message, being the one a dying run writes first" do
    write_out({ "questions" => [{ "q" => "From the file", "opts" => %w[A B] }] })
    result = Struct.new(:result_text).new('```json
      {"questions": [{"q": "From the message", "opts": ["A", "B"]}]}
    ```')

    ClaudeCodeRunner.new(@ticket, @run).send(:handle_structured_output, result)

    assert_equal ["From the file"], Question.where(ticket_code: "TST-O1").pluck(:body)
  end

  test "the out-file is cleared after it is read, so a retry cannot inherit it" do
    write_out({ "questions" => [{ "q" => "Cache where?", "opts" => %w[Memory Disk] }] })

    ClaudeCodeRunner.new(@ticket, @run).send(:handle_structured_output, nil)

    refute File.exist?(PhaseOutput.path_for(@run))
  end

  test "a corrupt out-file degrades to the final message rather than raising" do
    File.write(PhaseOutput.path_for(@run), "{ this is not json")

    assert_nil PhaseOutput.from_file(@run)
    assert_nothing_raised do
      ClaudeCodeRunner.new(@ticket, @run).send(:handle_structured_output, nil)
    end
  end

  test "every contract tells the agent to write its answer to disk first" do
    %w[investigation planning review testing].each do |phase|
      ticket = Ticket.create!(code: "TST-O#{phase[0..2]}", title: "t", repo: "sample-repo", state: phase.to_sym)
      run = ticket.phase_runs.create!(phase: phase, status: "running", started_at: Time.current)
      plan = PhasePrompts.execution(ticket, phase, "/nonexistent-repo", Setting.instance, run)

      assert_includes plan[:prompt], PhaseOutput.path_for(run), "#{phase} has no out-file"
      assert_match(/before you finish/i, plan[:prompt], "#{phase} was not told when to write it")
    end
  end

  test "a phase with no contract is not given an out-file to write" do
    ticket = Ticket.create!(code: "TST-O9", title: "t", repo: "sample-repo", state: :implementation)
    run = ticket.phase_runs.create!(phase: "implementation", status: "running", started_at: Time.current)

    plan = PhasePrompts.execution(ticket, "implementation", "/nonexistent-repo", Setting.instance, run)

    refute_includes plan[:prompt], PhaseOutput.path_for(run)
  end
end
