import { Controller } from "@hotwired/stimulus"

// Tab-title "(N)" prefix + favicon badge whenever gates, questions or failed
// runs are waiting on the operator. Lives on <body>; morph refreshes update
// the count value and the change callback re-renders.
export default class extends Controller {
  static values = { count: Number }

  connect() {
    this.baseTitle = document.title.replace(/^\(\d+\+?\) /, "")
    this.render()
  }

  countValueChanged() {
    if (this.baseTitle !== undefined) this.render()
  }

  render() {
    const n = this.countValue
    document.title = n > 0 ? `(${n}) ${this.baseTitle}` : this.baseTitle

    const link = document.getElementById("favicon")
    if (!link) return
    if (n === 0) {
      link.href = "data:,"
      return
    }
    const canvas = document.createElement("canvas")
    canvas.width = canvas.height = 32
    const ctx = canvas.getContext("2d")
    ctx.fillStyle = "#ff6a2b"
    ctx.beginPath()
    ctx.arc(16, 16, 14, 0, Math.PI * 2)
    ctx.fill()
    ctx.fillStyle = "#fff"
    ctx.font = "bold 17px sans-serif"
    ctx.textAlign = "center"
    ctx.textBaseline = "middle"
    ctx.fillText(n > 9 ? "9+" : String(n), 16, 17)
    link.href = canvas.toDataURL("image/png")
  }
}
