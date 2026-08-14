class CreateCoreSchema < ActiveRecord::Migration[8.1]
  def change
    create_table :settings do |t|
      t.string :autonomy, null: false, default: "auto"
      t.boolean :running, null: false, default: true
      t.decimal :spend_today, precision: 8, scale: 2, null: false, default: 0
      t.decimal :spend_cap, precision: 8, scale: 2, null: false, default: 80
      t.jsonb :setup, null: false, default: {}
      t.boolean :setup_complete, null: false, default: false
      t.integer :tick_count, null: false, default: 0
      t.timestamps
    end

    create_table :agents do |t|
      t.string :name, null: false
      t.string :abbr, null: false
      t.string :role, null: false
      t.string :llm_model, null: false
      t.string :status, null: false, default: "idle"
      t.string :doing
      t.jsonb :tools, null: false, default: []
      t.decimal :cost_today, precision: 8, scale: 2, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :tickets do |t|
      t.string :code, null: false, index: { unique: true }
      t.string :title, null: false
      t.string :repo
      t.string :est_label
      t.boolean :risky, null: false, default: false
      t.integer :state, null: false, default: 0
      t.references :agent, foreign_key: true
      t.integer :phase_progress, null: false, default: 0
      t.decimal :cost, precision: 8, scale: 2, null: false, default: 0
      t.string :tokens_label
      t.jsonb :diff, null: false, default: []
      t.jsonb :dep_codes, null: false, default: []
      t.jsonb :artifacts, null: false, default: []
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end

    create_table :phase_runs do |t|
      t.references :ticket, null: false, foreign_key: true
      t.string :phase, null: false
      t.string :status, null: false, default: "running"
      t.string :note
      t.datetime :started_at
      t.datetime :finished_at
      t.integer :duration_s
      t.timestamps
    end

    create_table :events do |t|
      t.datetime :happened_at, null: false
      t.string :phase_tag, null: false
      t.string :tone
      t.text :text, null: false
      t.string :ticket_code
      t.string :agent_name
      t.string :meta
      t.decimal :cost, precision: 6, scale: 2, null: false, default: 0
      t.timestamps
    end
    add_index :events, :happened_at

    create_table :capabilities do |t|
      t.string :slug, null: false, index: { unique: true }
      t.string :file, null: false
      t.string :title, null: false
      t.text :purpose
      t.string :meta_label
      t.jsonb :tags, null: false, default: []
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :spec_requirements do |t|
      t.references :capability, null: false, foreign_key: true
      t.string :rid, null: false
      t.string :name, null: false
      t.string :status, null: false, default: "pending"
      t.text :body
      t.string :impl_ref
      t.string :tests_label
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :spec_scenarios do |t|
      t.references :spec_requirement, null: false, foreign_key: true
      t.string :name, null: false
      t.text :body
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :rfcs do |t|
      t.text :body
      t.integer :stage, null: false, default: 0
      t.jsonb :trace, null: false, default: []
      t.jsonb :questions, null: false, default: []
      t.jsonb :answers, null: false, default: {}
      t.jsonb :proposals, null: false, default: []
      t.boolean :pushed, null: false, default: false
      t.timestamps
    end

    create_table :chat_messages do |t|
      t.string :room, null: false, default: "ALG-215"
      t.string :sender, null: false
      t.text :body, null: false
      t.string :attach_label
      t.datetime :sent_at, null: false
      t.timestamps
    end

    create_table :gates do |t|
      t.references :ticket, null: false, foreign_key: true
      t.integer :to_state, null: false
      t.text :reason, null: false
      t.string :status, null: false, default: "pending"
      t.timestamps
    end

    create_table :questions do |t|
      t.string :ticket_code, null: false
      t.string :phase
      t.text :body, null: false
      t.string :why
      t.jsonb :options, null: false, default: []
      t.string :chosen
      t.string :status, null: false, default: "pending"
      t.datetime :asked_at, null: false
      t.timestamps
    end

    create_table :commit_records do |t|
      t.string :sha, null: false
      t.string :message, null: false
      t.string :author
      t.datetime :committed_at, null: false
      t.timestamps
    end

    create_table :releases do |t|
      t.string :version, null: false
      t.string :kind, null: false, default: "staged"
      t.string :date_label
      t.jsonb :lines, null: false, default: []
      t.integer :position, null: false, default: 0
      t.datetime :released_at
      t.timestamps
    end

    create_table :ci_suites do |t|
      t.string :name, null: false
      t.integer :pct, null: false, default: 100
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :spend_samples do |t|
      t.datetime :bucket, null: false, index: { unique: true }
      t.decimal :amount, precision: 8, scale: 2, null: false, default: 0
      t.timestamps
    end
  end
end
