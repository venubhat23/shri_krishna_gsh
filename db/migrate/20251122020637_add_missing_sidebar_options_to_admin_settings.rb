class AddMissingSidebarOptionsToAdminSettings < ActiveRecord::Migration[8.0]
  def change
    add_column :admin_settings, :show_my_bookings, :boolean
    add_column :admin_settings, :show_customer_patterns, :boolean
    add_column :admin_settings, :show_customer_points, :boolean
    add_column :admin_settings, :show_customer_wallets, :boolean
    add_column :admin_settings, :show_customer_details, :boolean
    add_column :admin_settings, :show_advertisements, :boolean
    add_column :admin_settings, :show_schedules, :boolean
    add_column :admin_settings, :show_pending_payments, :boolean
    add_column :admin_settings, :show_delivery_review, :boolean
    add_column :admin_settings, :show_purchase_invoices, :boolean
    add_column :admin_settings, :show_sales_invoices, :boolean
    add_column :admin_settings, :show_whatsapp_messages, :boolean
  end
end
