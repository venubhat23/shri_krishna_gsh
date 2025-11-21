class AdminSetting < ApplicationRecord
  validates :business_name, presence: true
  validates :mobile, presence: true
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :account_holder_name, presence: true
  validates :bank_name, presence: true
  validates :account_number, presence: true
  validates :ifsc_code, presence: true
  validates :upi_id, format: { with: /\A[a-zA-Z0-9.\-_]+@[a-zA-Z0-9.\-_]+\z/, message: "must be a valid UPI ID" }, allow_blank: true

  # Singleton pattern to get the current admin settings
  def self.current
    first || new
  end

  # Owner notification settings
  def owner_email
    email
  end

  def owner_mobile
    mobile
  end

  def formatted_terms_and_conditions
    terms_and_conditions.split("\n").map(&:strip).reject(&:empty?)
  end

  # Sidebar visibility methods
  def sidebar_menu_items
    {
      dashboard: { name: 'Dashboard', path: '/', icon: 'fa-tachometer-alt', show: show_dashboard? },
      orders: { name: 'Orders', path: '/orders', icon: 'fa-shopping-cart', show: show_orders? },
      customers: { name: 'Customers', path: '/customers', icon: 'fa-users', show: show_customers? },
      products: { name: 'Products', path: '/products', icon: 'fa-box', show: show_products? },
      categories: { name: 'Categories', path: '/categories', icon: 'fa-tags', show: show_categories? },
      delivery_assignments: { name: 'Deliveries', path: '/delivery_assignments', icon: 'fa-truck', show: show_delivery_assignments? },
      invoices: { name: 'Invoices', path: '/invoices', icon: 'fa-file-invoice', show: show_invoices? },
      sales: { name: 'Sales', path: '/sales', icon: 'fa-chart-line', show: show_sales? },
      milk_analytics: { name: 'Milk Analytics', path: '/milk-supply-analytics', icon: 'fa-cow', show: show_milk_analytics? },
      analytics: { name: 'Analytics', path: '/analytics', icon: 'fa-analytics', show: show_analytics? },
      ai_insights: { name: 'AI Insights', path: '/ai-insights', icon: 'fa-brain', show: show_ai_insights? },
      procurement: { name: 'Procurement', path: '/procurement_schedules', icon: 'fa-industry', show: show_procurement? },
      inventory: { name: 'Inventory', path: '/inventory', icon: 'fa-warehouse', show: show_inventory? },
      franchise: { name: 'Franchise', path: '/franchises', icon: 'fa-store', show: show_franchise? },
      affiliates: { name: 'Affiliates', path: '/admin/affiliates', icon: 'fa-handshake', show: show_affiliates? },
      payouts: { name: 'Payouts', path: '/payouts', icon: 'fa-money-bill-wave', show: show_payouts? },
      reports: { name: 'Reports', path: '/reports', icon: 'fa-chart-bar', show: show_reports? },
      notifications: { name: 'Notifications', path: '/notifications', icon: 'fa-bell', show: show_notifications? },
      users: { name: 'Users', path: '/users', icon: 'fa-user-cog', show: show_users? },
      settings_advanced: { name: 'Advanced Settings', path: '/settings/advanced', icon: 'fa-tools', show: show_settings_advanced? },
      settings: { name: 'Settings', path: '/admin_settings', icon: 'fa-cog', show: show_settings? }
    }
  end

  def visible_menu_items
    sidebar_menu_items.select { |key, item| item[:show] }
  end

  # Sidebar visibility check methods with defaults
  def show_dashboard?
    show_dashboard.nil? ? true : show_dashboard
  end

  def show_orders?
    show_orders.nil? ? true : show_orders
  end

  def show_customers?
    show_customers.nil? ? true : show_customers
  end

  def show_products?
    show_products.nil? ? true : show_products
  end

  def show_categories?
    show_categories.nil? ? true : show_categories
  end

  def show_delivery_assignments?
    show_delivery_assignments.nil? ? true : show_delivery_assignments
  end

  def show_invoices?
    show_invoices.nil? ? true : show_invoices
  end

  def show_milk_analytics?
    show_milk_analytics.nil? ? true : show_milk_analytics
  end

  def show_procurement?
    show_procurement.nil? ? true : show_procurement
  end

  def show_payouts?
    show_payouts.nil? ? true : show_payouts
  end

  def show_reports?
    show_reports.nil? ? true : show_reports
  end

  def show_users?
    show_users.nil? ? true : show_users
  end

  def show_settings?
    show_settings.nil? ? true : show_settings
  end

  def show_sales?
    show_sales.nil? ? true : show_sales
  end

  def show_analytics?
    show_analytics.nil? ? true : show_analytics
  end

  def show_ai_insights?
    show_ai_insights.nil? ? true : show_ai_insights
  end

  def show_inventory?
    show_inventory.nil? ? true : show_inventory
  end

  def show_franchise?
    show_franchise.nil? ? true : show_franchise
  end

  def show_affiliates?
    show_affiliates.nil? ? true : show_affiliates
  end

  def show_notifications?
    show_notifications.nil? ? true : show_notifications
  end

  def show_settings_advanced?
    show_settings_advanced.nil? ? true : show_settings_advanced
  end
end