class SidebarConfigurationsController < ApplicationController
  before_action :require_login
  before_action :require_admin
  before_action :set_admin_setting

  def index
    @sidebar_items = @admin_setting.sidebar_menu_items
    @visible_items = @admin_setting.visible_menu_items
  end

  def update
    if @admin_setting.update(sidebar_params)
      redirect_to sidebar_configurations_path, notice: 'Sidebar configuration updated successfully!'
    else
      @sidebar_items = @admin_setting.sidebar_menu_items
      @visible_items = @admin_setting.visible_menu_items
      render :index
    end
  end

  private

  def set_admin_setting
    @admin_setting = AdminSetting.current
  end

  def sidebar_params
    params.require(:admin_setting).permit(
      :show_dashboard, :show_my_bookings, :show_orders, :show_customers,
      :show_customer_patterns, :show_customer_points, :show_customer_wallets,
      :show_ai_insights, :show_customer_details, :show_products,
      :show_categories, :show_advertisements, :show_users, :show_delivery_assignments,
      :show_milk_analytics, :show_schedules, :show_procurement, :show_invoices,
      :show_franchise, :show_affiliates, :show_pending_payments, :show_payouts,
      :show_delivery_review, :show_purchase_invoices, :show_sales_invoices,
      :show_sales, :show_analytics, :show_reports, :show_whatsapp_messages,
      :show_inventory, :show_notifications, :show_settings_advanced
    )
  end

  def require_admin
    unless current_user&.admin?
      redirect_to root_path, alert: 'Access denied. Admin privileges required.'
    end
  end
end