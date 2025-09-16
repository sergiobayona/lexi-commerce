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

ActiveRecord::Schema[8.0].define(version: 2025_09_16_153610) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "wa_business_numbers", force: :cascade do |t|
    t.string "phone_number_id"
    t.string "display_phone_number"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["phone_number_id"], name: "index_wa_business_numbers_on_phone_number_id", unique: true
  end

  create_table "wa_contacts", force: :cascade do |t|
    t.string "wa_id"
    t.string "profile_name"
    t.string "identity_key_hash"
    t.datetime "identity_last_changed_at"
    t.datetime "first_seen_at"
    t.datetime "last_seen_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["wa_id"], name: "index_wa_contacts_on_wa_id", unique: true
  end

  create_table "wa_media", force: :cascade do |t|
    t.string "provider_media_id"
    t.string "sha256"
    t.string "mime_type"
    t.boolean "is_voice"
    t.bigint "bytes"
    t.string "storage_url"
    t.string "download_status"
    t.text "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider_media_id"], name: "index_wa_media_on_provider_media_id", unique: true
    t.index ["sha256"], name: "index_wa_media_on_sha256", unique: true
  end

  create_table "wa_message_media", force: :cascade do |t|
    t.bigint "wa_message_id", null: false
    t.bigint "wa_media_id", null: false
    t.string "purpose"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["wa_media_id"], name: "index_wa_message_media_on_wa_media_id"
    t.index ["wa_message_id"], name: "index_wa_message_media_on_wa_message_id"
  end

  create_table "wa_message_status_events", force: :cascade do |t|
    t.string "provider_message_id"
    t.string "event_type"
    t.datetime "event_timestamp"
    t.jsonb "raw"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "wa_messages", force: :cascade do |t|
    t.string "provider_message_id", null: false
    t.string "direction"
    t.bigint "wa_contact_id", null: false
    t.bigint "wa_business_number_id", null: false
    t.string "type_name"
    t.text "body_text"
    t.datetime "timestamp"
    t.string "status", default: "received"
    t.string "context_msg_id"
    t.boolean "has_media", default: false
    t.string "media_kind"
    t.jsonb "wa_contact_snapshot"
    t.jsonb "metadata_snapshot"
    t.jsonb "raw", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider_message_id"], name: "index_wa_messages_on_provider_message_id", unique: true
    t.index ["wa_business_number_id"], name: "index_wa_messages_on_wa_business_number_id"
    t.index ["wa_contact_id"], name: "index_wa_messages_on_wa_contact_id"
  end

  create_table "wa_referrals", force: :cascade do |t|
    t.bigint "wa_message_id", null: false
    t.string "source_url"
    t.string "source_id"
    t.string "source_type"
    t.text "body"
    t.text "headline"
    t.string "media_type"
    t.string "image_url"
    t.string "video_url"
    t.string "thumbnail_url"
    t.string "ctwa_clid"
    t.jsonb "welcome_message_json"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["wa_message_id"], name: "index_wa_referrals_on_wa_message_id"
  end

  create_table "webhook_events", force: :cascade do |t|
    t.string "provider", null: false, comment: "e.g. 'whatsapp'"
    t.string "object_name", comment: "top-level 'object' field from the webhook"
    t.jsonb "payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_webhook_events_on_created_at"
    t.index ["payload"], name: "index_webhook_events_on_payload", using: :gin
    t.index ["provider"], name: "index_webhook_events_on_provider"
  end

  add_foreign_key "wa_message_media", "wa_media", column: "wa_media_id"
  add_foreign_key "wa_message_media", "wa_messages"
  add_foreign_key "wa_messages", "wa_business_numbers"
  add_foreign_key "wa_messages", "wa_contacts"
  add_foreign_key "wa_referrals", "wa_messages"
end
