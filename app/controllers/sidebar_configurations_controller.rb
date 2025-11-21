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
      :show_dashboard, :show_orders, :show_customers, :show_products,
      :show_categories, :show_delivery_assignments, :show_invoices,
      :show_sales, :show_milk_analytics, :show_analytics, :show_ai_insights,
      :show_procurement, :show_inventory, :show_franchise, :show_affiliates,
      :show_payouts, :show_reports, :show_notifications, :show_users,
      :show_settings_advanced
    )
  end

  def require_admin
    unless current_user&.admin?
      redirect_to root_path, alert: 'Access denied. Admin privileges required.'
    end
  end
end