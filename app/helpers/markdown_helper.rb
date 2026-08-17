require "kramdown"
require "kramdown-parser-gfm"

# Agent replies arrive as GitHub-flavored markdown — tables, fenced code,
# lists, inline code. Rendered here, then sanitized: the source is model
# output quoting arbitrary repository content, so raw HTML in it is never
# trusted.
module MarkdownHelper
  ALLOWED_TAGS = %w[
    p br strong em del code pre blockquote a hr
    ul ol li h1 h2 h3 h4 h5 h6
    table thead tbody tr th td
  ].freeze

  ALLOWED_ATTRIBUTES = %w[href title class target rel].freeze

  def markdown(text)
    return "".html_safe if text.blank?

    html = Kramdown::Document.new(
      text.to_s,
      input: "GFM",
      hard_wrap: true,       # a lone newline is a line break, as in chat
      auto_ids: false,       # no heading anchors — these aren't documents
      smart_quotes: %w[apos apos quot quot],
      entity_output: :as_char
    ).to_html

    # GFM treats \| inside a table cell as a literal pipe; kramdown splits the
    # row on it correctly but leaves the backslash behind in the cell.
    html = html.gsub(%r{(<t[dh][^>]*>)(.*?)(</t[dh]>)}m) { "#{$1}#{$2.gsub('\\|', '|')}#{$3}" }

    # Anything the agent links to is outside this app.
    html = html.gsub("<a href=", '<a target="_blank" rel="noopener noreferrer" href=')

    sanitize(html, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRIBUTES)
  rescue StandardError
    # A malformed document must never take the page down — show the source.
    tag.pre(text.to_s)
  end
end
