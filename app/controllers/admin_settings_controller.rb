class AdminSettingsController < ApplicationController
  before_action :require_login
  before_action :set_admin_setting, only: [:show, :edit, :update, :destroy]

  def index
    @admin_setting = AdminSetting.first || AdminSetting.new
    redirect_to admin_setting_path(@admin_setting) if @admin_setting.persisted?
  end

  def show
    generate_qr_code if @admin_setting.upi_id.present?
  end

  def new
    @admin_setting = AdminSetting.new
    set_default_values
  end

  def create
    @admin_setting = AdminSetting.new(admin_setting_params)
    
    if @admin_setting.save
      generate_qr_code if @admin_setting.upi_id.present?
      redirect_to admin_setting_path(@admin_setting), notice: 'Admin settings were successfully created.'
    else
      render :new
    end
  end

  def edit
    # Set default brand name if empty
    if @admin_setting.business_name.blank?
      @admin_setting.business_name = current_user&.name || "Shri Krishna Goshala"
    end
  end

  def update
    if @admin_setting.update(admin_setting_params)
      generate_qr_code if @admin_setting.upi_id.present?
      redirect_to admin_setting_path(@admin_setting), notice: 'Admin settings were successfully updated.'
    else
      render :edit
    end
  end

  def destroy
    @admin_setting.destroy
    redirect_to admin_settings_path, notice: 'Admin settings were successfully deleted.'
  end

  def cleanup_tokens
    count = RefreshToken.expired.destroy_all.size
    render json: { success: true, count: count }
  rescue => e
    render json: { success: false, error: e.message }
  end

  def export_data
    respond_to do |format|
      format.csv do
        csv_data = generate_system_export_csv
        send_data csv_data, filename: "system_data_#{Date.current}.csv", type: 'text/csv'
      end
      format.json do
        data = {
          admin_settings: @admin_setting.as_json,
          statistics: {
            customers: Customer.count,
            users: User.count,
            refresh_tokens: RefreshToken.count,
            support_tickets: SupportTicket.count,
            cms_pages: CmsPage.count,
            faqs: Faq.count,
            referral_codes: ReferralCode.count
          },
          generated_at: Time.current
        }
        render json: data
      end
    end
  end

  private

  def set_admin_setting
    @admin_setting = AdminSetting.find(params[:id])
  end

  def admin_setting_params
    params.require(:admin_setting).permit(:business_name, :address, :mobile, :email, :gstin, :pan_number,
                                          :account_holder_name, :bank_name, :account_number, :ifsc_code,
                                          :upi_id, :terms_and_conditions, :faq, :contact_us, :privacy_policy,
                                          :show_dashboard, :show_orders, :show_customers, :show_products,
                                          :show_categories, :show_delivery_assignments, :show_invoices,
                                          :show_milk_analytics, :show_procurement, :show_payouts,
                                          :show_reports, :show_users, :show_settings)
  end

  def set_default_values
    @admin_setting.business_name = current_user&.name || "Shri Krishna Goshala"
    @admin_setting.account_holder_name = current_user&.name || "Shri Krishna Goshala"
    @admin_setting.bank_name = "Canara Bank"
    @admin_setting.account_number = "3194201000718"
    @admin_setting.ifsc_code = "CNRB0003194"
    @admin_setting.terms_and_conditions = "Kindly make your monthly payment on or before the 10th of every month.\nPlease share the payment screenshot immediately after completing the transaction to confirm your payment."
  end

  def generate_qr_code
    require 'rqrcode'
    
    qr = RQRCode::QRCode.new(@admin_setting.upi_id)
    
    # Generate SVG
    svg = qr.as_svg(
      color: "000",
      shape_rendering: "crispEdges",
      module_size: 6,
      standalone: true
    )
    
    # Save to storage
    qr_code_path = Rails.root.join('public', 'qr_codes')
    FileUtils.mkdir_p(qr_code_path) unless Dir.exist?(qr_code_path)
    
    File.write(Rails.root.join('public', 'qr_codes', "upi_qr_#{@admin_setting.id}.svg"), svg)
    
    @admin_setting.update(qr_code_path: "/qr_codes/upi_qr_#{@admin_setting.id}.svg")
  end

  def generate_system_export_csv
    require 'csv'
    
    CSV.generate(headers: true) do |csv|
      # Admin Settings
      csv << ['Section', 'Field', 'Value']
      csv << ['Admin Settings', 'Business Name', @admin_setting.business_name]
      csv << ['Admin Settings', 'Email', @admin_setting.email]
      csv << ['Admin Settings', 'Mobile', @admin_setting.mobile]
      
      # Statistics
      csv << ['Statistics', 'Total Customers', Customer.count]
      csv << ['Statistics', 'Total Users', User.count]
      csv << ['Statistics', 'Active Tokens', RefreshToken.valid.count]
      csv << ['Statistics', 'Expired Tokens', RefreshToken.expired.count]
      csv << ['Statistics', 'Support Tickets', SupportTicket.count]
      csv << ['Statistics', 'CMS Pages', CmsPage.count]
      csv << ['Statistics', 'FAQ Items', Faq.count]
      csv << ['Statistics', 'Referral Codes', ReferralCode.count]
      csv << ['Statistics', 'Export Generated', Time.current]
    end
  end
end