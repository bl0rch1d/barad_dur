import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Attached to elements that visualize an in-flight server-side transition
// (go-live stages, spec-parse progress). Re-renders the page every second so
// the display advances even when broadcast refreshes are deferred or missed;
// vanishes with its element once the server clears the progress state.
export default class extends Controller {
  static values = { interval: { type: Number, default: 1000 } }

  connect() {
    this.timer = setInterval(() => {
      if (document.visibilityState === "visible") {
        Turbo.session.refresh(window.location.href)
      }
    }, this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }
}
