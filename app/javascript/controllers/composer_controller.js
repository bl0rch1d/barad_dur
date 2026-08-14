import { Controller } from "@hotwired/stimulus"

// Clears a (data-turbo-permanent) textarea after its form submits, and lets
// Enter submit while Shift+Enter inserts a newline.
export default class extends Controller {
  static targets = ["input"]

  clear() {
    if (this.hasInputTarget) this.inputTarget.value = ""
  }

  submitOnEnter(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      this.element.requestSubmit()
    }
  }
}
