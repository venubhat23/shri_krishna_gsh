class AddAdditionalSidebarOptionsToAdminSettings < ActiveRecord::Migration[8.0]
  def change
    add_column :admin_settings, :show_ai_insights, :boolean
    add_column :admin_settings, :show_franchise, :boolean
    add_column :admin_settings, :show_affiliates, :boolean
    add_column :admin_settings, :show_sales, :boolean
    add_column :admin_settings, :show_inventory, :boolean
    add_column :admin_settings, :show_analytics, :boolean
    add_column :admin_settings, :show_notifications, :boolean
    add_column :admin_settings, :show_settings_advanced, :boolean
  end
end
