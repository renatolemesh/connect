class CreateWhatsappRetrySettings < ActiveRecord::Migration[7.1]
  def change
    create_table :whatsapp_retry_settings do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }
      t.boolean :enabled, null: false, default: false
      t.jsonb :config, null: false, default: {}
      t.datetime :last_run_at
      t.jsonb :last_run_summary, null: false, default: {}

      t.timestamps
    end
  end
end
