Rails.application.routes.draw do
  root "dashboard#show"

  get "board"         => "board#show",    as: :board
  get "rfc"           => "rfcs#show",     as: :rfc
  get "agents"        => "agents#index",  as: :agents
  get "activity"      => "activity#show", as: :activity
  get "specs(/*slug)" => "specs#show",    as: :specs, format: false

  post "rfc/advance" => "rfcs#advance", as: :rfc_advance
  post "rfc/reset"   => "rfcs#reset",   as: :rfc_reset
  post "rfc/answer"  => "rfcs#answer",  as: :rfc_answer
  post "rfc/push"    => "rfcs#push",    as: :rfc_push

  post "chat" => "chat_messages#create", as: :chat_messages

  post "settings/autonomy"   => "settings#autonomy",   as: :settings_autonomy
  post "settings/toggle_run" => "settings#toggle_run", as: :settings_toggle_run
  post "settings/stop"       => "settings#stop",       as: :settings_stop

  post "gates/:id/approve"    => "gates#approve",    as: :approve_gate
  post "questions/:id/answer" => "questions#answer", as: :answer_question
  post "tickets/:code/phase"  => "tickets#phase",    as: :ticket_phase
  post "tickets/:code/groom"  => "tickets#groom",    as: :ticket_groom
  post "tickets/:code/merge"  => "tickets#merge",    as: :ticket_merge
  post "tickets/:code/request_changes" => "tickets#request_changes", as: :ticket_request_changes
  post "tickets/:code/enrich" => "tickets#enrich", as: :ticket_enrich

  post "wizard/patch"  => "wizard#patch",  as: :wizard_patch
  post "wizard/finish" => "wizard#finish", as: :wizard_finish

  post "specs_sync" => "specs#sync",     as: :specs_sync
  post "tickets"    => "tickets#create", as: :tickets

  get "up" => "rails/health#show", as: :rails_health_check
end
