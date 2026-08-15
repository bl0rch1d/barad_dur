// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import { Turbo } from "@hotwired/turbo-rails"
import "controllers"

// Broadcast-triggered page refreshes are visits to the CURRENT location, and
// Turbo cancels the previous visit when a new one starts — so a live refresh
// arriving mid-navigation would silently cancel the user's navigation (e.g.
// the wizard's go-live redirect to step 6). Defer refreshes while a visit is
// in flight and apply a single one after landing.
let deferredRefresh = false
let blockRefreshesUntil = 0

const originalRefresh = Turbo.StreamActions.refresh
Turbo.StreamActions.refresh = function (...args) {
  if (Date.now() < blockRefreshesUntil) {
    deferredRefresh = true
    return
  }
  originalRefresh.apply(this, args)
}

document.addEventListener("turbo:visit", () => {
  // safety-capped so a lost load event can never mute live updates for good
  blockRefreshesUntil = Date.now() + 4000
})

document.addEventListener("turbo:load", () => {
  blockRefreshesUntil = 0
  if (deferredRefresh) {
    deferredRefresh = false
    setTimeout(() => Turbo.session.refresh(document.baseURI), 300)
  }
})
