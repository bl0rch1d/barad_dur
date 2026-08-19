import { Controller } from "@hotwired/stimulus"

// Smooth cosmetic progress that actually finishes: eases quickly out of 0,
// slows near the end, then snaps to 100%, flips the title to its done state
// and stops. Rows with a data-threshold tick from pending (◦) to done (✓) as
// the bar passes them. The host element is data-turbo-permanent so live morph
// refreshes don't reset the animation.
export default class extends Controller {
  static targets = ["bar", "label", "row", "title"]
  static values = {
    cap: { type: Number, default: 100 },
    doneLabel: { type: String, default: "done" },
    // real work is in flight: show its actual position and do not complete
    busy: { type: Boolean, default: false },
    pct: { type: Number, default: 0 }
  }

  connect() {
    // A spec parse can run for minutes. Easing a cosmetic bar to 100% over it
    // would claim the work was finished — and unlock Continue — while the
    // parse was still going. Show where it really is instead.
    if (this.busyValue) {
      this.showActual()
      return
    }
    if (this.alreadyCompleted()) {
      this.finish()
      return
    }
    this.start = performance.now()
    this.tick = this.tick.bind(this)
    this.frame = requestAnimationFrame(this.tick)
  }

  // Rendered fresh by each live refresh while the work runs, so there is
  // nothing to animate — just paint the server's numbers and stay locked.
  showActual() {
    this.render(Math.min(this.pctValue, this.capValue))
    document.querySelectorAll("[data-progress-unlock]").forEach((el) => el.classList.add("locked"))
  }

  disconnect() {
    cancelAnimationFrame(this.frame)
  }

  tick(now) {
    const seconds = (now - this.start) / 1000
    const pct = this.capValue * (1 - Math.exp(-seconds / 2.2))

    if (pct >= this.capValue - 1) {
      this.finish()
      return
    }

    this.render(pct)
    this.frame = requestAnimationFrame(this.tick)
  }

  render(pct) {
    if (this.hasBarTarget) this.barTarget.style.width = `${pct.toFixed(1)}%`
    if (this.hasLabelTarget) this.labelTarget.textContent = `${Math.floor(pct)}%`
    this.rowTargets.forEach((row) => {
      if (pct < parseFloat(row.dataset.threshold || "101")) return
      this.completeRow(row)
    })
  }

  finish() {
    if (this.hasBarTarget) {
      this.barTarget.style.width = "100%"
      this.barTarget.style.background = "var(--ok)"
    }
    if (this.hasLabelTarget) {
      this.labelTarget.textContent = "100%"
      this.labelTarget.style.color = "var(--ok)"
    }
    this.rowTargets.forEach((row) => this.completeRow(row))
    if (this.hasTitleTarget) {
      this.titleTarget.textContent = this.doneLabelValue
      this.titleTarget.style.color = "var(--ok)"
    }
    this.rememberCompleted()
    document.querySelectorAll("[data-progress-unlock]").forEach((el) => el.classList.remove("locked"))
  }

  alreadyCompleted() {
    try {
      return sessionStorage.getItem("barad-dur-indexing-complete") === "1"
    } catch {
      return false
    }
  }

  rememberCompleted() {
    try {
      sessionStorage.setItem("barad-dur-indexing-complete", "1")
    } catch {
      // private-mode storage unavailable — re-animate next visit instead
    }
  }

  completeRow(row) {
    const mark = row.querySelector("[data-mark]")
    if (mark && mark.textContent !== "✓") {
      mark.textContent = "✓"
      mark.style.color = "var(--ok)"
    }
  }
}
