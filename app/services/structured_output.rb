require "json"

# Pulls a structured JSON payload out of an agent's free-text final message.
# Agents are prompted to end with a fenced ```json block; falls back to the
# widest brace span when the fence is missing.
module StructuredOutput
  module_function

  def json_block(text)
    return nil if text.blank?

    fenced = text.scan(/```json\s*(.+?)```/m).last
    raw = fenced ? fenced[0] : text[/\{.*\}/m]
    return nil if raw.blank?

    JSON.parse(raw)
  rescue JSON::ParserError
    nil
  end
end
