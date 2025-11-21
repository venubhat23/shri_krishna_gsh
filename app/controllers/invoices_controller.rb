# app/controllers/invoices_controller.rb
class InvoicesController < ApplicationController
  before_action :set_invoice, only: [:show, :edit, :update, :destroy, :mark_as_paid, :mark_as_completed, :convert_to_completed, :share_whatsapp, :send_email, :download_pdf, :delivery_assignments, :recalculate]
  before_action :set_customers, only: [:index, :new, :create, :generate]
  skip_before_action :require_login, only: [:public_view, :public_download_pdf, :serve_pdf]
  
  def index
    # Optimize queries with proper includes to prevent N+1 queries
    @invoices = Invoice.includes(:customer, :invoice_items, :delivery_assignments)
    
    # Apply filters
    @invoices = @invoices.by_customer(params[:customer_id]) if params[:customer_id].present?

    # Default to pending invoices if no status filter is specified
    if params[:status].present?
      @invoices = @invoices.where(status: params[:status])
    else
      @invoices = @invoices.where(status: 'pending')
    end
    
    # Date filter
    if params[:from_date].present? || params[:to_date].present?
      @invoices = @invoices.by_date_range(params[:from_date], params[:to_date])
    end
    
    # Month filter
    if params[:month].present? && params[:year].present?
      @invoices = @invoices.by_month(params[:month], params[:year])
    end
    
    # Search
    @invoices = @invoices.search_by_number_or_customer(params[:search]) if params[:search].present?
    
    @invoices = @invoices.order(created_at: :desc)
    
    # Get invoice statistics
    @stats = Invoice.invoice_stats
    
    # Add pagination - 50 invoices per page
    @total_invoices = @invoices.count
    @invoices = @invoices.page(params[:page]).per(50)
    
    respond_to do |format|
      format.html
      format.json { 
        render json: @invoices.map { |invoice| 
          {
            id: invoice.id,
            invoice_number: invoice.formatted_number,
            customer_name: invoice.customer.name,
            customer_phone: invoice.customer.phone_number,
            invoice_date: invoice.invoice_date.strftime('%d %b %Y'),
            due_date: invoice.due_date.strftime('%d %b %Y'),
            total_amount: invoice.total_amount,
            status: invoice.status,
            invoice_type: invoice.invoice_type&.humanize || 'Manual',
            overdue: invoice.overdue?,
            days_overdue: invoice.days_overdue,
            url: invoice_path(invoice),
            pdf_url: invoice_path(invoice, format: :pdf)
          }
        }
      }
    end
  end
  
  # def show
  #   @invoice_items = @invoice.invoice_items.includes(:product)
  #   @customer = @invoice.customer
  # end

def show
  @invoice_items = @invoice.invoice_items.includes(:product)
  @customer = @invoice.customer

  # Load delivery assignments for the second page delivery report
  @delivery_assignments = @invoice.delivery_assignments.includes(:product).order(:completed_at, :scheduled_date)
  
  respond_to do |format|
    format.html { render 'show_html' }  # Use new HTML template with actions
    format.pdf do
      begin
        render pdf: "invoice_#{@invoice.id}",
               template: 'invoices/show',  # Keep existing template for PDF
               layout: false,
               page_size: 'A4',
               margin: { top: 5, bottom: 5, left: 5, right: 5 },
               encoding: 'UTF-8'
      rescue => e
        Rails.logger.error "PDF generation failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        
        # Fallback to HTML with print-friendly styling
        flash[:alert] = "PDF generation temporarily unavailable. Showing print-friendly version."
        render template: 'invoices/show_print', layout: false, content_type: 'text/html'
      end
    end
  end
