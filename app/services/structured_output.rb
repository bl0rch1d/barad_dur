require "json"

# Pulls a structured JSON payload out of an agent's free-text final message.
#
# Agents are prompted to end with a fenced ```json block, and they also
# volunteer unrequested ones: a review report is mostly code fences, and the
# last of them is very often an example the agent was explaining rather than
# the contract it was asked for. Every contract therefore carries a sentinel
# ("_c": "review.v1") and the block carrying it wins wherever it sits.
module StructuredOutput
  module_function

  # expect: the phase name whose sentinel to prefer ("review" -> "review.v1").
  def json_block(text, expect: nil)
    return nil if text.blank?

    blocks = fenced(text)
    if expect
      sentinel = blocks.reverse.find { |data| data["_c"].to_s.start_with?("#{expect}.") }
      return sentinel if sentinel
    end
    blocks.last || braces(text)
  end

  def fenced(text)
    text.to_s.scan(/```json\s*(.+?)```/m).filter_map do |(raw)|
      data = JSON.parse(raw)
      data if data.is_a?(Hash)
    rescue JSON::ParserError
      nil
    end
  end

  # No fence at all: the widest brace span is the last resort it always was.
  def braces(text)
    raw = text[/\{.*\}/m] or return nil

    data = JSON.parse(raw)
    data if data.is_a?(Hash)
  rescue JSON::ParserError
    nil
  end
end
