import { Controller } from "@hotwired/stimulus"

// Switches the color theme instantly and persists it in a cookie the server
// reads on the next render, so Turbo morphs keep the choice.
export default class extends Controller {
  set(event) {
    const theme = event.params.theme
    document.cookie = `theme=${theme};path=/;max-age=31536000;samesite=lax`
    document.documentElement.dataset.theme = theme
    document.body.dataset.theme = theme
    this.element.querySelectorAll("button").forEach((button) => {
      button.classList.toggle("on", button === event.currentTarget)
    })
  }
}
