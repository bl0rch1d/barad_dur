require "test_helper"

class MarkdownHelperTest < ActionView::TestCase
  test "renders the GFM agents actually reply with" do
    html = markdown(<<~MD)
      **Branch:** `master`, clean.

      - first
      - second

      | Command | Does |
      |---|---|
      | `/review <slug \\| branch>` | reviews it |

      ```ruby
      puts "hi"
      ```
    MD

    assert_includes html, "<strong>Branch:</strong>"
    assert_includes html, "<code>master</code>"
    assert_includes html, "<li>first</li>"
    assert_includes html, "<table>"
    assert_includes html, "<pre>"
    assert_includes html, "&lt;slug | branch&gt;", "escaped pipes become literal inside cells"
  end

  test "a lone newline breaks the line, as in chat" do
    assert_includes markdown("one\ntwo"), "<br"
  end

  test "untrusted html in agent output is neutralised" do
    html = markdown("<script>alert(1)</script><img src=x onerror=alert(1)>hello")
    # no live tags survive — the img is escaped to inert text, script is gone
    assert_not_includes html, "<script"
    assert_not_includes html, "<img"
    assert_includes html, "&lt;img"
    assert_includes html, "hello"

    assert_not_includes markdown("[x](javascript:alert(1))"), "javascript:"
  end

  test "links leave the app in a new tab" do
    html = markdown("[docs](https://example.com)")
    assert_includes html, 'target="_blank"'
    assert_includes html, 'rel="noopener noreferrer"'
  end

  test "blank input renders nothing and bad input never raises" do
    assert_equal "", markdown(nil)
    assert_equal "", markdown("")
    assert_nothing_raised { markdown("| broken | table\n|---|") }
  end
end