end

  
  def new
    @invoice = Invoice.new
    @invoice.invoice_items.build
  end
  
  def create
    @invoice = Invoice.new(invoice_params)

    # Check if this is a quick invoice (no customer_id but has customer_name)
    if params[:invoice][:customer_id].blank? && params[:customer_name].present?
      # This is a quick invoice - don't create customer
      @invoice.is_quick_invoice = true
      @invoice.quick_customer_name = params[:customer_name]
      @invoice.quick_customer_phone_number = params[:customer_phone]
      @invoice.customer_id = nil  # Explicitly set to nil
      Rails.logger.info "Creating quick invoice for: #{params[:customer_name]} (#{params[:customer_phone]})"
    elsif params[:invoice][:customer_id].present?
      # This is a regular invoice with existing customer
      @invoice.is_quick_invoice = false
      Rails.logger.info "Using existing customer ID: #{params[:invoice][:customer_id]}"
    end

    @invoice.invoice_date = @invoice.invoice_date || Date.current
    @invoice.due_date = @invoice.invoice_date + 10.days if @invoice.due_date.blank?
    @invoice.status = 'pending' if @invoice.status.blank?
    @invoice.invoice_type = 'manual' # Mark as manual/quick invoice

    # Generate invoice number if not present
    if @invoice.invoice_number.blank?
      @invoice.invoice_number = Invoice.generate_invoice_number(@invoice.invoice_type || 'manual')
    end

    # Calculate total amount from invoice items
    if @invoice.invoice_items.any?
      @invoice.total_amount = @invoice.invoice_items.sum(&:total_price)
    end

    if @invoice.save
      # Create delivery assignments with completed status for each invoice item
      # For quick invoices, customer_id will be nil
      @invoice.invoice_items.each do |item|
        delivery_assignment = DeliveryAssignment.create!(
          customer_id: @invoice.customer_id,  # Will be nil for quick invoices
          product: item.product,
          scheduled_date: @invoice.invoice_date,
          quantity: item.quantity,
          unit: item.product.unit_type || 'pieces',
          status: 'completed',
          completed_at: @invoice.invoice_date.end_of_day,
          invoice_generated: true,
          invoice_id: @invoice.id,
          booked_by: 0, # Admin
          final_amount_after_discount: item.total_price
        )
        Rails.logger.info "Created delivery assignment: #{delivery_assignment.id} for product #{item.product.name}"
      end

      success_message = @invoice.is_quick_invoice? ?
        "Quick Invoice was successfully created for #{@invoice.quick_customer_name}!" :
        "Invoice was successfully created!"

      redirect_to invoice_path(@invoice), notice: success_message
    else
      # Debug validation errors
      Rails.logger.error "Invoice validation errors: #{@invoice.errors.full_messages}"
      @invoice.invoice_items.each_with_index do |item, index|
        if item.errors.any?
          Rails.logger.error "Invoice item #{index} errors: #{item.errors.full_messages}"
        end
      end

      # Reload data for the form
      @customers = Customer.all.order(:name)
      @products = Product.all.order(:name)

      render :quick
    end
  end
  
  # NEW: Generate monthly invoices for all customers
  def generate_monthly_for_all
    month = params[:month]&.to_i || Date.current.month
    year = params[:year]&.to_i || Date.current.year
    delivery_person_id = params[:delivery_person_id]
    customer_ids = params[:customer_ids]&.reject { |id| id.blank? || id.include?(',') }&.uniq

    begin
      # Get date range for the month
      start_date = Date.new(year, month, 1)
      end_date = start_date.end_of_month

      # Find existing invoices for the month/year
      existing_invoices_query = Invoice.includes(:customer, :delivery_assignments)
                                      .where(invoice_date: start_date..end_date)
                                      .where(invoice_type: 'monthly')

      # Apply customer/delivery person filters to existing invoices
      if customer_ids.present? && !customer_ids.include?('all')
        selected_customer_ids = customer_ids.reject { |id| id == 'all' }
        existing_invoices_query = existing_invoices_query.where(customer_id: selected_customer_ids)
      elsif delivery_person_id.present? && delivery_person_id != 'all'
        existing_invoices_query = existing_invoices_query.joins(:customer)
                                                         .where(customers: { delivery_person_id: delivery_person_id })
      end

      existing_invoices = existing_invoices_query.to_a

      # Check which invoices have all delivery assignments with invoice_generated = true
      invoices_ready_for_whatsapp = existing_invoices.select do |invoice|
        invoice.delivery_assignments.any? &&
        invoice.delivery_assignments.all? { |assignment| assignment.invoice_generated == true }
      end

      # Get customers that need new invoice generation
      customers_needing_generation = []

      if invoices_ready_for_whatsapp.any?
        # If we have existing invoices ready for WhatsApp, collect customers who don't have them
        existing_customer_ids = invoices_ready_for_whatsapp.map(&:customer_id)

        if customer_ids.present? && !customer_ids.include?('all')
          selected_customer_ids = customer_ids.reject { |id| id == 'all' }
          customers_needing_generation = selected_customer_ids - existing_customer_ids
        elsif delivery_person_id.present? && delivery_person_id != 'all'
          delivery_person_customer_ids = Customer.where(delivery_person_id: delivery_person_id).pluck(:id)
          customers_needing_generation = delivery_person_customer_ids - existing_customer_ids
        else
          # For "all customers", we still need to generate for those without invoices
          all_customer_ids = Customer.pluck(:id)
          customers_needing_generation = all_customer_ids - existing_customer_ids
        end
      else
        # No existing invoices ready, generate for all requested customers
        if customer_ids.present? && !customer_ids.include?('all')
          customers_needing_generation = customer_ids.reject { |id| id == 'all' }
        elsif delivery_person_id.present? && delivery_person_id != 'all'
          customers_needing_generation = Customer.where(delivery_person_id: delivery_person_id).pluck(:id)
        else
          customers_needing_generation = Customer.pluck(:id)
        end
      end

      success_count = 0
      failure_count = 0
      errors = []
      successful_invoices = invoices_ready_for_whatsapp.dup

      # Generate new invoices only for customers that need them
      if customers_needing_generation.any?
        results = Invoice.generate_monthly_invoices_for_selected_customers(customers_needing_generation, month, year)

        results.each do |result|
          if result[:result][:success]
            success_count += 1
            successful_invoices << result[:result][:invoice]
          else
            failure_count += 1
            errors << "#{result[:customer].name}: #{result[:result][:message]}"
          end
        end
      end

      # Add count of existing invoices to success count
      existing_invoice_count = invoices_ready_for_whatsapp.length
      total_success_count = success_count + existing_invoice_count
      
      # Send WhatsApp notifications in bulk using Twilio
      whatsapp_results = { success_count: 0, failure_count: 0 }
      if successful_invoices.any?
        begin
          twilio_service = TwilioWhatsappService.new
          whatsapp_results = twilio_service.send_bulk_invoice_notifications(successful_invoices)
        rescue => e
          Rails.logger.error "Bulk WhatsApp sending failed: #{e.message}"
          whatsapp_results[:failure_count] = successful_invoices.count
        end
      end
      
      whatsapp_success_count = whatsapp_results[:success_count]
      whatsapp_failure_count = whatsapp_results[:failure_count]
      
      # Build comprehensive status message
      message_parts = []

      if existing_invoice_count > 0
        message_parts << "📋 Found #{existing_invoice_count} existing invoices"
      end

      if success_count > 0
        message_parts << "✅ Generated #{success_count} new invoices"
      end

      if total_success_count > 0
        message_parts << "📱 WhatsApp sent: #{whatsapp_success_count} successful"

        if whatsapp_failure_count > 0
          message_parts << "⚠️ WhatsApp failed: #{whatsapp_failure_count} (customers may not have valid WhatsApp numbers)"
        end
      end

      if failure_count > 0
        message_parts << "❌ #{failure_count} invoices could not be generated: #{errors.join(', ')}"
      end

      if total_success_count == 0 && failure_count == 0
        message_parts << "ℹ️ No customers with completed deliveries found for #{Date::MONTHNAMES[month]} #{year}"
      end
      
      # Display appropriate flash message
      if total_success_count > 0 && failure_count == 0 && whatsapp_failure_count == 0
        flash[:notice] = message_parts.join(" | ")
      elsif total_success_count > 0
        flash[:warning] = message_parts.join(" | ")
      else
        flash[:alert] = message_parts.join(" | ")
      end
      
    rescue => e
      Rails.logger.error "Error generating monthly invoices: #{e.message}"
      flash[:alert] = "Error occurred while generating invoices: #{e.message}"
    end
    
    # Always redirect back to invoices index
    redirect_to invoices_path
  end

  def edit
  end
  
  def update
    if @invoice.update(invoice_params)
      redirect_to @invoice, notice: 'Invoice was successfully updated.'
    else
      render :edit
    end
  end
  
  def destroy
    begin
      # Store invoice details before deletion for response
      invoice_number = @invoice.formatted_number || @invoice.invoice_number
      customer_name = @invoice.customer&.name || 'Unknown Customer'

      # Delete all related records properly
      ActiveRecord::Base.transaction do
        # Delete invoice items first
        @invoice.invoice_items.destroy_all

        # Update delivery assignments to remove invoice reference
        @invoice.delivery_assignments.update_all(invoice_id: nil)

        # Delete the invoice
        @invoice.destroy!
      end

      respond_to do |format|
        format.html {
          redirect_to invoices_url, notice: "Invoice #{invoice_number} was successfully deleted."
        }
        format.json {
          render json: {
            success: true,
            message: "✅ Invoice #{invoice_number} has been successfully deleted!",
            invoice_number: invoice_number,
            customer_name: customer_name
          }
        }
      end

    rescue => e
      Rails.logger.error "Error deleting invoice: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      respond_to do |format|
        format.html {
          redirect_to invoices_url, alert: "Error deleting invoice: #{e.message}"
        }
        format.json {
          render json: {
            success: false,
            message: "❌ Error deleting invoice: #{e.message}"
          }, status: :unprocessable_entity
        }
      end
    end
  end
  
  # Quick Invoice page - simple form to create invoices
  def quick
    @customers = Customer.all.order(:name)
    @products = Product.all.order(:name)
  end

  # Existing action for generating single customer invoice
  def generate
    if request.post?
      customer_id = params[:customer_id]
      month = params[:month].to_i
      year = params[:year].to_i
      
      if customer_id.present? && month > 0 && year > 0
        result = Invoice.generate_invoice_for_customer_month(customer_id, month, year)
        
        if result[:success]
          # Send WhatsApp message for single invoice
          begin
            send_whatsapp_invoice(result[:invoice])
            redirect_to result[:invoice], notice: "#{result[:message]} WhatsApp notification sent successfully."
          rescue => e
            Rails.logger.error "WhatsApp sending failed: #{e.message}"
            redirect_to result[:invoice], notice: "#{result[:message]} (WhatsApp notification failed)"
          end
        else
          flash[:alert] = result[:message]
          redirect_to generate_invoices_path
        end
      else
        flash[:alert] = "Please select customer, month and year"
        redirect_to generate_invoices_path
      end
    else
      # Show the generation form
      @current_month = Date.current.month
      @current_year = Date.current.year
      @months = (1..12).map { |m| [Date::MONTHNAMES[m], m] }
      @years = (2020..Date.current.year + 1).to_a.reverse
      
      # Get preview data if customer and month are selected
      if params[:customer_id].present? && params[:month].present? && params[:year].present?
        @preview_data = DeliveryAssignment.monthly_summary_for_customer(
          params[:customer_id].to_i, 
          params[:month].to_i, 
          params[:year].to_i
        )
      end
    end
  end
  
  # AJAX action for getting monthly preview
  def monthly_preview
    customer_id = params[:customer_id].to_i
    month = params[:month].to_i
    year = params[:year].to_i
    if customer_id > 0 && month > 0 && year > 0
      @preview_data = DeliveryAssignment.monthly_summary_for_customer(customer_id, month, year)
      render partial: 'monthly_preview', locals: { preview_data: @preview_data }
    else
      render json: { error: 'Invalid parameters' }, status: 400
    end
  end
  
  # AJAX action for search suggestions
  def search_suggestions
    query = params[:q].to_s.strip
    page = (params[:page] || 1).to_i
    per_page = 15
    offset = (page - 1) * per_page
    
    if query.present? && query.length >= 1
      # Get customers matching name or phone/alt_phone starting with/containing digits
      # Prioritize starts-with for names, allow contains for numbers
      customers = Customer.where(
                    "name ILIKE :name_q OR phone_number ILIKE :num_q OR alt_phone_number ILIKE :num_q",
                    name_q: "#{query}%",
                    num_q: "%#{query}%"
                  )
                  .limit(per_page)
                  .offset(offset)
                  .order(:name)
      
      # Get total count for pagination info
      total_customers = Customer.where(
                         "name ILIKE :name_q OR phone_number ILIKE :num_q OR alt_phone_number ILIKE :num_q",
                         name_q: "#{query}%",
                         num_q: "%#{query}%"
                       ).count
      
      # Get invoices matching the query (only on first page)
      invoices = if page == 1
                   Invoice.includes(:customer)
                          .search_by_number_or_customer(query)
                          .limit(5)
                          .order(created_at: :desc)
                 else
                   []
                 end
    else
      # When no query, return all customers (paginated)
      customers = Customer.limit(per_page).offset(offset).order(:name)
      total_customers = Customer.count
      invoices = []
    end
    
    suggestions = []
    
    customers.each do |customer|
      suggestions << {
        type: 'customer',
        label: customer.name,
        value: customer.name,
        phone: customer.phone_number.presence || customer.alt_phone_number,
        id: customer.id
      }
    end
    
    # Only add invoices if there's a search query and it's the first page
    if query.present? && page == 1
      invoices.each do |invoice|
        suggestions << {
          type: 'invoice',
          label: "#{invoice.formatted_number} - #{invoice.customer.name}",
          value: invoice.formatted_number,
          customer_name: invoice.customer.name,
          amount: invoice.total_amount,
          id: invoice.id
        }
      end
    end
    
    has_more = (offset + customers.length) < total_customers
    
    render json: { 
      suggestions: suggestions,
      page: page,
      has_more: has_more,
      total_count: total_customers
    }
  end
  
  def mark_as_paid
    @invoice = Invoice.find(params[:id])
    @invoice.update(status: 'paid', paid_at: Time.current)
    redirect_to invoices_path, notice: 'Invoice marked as paid.'
  end

  def mark_as_completed
    @invoice.mark_as_completed!
    redirect_to invoices_path, notice: 'Invoice marked as completed successfully.'
  rescue => e
    redirect_to invoices_path, alert: "Failed to mark invoice as completed: #{e.message}"
  end
  
  def convert_to_completed
    @invoice.update(status: 'paid', paid_at: Time.current)
    redirect_to invoices_path, notice: 'Invoice converted to completed successfully.'
  end
  
  # Bulk WhatsApp sharing action
  def bulk_share_whatsapp
    invoice_ids = params[:invoice_ids]
    
    if invoice_ids.blank?
      render json: { error: 'No invoices selected' }, status: 400
      return
    end
    
    # Get invoices with valid phone numbers
    invoices = Invoice.includes(:customer)
                     .where(id: invoice_ids)
                     .joins(:customer)
                     .where.not(customers: { phone_number: [nil, ''] })
    
    if invoices.empty?
      render json: { error: 'No valid invoices found with phone numbers' }, status: 400
      return
    end
    
    # Generate WhatsApp URLs for each invoice
    whatsapp_urls = []
    host = Rails.application.config.action_controller.default_url_options[:host] || 'atmanirbharfarmbangalore.com'
    
    invoices.each do |invoice|
      # Ensure share token exists
      invoice.generate_share_token if invoice.share_token.blank?
      invoice.save! if invoice.changed?
      
      # Generate public URL
      protocol = 'https'
      public_url = invoice.public_url(host: host, protocol: protocol).gsub(':3000', '')

      # Generate public PDF URL
      pdf_url = invoice.generate_public_pdf_url

      # Build WhatsApp message
      message = build_whatsapp_message(invoice, public_url, pdf_url)
      
      # Sanitize phone number and add country code if needed
      sanitized_phone = invoice.customer.phone_number.gsub(/\D/, '')
      
      # Add +91 if it doesn't start with country code (assuming Indian numbers)
      unless sanitized_phone.start_with?('91')
        sanitized_phone = "91#{sanitized_phone.sub(/^0/, '')}"
      end
      
      # Create WhatsApp URL - use web.whatsapp.com for better multi-tab support
      whatsapp_url = "https://web.whatsapp.com/send?phone=#{sanitized_phone}&text=#{CGI.escape(message)}"
      
      whatsapp_urls << {
        invoice_id: invoice.id,
        customer_name: invoice.customer.name,
        invoice_number: invoice.formatted_number,
        whatsapp_url: whatsapp_url
      }
      
      # Mark invoice as shared
      invoice.mark_as_shared!
    end
    
    render json: { 
      success: true, 
      whatsapp_urls: whatsapp_urls,
      count: whatsapp_urls.length,
      message: "Generated #{whatsapp_urls.length} WhatsApp links"
    }
  rescue => e
    Rails.logger.error "Bulk WhatsApp sharing error: #{e.message}"
    render json: { error: 'Failed to generate WhatsApp links' }, status: 500
  end

  # WhatsApp sharing action
  def share_whatsapp
    phone_number = params[:phone_number]
    
    # Validate phone number
    if phone_number.blank?
      render json: { error: 'Phone number is required' }, status: 400
      return
    end
    
    # Sanitize phone number - remove non-digits
    sanitized_phone = phone_number.gsub(/\D/, '')
    
    # Validate phone format (10-15 digits)
    unless sanitized_phone.match?(/^\d{10,15}$/)
      render json: { error: 'Invalid phone number format' }, status: 400
      return
    end
    
    # Ensure share token exists
    @invoice.generate_share_token if @invoice.share_token.blank?
    @invoice.save! if @invoice.changed?
    
    # Generate public URL with explicit host and protocol
    host = Rails.application.config.action_controller.default_url_options[:host] || 'atmanirbharfarmbangalore.com'
    protocol = 'https'
    public_url = @invoice.public_url(host: host, protocol: protocol).gsub(':3000', '')
    
    # Generate public PDF URL
    pdf_url = @invoice.generate_public_pdf_url

    # Build WhatsApp message
    message = build_whatsapp_message(@invoice, public_url, pdf_url)
    
    # Create WhatsApp URL - using web.whatsapp.com for direct WhatsApp Web access
    whatsapp_url = "https://web.whatsapp.com/send?phone=#{sanitized_phone}&text=#{CGI.escape(message)}"
    
    # Mark invoice as shared
    @invoice.mark_as_shared!
    
    render json: { 
      success: true, 
      whatsapp_url: whatsapp_url,
      message: 'WhatsApp link generated successfully'
    }
  rescue => e
    Rails.logger.error "WhatsApp sharing error: #{e.message}"
    render json: { error: 'Failed to generate WhatsApp link' }, status: 500
  end
  
  # Public invoice view (no authentication required)
  def public_view
    # Load invoice with all needed associations at once
    @invoice = Invoice.includes(:customer, invoice_items: :product, delivery_assignments: [:product, :user, :delivery_person, :customer])
                     .find_by(share_token: params[:token])

    if @invoice.nil?
      render file: "#{Rails.root}/public/404.html", layout: false, status: 404
      return
    end

    # Mark as shared if first view
    @invoice.mark_as_shared! if @invoice.shared_at.nil?

    # Use pre-loaded associations
    @invoice_items = @invoice.invoice_items
    @customer = @invoice.customer

    # Use pre-loaded delivery assignments and sort them
    @delivery_assignments_array = @invoice.delivery_assignments
                                         .sort_by { |a| [a.completed_at || Time.zone.now, a.scheduled_date || Date.current] }

    # Pre-calculate counts to avoid repeated database queries in the view
    @total_assignments_count = @delivery_assignments_array.count
    @completed_assignments_count = @delivery_assignments_array.count { |assignment| assignment.status == 'completed' }
    @success_rate = @total_assignments_count > 0 ? (@completed_assignments_count.to_f / @total_assignments_count * 100).round(1) : 0

    render layout: 'public'
  end
  
  # Public PDF download (no authentication required)
  def public_download_pdf
    @invoice = Invoice.find_by(share_token: params[:token])

    if @invoice.nil?
      Rails.logger.warn "Invoice not found for token: #{params[:token]}"
      render file: "#{Rails.root}/public/404.html", layout: false, status: 404
      return
    end

    Rails.logger.info "Generating PDF for invoice #{@invoice.id} with token #{params[:token]}"

    @invoice_items = @invoice.invoice_items.includes(:product)
    @customer = @invoice.customer

    # Load delivery assignments for the second page delivery report
    @delivery_assignments = @invoice.delivery_assignments.includes(:product, :user, :delivery_person).order(:completed_at, :scheduled_date)
    
    respond_to do |format|
      format.pdf do
        generate_pdf_response
      end
      
      # Handle default format (when no format is specified in URL)
      format.html do
        generate_pdf_response
      end
      
      # Handle any other format by defaulting to PDF
      format.any do
        generate_pdf_response
      end
    end
  end

  def download_pdf
    @invoice = Invoice.find(params[:id])
    @invoice_items = @invoice.invoice_items.includes(:product)
    @customer = @invoice.customer

    # Load delivery assignments for the second page delivery report
    @delivery_assignments = @invoice.delivery_assignments.includes(:product, :user, :delivery_person).order(:completed_at, :scheduled_date)

    respond_to do |format|
      format.pdf do
        generate_pdf_response
      end

      # Handle default format (when no format is specified in URL)
      format.html do
        generate_pdf_response
      end

      # Handle any other format by defaulting to PDF
      format.any do
        generate_pdf_response
      end
    end
  end

  # Generate and send invoice via WhatsApp
  def generate_and_send_whatsapp
    customer_id = params[:customer_id]
    month = params[:month].to_i
    year = params[:year].to_i
    phone_number = params[:phone_number]

    if customer_id.blank? || month <= 0 || year <= 0 || phone_number.blank?
      render json: { success: false, error: 'Missing required parameters' }, status: 400
      return
    end

    # Validate phone number
    sanitized_phone = phone_number.gsub(/\D/, '')
    unless sanitized_phone.match?(/^\d{10,15}$/)
      render json: { success: false, error: 'Invalid phone number format' }, status: 400
      return
    end
    begin
      # Find or create invoice for the customer and month
      customer = Customer.find(customer_id)
      start_date = Date.new(year, month, 1)
      end_date = start_date.end_of_month

      # Check if invoice already exists
      existing_invoice = Invoice.where(
        customer: customer,
        invoice_date: start_date..end_date+10.days
      ).first

      if existing_invoice
        invoice = existing_invoice
      else
        # Generate new invoice using the selected customers method for single customer
        results = Invoice.generate_monthly_invoices_for_selected_customers([customer_id], month, year)

        if results.any? && results.first[:result][:success]
          invoice = results.first[:result][:invoice]
        else
          error_message = results.any? ? results.first[:result][:message] : "Failed to generate invoice"
          render json: { success: false, error: error_message }, status: 422
          return
        end
      end

      # Ensure share token exists
      invoice.generate_share_token if invoice.share_token.blank?
      invoice.save! if invoice.changed?

      # Generate public URL for invoice view
      host = Rails.application.config.action_controller.default_url_options[:host] || 'atmanirbharfarmbangalore.com'
      protocol = 'https'
      public_url = invoice.public_url(host: host, protocol: protocol).gsub(':3000', '')

      # Generate public PDF URL
      pdf_url = invoice.generate_public_pdf_url

      # Build WhatsApp message with PDF URL
      message = build_enhanced_invoice_message(invoice, public_url, pdf_url)

      # Add country code if needed
      unless sanitized_phone.start_with?('91')
        sanitized_phone = "91#{sanitized_phone.sub(/^0/, '')}"
      end

      # Create WhatsApp URL
      whatsapp_url = "https://web.whatsapp.com/send?phone=#{sanitized_phone}&text=#{CGI.escape(message)}"

      # Mark invoice as shared
      invoice.mark_as_shared! if invoice.respond_to?(:mark_as_shared!)

      # Update customer phone number if provided
      if phone_number.present? && customer.phone_number != phone_number
        customer.update(phone_number: phone_number)
      end
      # Send via Twilio WhatsApp service
      twilio_success = false
      twilio_error = nil
      begin
        twilio_service = WhatsappInvoiceService.new
        twilio_success = twilio_service.send_invoice_notification(invoice, phone_number: params[:phone_number], public_url: public_url)
      rescue => e
        Rails.logger.error "Twilio WhatsApp sending failed: #{e.message}"
        twilio_error = e.message
      end

      response_data = {
        success: true,
        invoice_id: invoice.id,
        invoice_number: invoice.formatted_number,
        twilio_sent: twilio_success
      }

      if twilio_success
        response_data[:message] = 'Invoice generated and sent via WhatsApp successfully'
      else
        response_data[:message] = 'Invoice generated but WhatsApp sending failed'
        response_data[:whatsapp_url] = whatsapp_url
        response_data[:twilio_error] = twilio_error if twilio_error
      end

      render json: response_data

    rescue => e
      Rails.logger.error "Error generating invoice and WhatsApp: #{e.message}"
      render json: { success: false, error: 'An error occurred while processing your request' }, status: 500
    end
  end

  # Serve PDF files for WhatsApp (public access)
  def serve_pdf
    filename = params[:filename]
    pdf_path = Rails.root.join('public', 'invoices', 'pdf', filename)

    unless File.exist?(pdf_path)
      Rails.logger.warn "PDF file not found: #{filename}"
      render file: "#{Rails.root}/public/404.html", layout: false, status: 404
      return
    end

    # Security check - only allow PDF files
    unless filename.end_with?('.pdf') && filename.match?(/\Ainvoice_\d+_\d+\.pdf\z/)
      Rails.logger.warn "Invalid PDF filename format: #{filename}"
      render file: "#{Rails.root}/public/404.html", layout: false, status: 404
      return
    end

    # Set security headers
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['Content-Security-Policy'] = "default-src 'none'; object-src 'none';"

    # Send file with proper content type
    send_file(
      pdf_path,
      type: 'application/pdf',
      disposition: 'inline',
      filename: filename
    )
  end

  # Send invoice via email
  def send_email
    email = params[:email]

    # Validate email
    if email.blank?
      render json: { error: 'Email address is required' }, status: 400
      return
    end

    # Validate email format
    unless email.match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
      render json: { error: 'Invalid email format' }, status: 400
      return
    end

    begin
      # Send email with PDF attachment
      InvoiceMailer.send_invoice_pdf(@invoice, email).deliver_now

      render json: {
        success: true,
        message: 'Invoice sent via email successfully'
      }
    rescue => e
      Rails.logger.error "Email sending error: #{e.message}"
      render json: { error: 'Failed to send email' }, status: 500
    end
  end

  def delivery_assignments
    delivery_assignments = @invoice.delivery_assignments.includes(:product, :delivery_person).order(:scheduled_date)

    delivery_data = delivery_assignments.map do |assignment|
      {
        id: assignment.id,
        scheduled_date: assignment.scheduled_date,
        product_name: assignment.product&.name || 'Unknown Product',
        quantity: assignment.quantity,
        unit: assignment.unit,
        status: assignment.status,
        delivery_person_name: assignment.delivery_person&.name,
        final_amount_after_discount: assignment.final_amount_after_discount,
        special_instructions: assignment.special_instructions
      }
    end

    render json: {
      success: true,
      delivery_assignments: delivery_data
    }
  rescue => e
    Rails.logger.error "Error fetching delivery assignments: #{e.message}"
    render json: {
      success: false,
      error: 'Failed to fetch delivery assignments'
    }, status: 500
  end

  def recalculate
    # Recalculate invoice based on current delivery assignments
    delivery_assignments = @invoice.delivery_assignments.includes(:product)

    # Clear existing invoice items
    @invoice.invoice_items.destroy_all

    # Group delivery assignments by product and sum quantities and amounts
    grouped_assignments = delivery_assignments.group_by(&:product_id)

    total_amount = 0

    grouped_assignments.each do |product_id, assignments|
      product = assignments.first.product
      next unless product

      total_quantity = assignments.sum(&:quantity)
      total_product_amount = assignments.sum { |a| a.final_amount_after_discount || 0 }

      # Create new invoice item
      @invoice.invoice_items.create!(
        product: product,
        quantity: total_quantity,
        unit_price: total_product_amount / total_quantity,
        total_price: total_product_amount
      )

      total_amount += total_product_amount
    end

    # Update invoice total
    @invoice.update!(total_amount: total_amount)

    render json: {
      success: true,
      message: 'Invoice recalculated successfully!',
      total_amount: total_amount
    }
  rescue => e
    Rails.logger.error "Error recalculating invoice: #{e.message}"
    render json: {
      success: false,
      error: 'Failed to recalculate invoice'
    }, status: 500
  end

  # Get products for dropdown
  def get_products
    products = Product.active.order(:name).select(:id, :name, :price, :unit_type)

    render json: {
      success: true,
      products: products.map do |product|
        {
          id: product.id,
          name: product.name,
          price: product.price,
          unit_type: product.unit_type
        }
      end
    }
  end

  # Create sidebar invoice with delivery assignment
  def create_sidebar_invoice
    begin
      # Handle customer - either existing by ID or create quick invoice
      customer = nil
      is_quick_invoice = false
      quick_customer_name = nil
      quick_customer_phone = nil

      if params[:customer_id].present? && params[:customer_id] != ""
        customer = Customer.find(params[:customer_id])
        is_quick_invoice = false
      else
        # This is a quick invoice - don't create customer
        customer_name = params[:customer_name].to_s.strip
        customer_phone = params[:customer_phone].to_s.strip

        if customer_name.blank?
          render json: { success: false, error: 'Customer name is required' }, status: 422
          return
        end

        # Set quick invoice details
        is_quick_invoice = true
        quick_customer_name = customer_name
        quick_customer_phone = customer_phone
        customer = nil  # No customer for quick invoices
      end

      # Parse parameters
      delivery_date = Date.parse(params[:delivery_date])
      delivery_person_id = params[:delivery_person_id].presence

      # Handle multiple products
      products_data = params[:products] || []

      if products_data.empty?
        render json: { success: false, error: 'At least one product is required' }, status: 422
        return
      end

      # Create invoice (either regular or quick)
      invoice = Invoice.new(
        customer: customer,
        invoice_date: delivery_date,
        due_date: delivery_date + 10.days,
        status: 'pending',
        invoice_type: 'manual',
        is_quick_invoice: is_quick_invoice,
        quick_customer_name: quick_customer_name,
        quick_customer_phone_number: quick_customer_phone
      )

      total_invoice_amount = 0
      delivery_assignments = []

      # Process each product
      products_data.each do |product_data|
        product = Product.find(product_data[:product_id])
        quantity = product_data[:quantity].to_f
        rate = product_data[:rate].to_f
        discount_amount = product_data[:discount_amount].to_f || 0

        # Create delivery assignment for this product
        assignment_params = {
          customer: customer,  # Will be nil for quick invoices
          product: product,
          scheduled_date: delivery_date,
          quantity: quantity,
          unit: product.unit_type,
          status: 'completed',
          completed_at: delivery_date.end_of_day,
          discount_amount: discount_amount,
          booked_by: 0, # Admin
          invoice_generated: false
        }

        # Only add user_id if delivery person is specified and valid
        if delivery_person_id.present? && delivery_person_id.to_i > 0
          assignment_params[:user_id] = delivery_person_id.to_i
        end

        delivery_assignment = DeliveryAssignment.create!(assignment_params)
        delivery_assignments << delivery_assignment

        # Create invoice item
        product_total = (rate * quantity) - discount_amount
        invoice.invoice_items.build(
          product: product,
          quantity: quantity,
          unit_price: rate,
          total_price: product_total
        )

        total_invoice_amount += product_total
      end

      invoice.total_amount = total_invoice_amount

      # Explicitly generate invoice number to ensure it's not blank
      invoice.send(:generate_invoice_number) if invoice.invoice_number.blank?

      if invoice.save
        # Link all delivery assignments to invoice
        delivery_assignments.each do |assignment|
          assignment.update!(
            invoice_generated: true,
            invoice_id: invoice.id
          )
        end

        render json: {
          success: true,
          message: "Invoice with #{products_data.length} product(s) created successfully!",
          invoice_id: invoice.id,
          invoice_number: invoice.formatted_number,
          delivery_assignment_ids: delivery_assignments.map(&:id),
          total_amount: total_invoice_amount
        }
      else
        # Clean up delivery assignments if invoice creation fails
        delivery_assignments.each(&:destroy)
        render json: {
          success: false,
          error: invoice.errors.full_messages.join(', ')
        }, status: 422
      end

    rescue => e
      Rails.logger.error "Error creating sidebar invoice: #{e.message}"
      render json: {
        success: false,
        error: 'An error occurred while creating the invoice'
      }, status: 500
    end
  end

  def customers_for_month
    month = params[:month].to_i
    year = params[:year].to_i
    show_all = params[:show_all] == 'true'

    if month.zero? || year.zero?
      render json: { success: false, error: 'Invalid month or year' }
      return
    end

    begin
      if show_all
        customers = Customer.includes(:delivery_person, :invoices).order(:name).limit(1000)
      else
        # Only consider month and year columns, not invoice_date
        customer_ids_with_invoices = Invoice.where(
          "month = ? AND year = ?",
          month, year
        ).distinct.pluck(:customer_id).compact

        customers = Customer.includes(:delivery_person)
                           .where.not(id: customer_ids_with_invoices)
                           .order(:name).limit(1000)
      end

      Rails.logger.info "Found #{customers.count} customers for month #{month}/#{year}, show_all: #{show_all}"

      html = render_to_string(
        partial: 'invoices/customers_list',
        formats: [:html],
        locals: {
          customers: customers,
          month: month,
          year: year,
          show_all: show_all,
          container_prefix: show_all ? 'all' : 'uninvoiced'
        }
      )

      Rails.logger.info "Partial rendered successfully, HTML length: #{html.length}"
      render json: { success: true, html: html, count: customers.count }
    rescue => e
      Rails.logger.error "Error loading customers for month: #{e.message}"
      Rails.logger.error "Error backtrace: #{e.backtrace.first(5).join('\n')}"
      render json: { success: false, error: 'Server error' }
    end
  end

  private

  def set_invoice
    @invoice = Invoice.find(params[:id])
  end

  def invoice_params
    params.require(:invoice).permit(
      :customer_id, :status, :invoice_date, :due_date, :invoice_number, :notes,
      :quick_customer_name, :quick_customer_phone_number, :is_quick_invoice,
      invoice_items_attributes: [:id, :product_id, :quantity, :unit_price, :total_price, :_destroy]
    )
  end

  def set_customers
    @customers = Customer.order(:name)
  end

  def build_whatsapp_message(invoice, public_url, pdf_url = nil)
    # Get current month and year or use invoice creation date
    month_year = invoice.invoice_date&.strftime('%B %Y') || invoice.created_at&.strftime('%B %Y') || Date.current.strftime('%B %Y')
    formatted_amount = ActionController::Base.helpers.number_with_delimiter(invoice.total_amount, delimiter: ',')

    # Calculate due date (always 10 days from creation date)
    due_date = (invoice.created_at + 10.days).strftime('%d/%m/%Y')

    message = <<~MESSAGE.strip
      👋 Hello #{invoice.customer.name}!

      🎉 Your #{month_year} Invoice is ready to view! 🧾

      ───────────────────
      📋 Invoice #: #{invoice.formatted_number}
      💵 Total Amount: ₹#{formatted_amount}
      📆 Due Date: #{due_date}
      ───────────────────

      👇 Click below to download your invoice:
      #{public_url}

      Thank you for trusting #{AdminSetting.current.business_name}! 🙏

      🏠 Bangalore
      📞 +91 9972808044 | +91 9008860329
      📱 WhatsApp: +91 9972808044
      📧 atmanirbharfarmbangalore@gmail.com
    MESSAGE

    message
  end

  # Method to send invoice via WhatsApp using WANotifier
  def send_whatsapp_invoice(invoice)
    return false unless invoice&.customer&.phone_number.present?
    
    begin
      # Initialize Twilio WhatsApp service
      twilio_service = TwilioWhatsappService.new

      # Send invoice notification via Twilio WhatsApp
      success = twilio_service.send_invoice_notification(invoice)
      
      if success
        Rails.logger.info "Invoice #{invoice.formatted_number} sent successfully via WANotifier to #{invoice.customer.name}"
      else
        Rails.logger.warn "Failed to send invoice #{invoice.formatted_number} via WANotifier to #{invoice.customer.name}"
      end
      
      success
    rescue => e
      Rails.logger.error "Failed to send invoice WhatsApp to #{invoice.customer.name}: #{e.message}"
      false
    end
  end

  # Export invoices for WhatsApp extension
  def export_for_whatsapp
    # Get invoices that haven't been sent via WhatsApp yet
    invoices = Invoice.includes(:customer)
                     .where(status: ['pending', 'generated'])
                     .where(shared_at: nil)
                     .where.not(customer: { phone_number: [nil, ''] })

    # Apply filters if provided
    if params[:month].present? && params[:year].present?
      invoices = invoices.by_month(params[:month], params[:year])
    end

    if params[:customer_id].present?
      invoices = invoices.where(customer_id: params[:customer_id])
    end

    whatsapp_data = invoices.map do |invoice|
      {
        id: invoice.id,
        customer_name: invoice.customer.name,
        phone_number: invoice.customer.phone_number,
        invoice_number: invoice.formatted_number,
        amount: invoice.total_amount.to_f,
        invoice_date: invoice.invoice_date.strftime('%d %B %Y'),
        due_date: invoice.due_date.strftime('%d %B %Y'),
        public_url: public_invoice_url(invoice.share_token),
        pdf_url: invoice_url(invoice, format: :pdf, host: request.host_with_port, protocol: request.protocol)
      }
    end

    render json: {
      invoices: whatsapp_data,
      total_count: whatsapp_data.length,
      timestamp: Time.current.iso8601,
      message: "#{whatsapp_data.length} invoices ready for WhatsApp delivery"
    }
  end

  # Download customer list as PDF
  def download_customer_list
    begin
      delivery_person_id = params[:delivery_person_id] || 'all'
      @customers = Customer.includes(:delivery_person).order(:name).limit(10)
      @delivery_person = nil

      respond_to do |format|
        format.html do
          render plain: "Customer list test - Found #{@customers.count} customers"
        end
        format.pdf do
          render plain: "PDF download test - Found #{@customers.count} customers", content_type: 'application/pdf'
        end
      end
    rescue => e
      render plain: "Error: #{e.message}", status: 500
    end
  end
  
  # Mark invoice as sent via WhatsApp
  def mark_whatsapp_sent
    @invoice = Invoice.find(params[:id])

    @invoice.update!(
      shared_at: Time.current
    )

    render json: { success: true, message: 'Invoice marked as sent via WhatsApp' }
  rescue ActiveRecord::RecordNotFound
    render json: { success: false, error: 'Invoice not found' }, status: 404
  end


  # Enhanced message for invoice with better formatting
  def build_enhanced_invoice_message(invoice, public_url, pdf_url = nil)
    month_year = invoice.invoice_date.strftime("%B %Y")
    formatted_amount = "₹#{ActionController::Base.helpers.number_with_delimiter(invoice.total_amount)}"
    due_date = (invoice.created_at + 10.days).strftime('%d %B %Y')

    message = <<~MESSAGE.strip
      👋 Hello #{invoice.customer.name}!

      🎉 Your #{month_year} Invoice is ready to view! 🧾

      ───────────────────
      📋 Invoice #: #{invoice.formatted_number}
      💵 Total: #{formatted_amount}
      📆 Due Date: #{due_date}
      ───────────────────

      👇 Click below to view your invoice:
      #{public_url}
    MESSAGE

    if pdf_url.present?
      message += "\n\n📄 Direct PDF Download:\n#{pdf_url}"
    end

    message += <<~FOOTER

      Thank you for trusting #{AdminSetting.current.business_name}! 🙏

      🏠 Bangalore
      📞 +91 9972808044 | +91 9008860329
      📱 WhatsApp: +91 9972808044
      📧 atmanirbharfarmbangalore@gmail.com
    FOOTER

    message
  end

  def generate_pdf_response
    begin
      render pdf: "invoice_#{@invoice.id}",
             template: 'invoices/show',
             layout: false,
             page_size: 'A4',
             margin: { top: 5, bottom: 5, left: 5, right: 5 },
             encoding: 'UTF-8'
    rescue => e
      Rails.logger.error "PDF generation failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      # Fallback: serve HTML with print-friendly styling that users can save as PDF
      respond_to do |format|
        format.pdf do
          render template: 'invoices/pdf_template',
                 layout: false,
                 content_type: 'text/html',
                 headers: {
                   'Content-Disposition' => "inline; filename=\"invoice_#{@invoice.id}.html\""
                 }
        end

        format.html do
          render template: 'invoices/pdf_template',
                 layout: false
        end

        format.any do
          render template: 'invoices/pdf_template',
                 layout: false
        end
      end
    end
  end

end