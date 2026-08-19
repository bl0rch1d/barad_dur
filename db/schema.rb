# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_19_000004) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "agents", force: :cascade do |t|
    t.string "abbr", null: false
    t.datetime "created_at", null: false
    t.string "doing"
    t.string "llm_model", null: false
    t.string "model_id"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.string "role", null: false
    t.string "status", default: "idle", null: false
    t.jsonb "tools", default: [], null: false
    t.datetime "updated_at", null: false
  end

  create_table "capabilities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "file", null: false
    t.string "meta_label"
    t.integer "position", default: 0, null: false
    t.text "purpose"
    t.string "slug", null: false
    t.jsonb "tags", default: [], null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_capabilities_on_slug", unique: true
  end

  create_table "chat_messages", force: :cascade do |t|
    t.string "attach_label"
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.string "room", default: "ALG-215", null: false
    t.string "sender", null: false
    t.datetime "sent_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "commit_records", force: :cascade do |t|
    t.string "author"
    t.datetime "committed_at", null: false
    t.datetime "created_at", null: false
    t.string "message", null: false
    t.string "sha", null: false
    t.datetime "updated_at", null: false
  end

  create_table "events", force: :cascade do |t|
    t.string "agent_name"
    t.decimal "cost", precision: 6, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "happened_at", null: false
    t.string "meta"
    t.string "phase_tag", null: false
    t.text "text", null: false
    t.string "ticket_code"
    t.string "tone"
    t.datetime "updated_at", null: false
    t.index ["happened_at"], name: "index_events_on_happened_at"
  end

  create_table "gates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "reason", null: false
    t.string "status", default: "pending", null: false
    t.bigint "ticket_id", null: false
    t.integer "to_state", null: false
    t.datetime "updated_at", null: false
    t.index ["ticket_id"], name: "index_gates_on_ticket_id"
  end

  create_table "phase_runs", force: :cascade do |t|
    t.decimal "cost", precision: 8, scale: 4, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.integer "duration_s"
    t.integer "exit_status"
    t.datetime "finished_at"
    t.text "log"
    t.string "note"
    t.string "phase", null: false
    t.string "runner", default: "claude", null: false
    t.string "session_id"
    t.datetime "started_at"
    t.string "status", default: "running", null: false
    t.jsonb "test_suites", default: [], null: false
    t.string "tests_command"
    t.boolean "tests_executed", default: false, null: false
    t.integer "tests_failed"
    t.integer "tests_passed"
    t.bigint "ticket_id", null: false
    t.datetime "updated_at", null: false
    t.index ["ticket_id"], name: "index_phase_runs_on_ticket_id"
  end

  create_table "questions", force: :cascade do |t|
    t.datetime "asked_at", null: false
    t.text "body", null: false
    t.string "chosen"
    t.datetime "created_at", null: false
    t.jsonb "options", default: [], null: false
    t.string "phase"
    t.string "status", default: "pending", null: false
    t.string "ticket_code", null: false
    t.datetime "updated_at", null: false
    t.string "why"
  end

  create_table "releases", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "date_label"
    t.string "kind", default: "staged", null: false
    t.jsonb "lines", default: [], null: false
    t.integer "position", default: 0, null: false
    t.datetime "released_at"
    t.datetime "updated_at", null: false
    t.string "version", null: false
  end

  create_table "rfcs", force: :cascade do |t|
    t.jsonb "answers", default: {}, null: false
    t.text "body"
    t.datetime "created_at", null: false
    t.string "error"
    t.string "job_state", default: "idle", null: false
    t.string "progress_note"
    t.jsonb "proposals", default: [], null: false
    t.boolean "pushed", default: false, null: false
    t.jsonb "questions", default: [], null: false
    t.integer "stage", default: 0, null: false
    t.jsonb "trace", default: [], null: false
    t.datetime "updated_at", null: false
  end

  create_table "settings", force: :cascade do |t|
    t.string "autonomy", default: "auto", null: false
    t.datetime "created_at", null: false
    t.boolean "running", default: true, null: false
    t.jsonb "setup", default: {}, null: false
    t.boolean "setup_complete", default: false, null: false
    t.decimal "spend_cap", precision: 10, scale: 2, default: "80.0", null: false
    t.datetime "updated_at", null: false
  end

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", null: false
    t.bigint "channel_hash", null: false
    t.datetime "created_at", null: false
    t.binary "payload", null: false
    t.index ["channel"], name: "index_solid_cable_messages_on_channel"
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "spec_requirements", force: :cascade do |t|
    t.text "body"
    t.bigint "capability_id", null: false
    t.datetime "created_at", null: false
    t.string "impl_ref"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.string "rid", null: false
    t.string "status", default: "pending", null: false
    t.string "tests_label"
    t.datetime "updated_at", null: false
    t.index ["capability_id"], name: "index_spec_requirements_on_capability_id"
  end

  create_table "spec_scenarios", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.bigint "spec_requirement_id", null: false
    t.datetime "updated_at", null: false
    t.index ["spec_requirement_id"], name: "index_spec_scenarios_on_spec_requirement_id"
  end

  create_table "spend_entries", force: :cascade do |t|
    t.bigint "agent_id"
    t.decimal "amount", precision: 10, scale: 4, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.string "llm_model"
    t.datetime "occurred_at", null: false
    t.string "phase"
    t.string "source", null: false
    t.string "ticket_code"
    t.datetime "updated_at", null: false
    t.index ["occurred_at"], name: "index_spend_entries_on_occurred_at"
    t.index ["source", "occurred_at"], name: "index_spend_entries_on_source_and_occurred_at"
    t.index ["ticket_code"], name: "index_spend_entries_on_ticket_code"
  end

  create_table "tickets", force: :cascade do |t|
    t.jsonb "acceptance_criteria", default: [], null: false
    t.bigint "agent_id"
    t.jsonb "artifacts", default: [], null: false
    t.string "code", null: false
    t.decimal "cost", precision: 10, scale: 4, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.jsonb "dep_codes", default: [], null: false
    t.text "description"
    t.jsonb "diff", default: [], null: false
    t.string "est_label"
    t.text "feedback"
    t.datetime "finished_at"
    t.string "pr_url"
    t.string "repo"
    t.boolean "risky", default: false, null: false
    t.datetime "started_at"
    t.integer "state", default: 0, null: false
    t.text "technical_notes"
    t.string "title", null: false
    t.string "tokens_label"
    t.datetime "updated_at", null: false
    t.index ["agent_id"], name: "index_tickets_on_agent_id"
    t.index ["code"], name: "index_tickets_on_code", unique: true
  end

  add_foreign_key "gates", "tickets"
  add_foreign_key "phase_runs", "tickets"
  add_foreign_key "spec_requirements", "capabilities"
  add_foreign_key "spec_scenarios", "spec_requirements"
  add_foreign_key "tickets", "agents"
end
