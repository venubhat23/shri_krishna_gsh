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

ActiveRecord::Schema[8.0].define(version: 2025_11_22_020637) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "admin_settings", force: :cascade do |t|
    t.string "business_name"
    t.text "address"
    t.string "mobile"
    t.string "email"
    t.string "gstin"
    t.string "pan_number"
    t.string "account_holder_name"
    t.string "bank_name"
    t.string "account_number"
    t.string "ifsc_code"
    t.string "upi_id"
    t.text "terms_and_conditions"
    t.string "qr_code_path"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "faq"
    t.text "contact_us"
    t.text "privacy_policy"
    t.boolean "show_dashboard", default: true
    t.boolean "show_orders", default: true
    t.boolean "show_customers", default: true
    t.boolean "show_products", default: true
    t.boolean "show_categories", default: true
    t.boolean "show_delivery_assignments", default: true
    t.boolean "show_invoices", default: true
    t.boolean "show_milk_analytics", default: true
    t.boolean "show_procurement", default: true
    t.boolean "show_payouts", default: true
    t.boolean "show_reports", default: true
    t.boolean "show_users", default: true
    t.boolean "show_settings", default: true
    t.boolean "show_ai_insights"
    t.boolean "show_franchise"
    t.boolean "show_affiliates"
    t.boolean "show_sales"
    t.boolean "show_inventory"
    t.boolean "show_analytics"
    t.boolean "show_notifications"
    t.boolean "show_settings_advanced"
    t.boolean "show_my_bookings"
    t.boolean "show_customer_patterns"
    t.boolean "show_customer_points"
    t.boolean "show_customer_wallets"
    t.boolean "show_customer_details"
    t.boolean "show_advertisements"
    t.boolean "show_schedules"
    t.boolean "show_pending_payments"
    t.boolean "show_delivery_review"
    t.boolean "show_purchase_invoices"
    t.boolean "show_sales_invoices"
    t.boolean "show_whatsapp_messages"
  end

  create_table "advertisements", force: :cascade do |t|
    t.string "name", null: false
    t.string "image_url"
    t.date "start_date", null: false
    t.date "end_date", null: false
    t.string "status", default: "active"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["end_date"], name: "index_advertisements_on_end_date"
    t.index ["start_date", "end_date"], name: "index_advertisements_on_start_date_and_end_date"
    t.index ["start_date"], name: "index_advertisements_on_start_date"
    t.index ["status"], name: "index_advertisements_on_status"
    t.index ["user_id"], name: "index_advertisements_on_user_id"
  end

  create_table "affiliate_bookings", force: :cascade do |t|
    t.bigint "affiliate_id", null: false
    t.bigint "product_id", null: false
    t.decimal "quantity"
    t.decimal "price"
    t.string "status"
    t.date "booking_date"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["affiliate_id"], name: "index_affiliate_bookings_on_affiliate_id"
    t.index ["product_id"], name: "index_affiliate_bookings_on_product_id"
  end

  create_table "affiliates", force: :cascade do |t|
    t.string "name"
    t.string "email"
    t.string "phone"
    t.string "password_digest"
    t.string "location"
    t.decimal "commission_rate"
    t.decimal "total_earnings"
    t.string "status"
    t.boolean "active"
    t.string "referral_code"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "categories", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.string "color", null: false
    t.boolean "is_active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["is_active"], name: "index_categories_on_is_active"
    t.index ["name"], name: "index_categories_on_name", unique: true
  end

  create_table "cms_pages", force: :cascade do |t|
    t.string "slug", null: false
    t.string "version", default: "v1.0", null: false
    t.string "title", null: false
    t.text "content", null: false
    t.string "locale", default: "en", null: false
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["published_at"], name: "index_cms_pages_on_published_at"
    t.index ["slug", "locale"], name: "index_cms_pages_on_slug_and_locale", unique: true
  end

  create_table "coupons", force: :cascade do |t|
    t.string "code"
    t.decimal "amount"
    t.text "description"
    t.datetime "expires_at"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "customer_addresses", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.string "address_type"
    t.text "street_address"
    t.string "city"
    t.string "state"
    t.string "pincode"
    t.string "landmark"
    t.boolean "is_default"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_customer_addresses_on_customer_id"
  end

  create_table "customer_points", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.decimal "points", precision: 10, scale: 2, default: "0.0"
    t.string "action_type", null: false
    t.integer "reference_id"
    t.string "reference_type"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id", "action_type"], name: "index_customer_points_on_customer_id_and_action_type"
    t.index ["customer_id"], name: "index_customer_points_on_customer_id"
    t.index ["reference_type", "reference_id"], name: "index_customer_points_on_reference_type_and_reference_id"
  end

  create_table "customer_preferences", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.string "language"
    t.time "delivery_time_start"
    t.time "delivery_time_end"
    t.boolean "skip_weekends"
    t.text "special_instructions"
    t.text "notification_preferences"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "referral_code"
    t.decimal "referral_earnings", precision: 10, scale: 2, default: "0.0"
    t.text "address_request_notes"
    t.boolean "referral_enabled", default: true
    t.index ["customer_id"], name: "index_customer_preferences_on_customer_id"
  end

  create_table "customers", force: :cascade do |t|
    t.string "name"
    t.string "address"
    t.decimal "latitude"
    t.decimal "longitude"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "delivery_person_id"
    t.string "image_url"
    t.string "phone_number"
    t.string "email"
    t.string "gst_number"
    t.string "pan_number"
    t.string "member_id"
    t.string "shipping_address"
    t.string "preferred_language"
    t.string "delivery_time_preference"
    t.string "notification_method"
    t.string "alt_phone_number"
    t.string "profile_image_url"
    t.string "address_landmark"
    t.string "address_type"
    t.boolean "is_active", default: true
    t.string "password_digest"
    t.string "pincode"
    t.string "landmark"
    t.string "city"
    t.string "postal_code"
    t.string "state"
    t.string "address_line"
    t.string "full_address"
    t.string "country"
    t.integer "customer_type", default: 0
    t.text "interval_days"
    t.integer "regular_quantity"
    t.integer "regular_product_id"
    t.string "regular_delivery_person"
    t.string "regular_delivery_person_from_assignment"
    t.string "monthly_pattern", default: "irregular"
    t.datetime "pattern_updated_at"
    t.integer "invoices_count", default: 0, null: false
    t.decimal "wallet_amount", precision: 10, scale: 2, default: "50.0", null: false
    t.datetime "invoice_created_at"
    t.datetime "invoice_sent_at"
    t.index ["alt_phone_number"], name: "index_customers_on_alt_phone_number", where: "(alt_phone_number IS NOT NULL)"
    t.index ["created_at"], name: "idx_customers_created_at"
    t.index ["customer_type"], name: "index_customers_on_customer_type"
    t.index ["delivery_person_id", "is_active"], name: "index_customers_delivery_person_active"
    t.index ["delivery_person_id"], name: "index_customers_on_delivery_person_id"
    t.index ["email"], name: "index_customers_on_email", where: "(email IS NOT NULL)"
    t.index ["is_active"], name: "index_customers_on_is_active"
    t.index ["latitude", "longitude"], name: "index_customers_on_latitude_and_longitude", where: "((latitude IS NOT NULL) AND (longitude IS NOT NULL))"
    t.index ["member_id"], name: "index_customers_on_member_id", unique: true, where: "(member_id IS NOT NULL)"
    t.index ["monthly_pattern"], name: "index_customers_on_monthly_pattern"
    t.index ["name"], name: "index_customers_on_name"
    t.index ["preferred_language"], name: "index_customers_on_preferred_language"
    t.index ["user_id"], name: "index_customers_on_user_id"
  end

  create_table "deliveries", force: :cascade do |t|
    t.integer "delivery_person_id"
    t.bigint "customer_id", null: false
    t.string "status"
    t.date "delivery_date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_deliveries_on_customer_id"
  end

  create_table "delivery_assignments", force: :cascade do |t|
    t.bigint "delivery_schedule_id"
    t.bigint "customer_id", null: false
    t.bigint "user_id"
    t.date "scheduled_date"
    t.string "status"
    t.datetime "completed_at"
    t.bigint "product_id", null: false
    t.float "quantity"
    t.string "unit"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "invoice_generated", default: false
    t.bigint "invoice_id"
    t.integer "delivery_person_id"
    t.text "special_instructions"
    t.decimal "discount_amount", precision: 10, scale: 2, default: "0.0"
    t.decimal "final_amount_after_discount", precision: 10, scale: 2
    t.text "cancellation_reason"
    t.integer "booked_by"
    t.index ["customer_id", "scheduled_date", "product_id"], name: "index_da_on_customer_date_product"
    t.index ["customer_id", "scheduled_date", "status"], name: "index_delivery_assignments_customer_date_status"
    t.index ["customer_id", "scheduled_date"], name: "index_delivery_assignments_on_customer_and_date"
    t.index ["customer_id", "scheduled_date"], name: "index_delivery_assignments_on_customer_id_and_scheduled_date"
    t.index ["customer_id"], name: "index_delivery_assignments_on_customer_id"
    t.index ["delivery_schedule_id"], name: "index_delivery_assignments_on_delivery_schedule_id"
    t.index ["discount_amount"], name: "index_delivery_assignments_on_discount_amount"
    t.index ["final_amount_after_discount"], name: "index_delivery_assignments_on_final_amount_after_discount"
    t.index ["invoice_generated"], name: "index_delivery_assignments_on_invoice_generated"
    t.index ["invoice_id"], name: "index_delivery_assignments_on_invoice_id"
    t.index ["product_id", "scheduled_date", "quantity"], name: "index_delivery_assignments_product_date_quantity"
    t.index ["product_id", "scheduled_date", "status"], name: "index_delivery_assignments_composite"
    t.index ["product_id", "status", "completed_at"], name: "idx_delivery_product_status_completed"
    t.index ["product_id", "status", "scheduled_date"], name: "idx_delivery_product_status_date"
    t.index ["product_id"], name: "index_delivery_assignments_on_product_id"
    t.index ["scheduled_date", "customer_id"], name: "index_delivery_assignments_on_date_and_customer"
    t.index ["scheduled_date", "final_amount_after_discount", "quantity"], name: "idx_delivery_assignments_date_revenue_qty"
    t.index ["scheduled_date", "final_amount_after_discount"], name: "index_delivery_assignments_date_revenue"
    t.index ["scheduled_date", "product_id", "quantity"], name: "idx_delivery_assignments_completed_date_product", where: "((status)::text = 'completed'::text)"
    t.index ["scheduled_date", "product_id"], name: "index_delivery_assignments_completed", where: "((status)::text = 'completed'::text)"
    t.index ["scheduled_date", "quantity", "final_amount_after_discount"], name: "idx_delivery_assignments_date_qty_amount"
    t.index ["scheduled_date", "quantity", "final_amount_after_discount"], name: "index_delivery_assignments_date_qty_revenue"
    t.index ["scheduled_date", "status", "product_id"], name: "idx_delivery_assignments_date_status_product"
    t.index ["scheduled_date", "status"], name: "index_delivery_assignments_on_date_and_status"
    t.index ["status", "completed_at", "product_id"], name: "idx_delivery_status_completed_product"
    t.index ["status", "completed_at"], name: "idx_delivery_status_completed_at"
    t.index ["status", "scheduled_date"], name: "idx_delivery_status_scheduled_date"
    t.index ["user_id"], name: "index_delivery_assignments_on_user_id"
  end

  create_table "delivery_items", force: :cascade do |t|
    t.bigint "delivery_id", null: false
    t.bigint "product_id", null: false
    t.decimal "quantity"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["delivery_id"], name: "index_delivery_items_on_delivery_id"
    t.index ["product_id"], name: "index_delivery_items_on_product_id"
  end

  create_table "delivery_schedules", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.bigint "user_id", null: false
    t.string "frequency"
    t.date "start_date"
    t.date "end_date"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "default_quantity", precision: 8, scale: 2, default: "1.0"
    t.string "default_unit", default: "pieces"
    t.bigint "product_id"
    t.integer "delivery_person_id"
    t.decimal "default_discount_amount", precision: 10, scale: 2, default: "0.0"
    t.boolean "cod", default: false
    t.integer "booked_by"
    t.index ["customer_id"], name: "index_delivery_schedules_on_customer_id"
    t.index ["default_discount_amount"], name: "index_delivery_schedules_on_default_discount_amount"
    t.index ["delivery_person_id"], name: "index_delivery_schedules_on_delivery_person_id"
    t.index ["product_id"], name: "index_delivery_schedules_on_product_id"
    t.index ["user_id"], name: "index_delivery_schedules_on_user_id"
  end

  create_table "faqs", force: :cascade do |t|
    t.string "category"
    t.text "question", null: false
    t.text "answer", null: false
    t.string "locale", default: "en", null: false
    t.boolean "is_active", default: true, null: false
    t.integer "sort_order", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "customer_id", null: false
    t.boolean "submitted_by_user"
    t.integer "status"
    t.text "admin_response"
    t.index ["category", "locale"], name: "index_faqs_on_category_and_locale"
    t.index ["customer_id"], name: "index_faqs_on_customer_id"
    t.index ["is_active"], name: "index_faqs_on_is_active"
    t.index ["locale"], name: "index_faqs_on_locale"
    t.index ["sort_order"], name: "index_faqs_on_sort_order"
  end

  create_table "franchise_bookings", force: :cascade do |t|
    t.bigint "franchise_id", null: false
    t.bigint "product_id", null: false
    t.decimal "quantity"
    t.decimal "price"
    t.string "status"
    t.date "booking_date"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["franchise_id"], name: "index_franchise_bookings_on_franchise_id"
    t.index ["product_id"], name: "index_franchise_bookings_on_product_id"
  end

  create_table "franchises", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.string "phone", null: false
    t.string "password_digest", null: false
    t.string "location", null: false
    t.string "gst_number"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_franchises_on_active"
    t.index ["email"], name: "index_franchises_on_email", unique: true
  end

  create_table "invoice_items", force: :cascade do |t|
    t.bigint "invoice_id", null: false
    t.bigint "product_id"
    t.decimal "quantity"
    t.decimal "unit_price"
    t.decimal "total_price"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "description"
    t.index ["invoice_id"], name: "index_invoice_items_on_invoice_id"
    t.index ["product_id"], name: "index_invoice_items_on_product_id"
  end

  create_table "invoices", force: :cascade do |t|
    t.bigint "customer_id"
    t.float "total_amount"
    t.string "status"
    t.date "invoice_date"
    t.date "due_date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "invoice_number"
    t.string "invoice_type", default: "manual"
    t.datetime "paid_at"
    t.datetime "last_reminder_sent_at"
    t.text "notes"
    t.string "phone_number"
    t.string "share_token"
    t.datetime "shared_at"
    t.integer "month"
    t.integer "year"
    t.string "quick_customer_name"
    t.string "quick_customer_phone_number"
    t.boolean "is_quick_invoice", default: false
    t.index ["customer_id"], name: "index_invoices_on_customer_id"
    t.index ["due_date"], name: "index_invoices_on_due_date"
    t.index ["invoice_date"], name: "index_invoices_on_invoice_date"
    t.index ["invoice_number"], name: "index_invoices_on_invoice_number", unique: true
    t.index ["invoice_type"], name: "index_invoices_on_invoice_type"
    t.index ["month", "year"], name: "index_invoices_on_month_and_year"
    t.index ["share_token"], name: "index_invoices_on_share_token", unique: true
    t.index ["status"], name: "index_invoices_on_status"
    t.index ["total_amount", "created_at"], name: "index_invoices_on_total_amount_and_created_at"
    t.index ["total_amount"], name: "index_invoices_on_total_amount"
    t.index ["year"], name: "index_invoices_on_year"
  end

  create_table "payouts", force: :cascade do |t|
    t.string "name"
    t.string "gst"
    t.decimal "amount"
    t.string "transaction_id"
    t.string "paid_via"
    t.date "date"
    t.text "description"
    t.string "type"
    t.string "payin_payout"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "payout_type"
  end

  create_table "procurement_assignments", force: :cascade do |t|
    t.bigint "procurement_schedule_id"
    t.bigint "customer_id"
    t.bigint "user_id"
    t.date "scheduled_date"
    t.string "status"
    t.datetime "completed_at", precision: nil
    t.bigint "product_id"
    t.decimal "quantity"
    t.string "unit"
    t.text "notes"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["customer_id"], name: "index_procurement_assignments_on_customer_id"
    t.index ["procurement_schedule_id"], name: "index_procurement_assignments_on_procurement_schedule_id"
    t.index ["product_id"], name: "index_procurement_assignments_on_product_id"
    t.index ["scheduled_date"], name: "index_procurement_assignments_on_scheduled_date"
  end

  create_table "procurement_schedules", force: :cascade do |t|
    t.string "vendor_name"
    t.date "from_date"
    t.date "to_date"
    t.decimal "quantity"
    t.decimal "buying_price"
    t.decimal "selling_price"
    t.string "status"
    t.string "unit"
    t.text "notes"
    t.bigint "user_id"
    t.bigint "product_id"
    t.string "whatsapp_phone_number"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["product_id"], name: "index_procurement_schedules_on_product_id"
    t.index ["user_id"], name: "index_procurement_schedules_on_user_id"
  end

  create_table "products", force: :cascade do |t|
    t.string "name", null: false
    t.decimal "price"
    t.string "unit"
    t.text "description"
    t.bigint "category_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "hsn_sac"
    t.decimal "cgst"
    t.decimal "sgst"
    t.decimal "igst"
    t.decimal "gst_rate"
    t.decimal "price_without_discount"
    t.decimal "discount"
    t.string "unit_type"
    t.string "image_url"
    t.decimal "available_quantity", default: "0.0"
    t.boolean "is_active", default: true, null: false
    t.boolean "is_subscription_eligible", default: false, null: false
    t.index ["category_id"], name: "index_products_on_category_id"
  end

  create_table "referral_codes", force: :cascade do |t|
    t.string "code"
    t.bigint "user_id"
    t.bigint "customer_id"
    t.integer "uses_count", default: 0
    t.integer "max_uses"
    t.datetime "expires_at", precision: nil
    t.boolean "is_active", default: true
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "total_referrals", default: 0
    t.decimal "reward_amount", default: "0.0"
    t.string "status"
    t.text "description"
    t.decimal "total_credits", default: "0.0"
    t.string "share_url_slug"
    t.index ["share_url_slug"], name: "index_referral_codes_on_share_url_slug", unique: true
  end

  create_table "referrals", force: :cascade do |t|
    t.bigint "affiliate_id", null: false
    t.string "customer_name"
    t.string "customer_phone"
    t.string "customer_email"
    t.string "status"
    t.decimal "reward_amount"
    t.text "notes"
    t.datetime "referred_at"
    t.datetime "approved_at"
    t.datetime "rejected_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["affiliate_id"], name: "index_referrals_on_affiliate_id"
  end

  create_table "refresh_tokens", force: :cascade do |t|
    t.string "token"
    t.bigint "user_id"
    t.datetime "expires_at", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.datetime "revoked_at", precision: nil
    t.string "device_info"
    t.string "ip_address"
    t.string "token_hash"
    t.bigint "customer_id"
    t.string "user_agent"
    t.string "created_by_ip"
    t.string "replaced_by_token_hash"
    t.index ["expires_at"], name: "index_refresh_tokens_on_expires_at"
    t.index ["token"], name: "index_refresh_tokens_on_token"
    t.index ["user_id"], name: "index_refresh_tokens_on_user_id"
  end

  create_table "reports", force: :cascade do |t|
    t.string "name", null: false
    t.string "report_type", null: false
    t.date "from_date", null: false
    t.date "to_date", null: false
    t.bigint "user_id", null: false
    t.text "content"
    t.string "file_path"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
  end

  create_table "support_tickets", force: :cascade do |t|
    t.string "subject"
    t.text "description"
    t.string "status"
    t.string "priority"
    t.bigint "user_id"
    t.bigint "customer_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "users", force: :cascade do |t|
    t.string "name"
    t.string "email"
    t.string "phone"
    t.string "password_digest"
    t.integer "role"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "employee_id"
  end

  add_foreign_key "referrals", "affiliates"
end
