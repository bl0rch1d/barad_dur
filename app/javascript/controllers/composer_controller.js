import { Controller } from "@hotwired/stimulus"

// Clears a (data-turbo-permanent) textarea after its form submits, and lets
// Enter submit while Shift+Enter inserts a newline.
export default class extends Controller {
  static targets = ["input"]

  clear() {
    if (!this.hasInputTarget) return
    this.inputTarget.value = ""
    this.inputTarget.style.height = ""
  }

  // grow with the text instead of scrolling inside two lines
  autogrow() {
    const el = this.inputTarget
    el.style.height = "auto"
    el.style.height = Math.min(el.scrollHeight, 170) + "px"
  }

  submitOnEnter(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      this.element.requestSubmit()
    }
  }
}
