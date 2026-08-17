import { Controller } from "@hotwired/stimulus"

// Keeps the newest message in view. Morph refreshes replace the log's
// children without reconnecting this controller, hence the observer — but
// only follow along when the reader is already at the bottom, so scrolling
// back through history isn't yanked away every few seconds.
export default class extends Controller {
  connect() {
    this.toBottom(true)
    this.observer = new MutationObserver(() => this.toBottom(false))
    this.observer.observe(this.element, { childList: true, subtree: true })
  }

  disconnect() {
    this.observer?.disconnect()
  }

  toBottom(force) {
    const el = this.element
    const distance = el.scrollHeight - el.scrollTop - el.clientHeight
    if (force || distance < 140) el.scrollTop = el.scrollHeight
  }
}
