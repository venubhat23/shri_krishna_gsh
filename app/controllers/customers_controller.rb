# app/controllers/customers_controller.rb
class CustomersController < ApplicationController
  before_action :require_login
  before_action :set_customer, only: [:show, :edit, :update, :destroy]
  
  def index
    # Start with optimized scope - only essential columns
    @customers = Customer.fast_index

    # Filter by delivery person if selected
    if params[:delivery_person_id].present? && params[:delivery_person_id] != 'all'
      @customers = @customers.where(delivery_person_id: params[:delivery_person_id])
      @selected_delivery_person_id = params[:delivery_person_id]
    else
      @selected_delivery_person_id = 'all'
    end

    # Search by term across multiple fields
    if params[:search].present?
      term = params[:search].strip
      # Quick exact match check first
      exact_customer = Customer.fast_index
                              .where(
                                "member_id = :term OR phone_number = :term OR alt_phone_number = :term OR email = :term",
                                term: term
                              ).first
      if exact_customer
        redirect_to exact_customer and return
      end

      # Full text search
      @customers = @customers.where(
        "name ILIKE :q OR address ILIKE :q OR phone_number ILIKE :q OR alt_phone_number ILIKE :q OR email ILIKE :q OR member_id ILIKE :q",
        q: "%#{term}%"
      )
    end

    # Order by name for consistent results
    @customers = @customers.order(:name)

    # Get total count before pagination - use distinct count to avoid SELECT conflicts
    @total_customers = @customers.except(:select).count

    # Apply Kaminari pagination - 25 customers per page
    @customers = @customers.page(params[:page]).per(25)

    # Eager load associations only for the paginated results
    @customers = @customers.includes(:delivery_person)

    # Cache delivery people query - only load what's needed for dropdown
    @delivery_people = Rails.cache.fetch('delivery_people_dropdown', expires_in: 1.hour) do
      User.delivery_people.select(:id, :name).order(:name).to_a
    end
  end

  def search_suggestions
    query = params[:q].to_s.strip

    if query.present?
      # Optimized query with only necessary fields selected
      customers = Customer.with_delivery_person
                         .select(:id, :name, :phone_number, :address, :member_id, :delivery_person_id)
                         .where("name ILIKE ? OR phone_number ILIKE ? OR address ILIKE ? OR member_id ILIKE ?",
                                "%#{query}%", "%#{query}%", "%#{query}%", "%#{query}%")
                         .limit(10)
                         .order(:name)
    else
      customers = []
    end

    render json: {
      customers: customers.map do |customer|
        {
          id: customer.id,
          name: customer.name,
          phone_number: customer.phone_number,
          address: customer.address,
          member_id: customer.member_id,
          delivery_person: customer.delivery_person ? {
            id: customer.delivery_person.id,
            name: customer.delivery_person.name
          } : nil
        }
      end
    }
  end
  
  def show
    # @customer is already set by before_action :set_customer
    # Reload customer with associated data for the customer show page
    @customer = Customer.includes(:user, :delivery_person, :customer_preference).find(params[:id])
  end
  
  def new
    @customer = Customer.new
    # Load dropdown data for optional delivery setup
    @delivery_people = User.delivery_people.order(:name)
    @products = Product.order(:name)
  end
  
  def create
    @customer = Customer.new(customer_params)
    @customer.user = current_user
    
    # Handle empty member_id by setting it to nil to avoid unique constraint violation
    @customer.member_id = nil if @customer.member_id.blank?
    
    @customer.password = "customer@123"
    @customer.password_confirmation = "customer@123"
    
    respond_to do |format|
      if @customer.save
        # Optionally create initial delivery schedule + assignments
        maybe_create_initial_delivery_setup(@customer)
        
        success_message = 'Customer was successfully created.'
        if params[:products].present? && params[:delivery_details].present?
          products_count = params[:products].permit!.to_h.count { |_, p| p[:product_id].present? }
          success_message += " Created delivery schedules for #{products_count} product(s)." if products_count > 0
        end
        
        format.html { redirect_to customer_path(@customer), notice: success_message }
        format.json { render json: { success: true, customer: @customer, message: success_message } }
      else
        # Reload dropdown data on failure
        @delivery_people = User.delivery_people.order(:name)
        @products = Product.order(:name)
        
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: { success: false, errors: @customer.errors.full_messages, message: 'Failed to create customer' } }
      end
    end
  end
  
  def edit
    # Load dropdown data for optional delivery setup used in shared form
    @delivery_people = User.delivery_people.order(:name)
    @products = Product.order(:name)
  end
  
  def update
    # Handle empty member_id by setting it to nil to avoid unique constraint violation
    params_to_update = customer_params
    params_to_update[:member_id] = nil if params_to_update[:member_id].blank?
    
    if @customer.update(params_to_update)
      # Check if we should redirect back to index with filters
      if params[:return_to_index].present?
        redirect_url = customers_path
        if params[:filters].present?
          begin
            filter_params = JSON.parse(params[:filters])
            query_params = []
            query_params << "search=#{CGI.escape(filter_params['search'])}" if filter_params['search'].present?
            query_params << "delivery_person_id=#{CGI.escape(filter_params['delivery_person_id'])}" if filter_params['delivery_person_id'].present? && filter_params['delivery_person_id'] != 'all'
            redirect_url += "?#{query_params.join('&')}" if query_params.any?
          rescue JSON::ParserError
            # If filters can't be parsed, just redirect to index
          end
        end
        redirect_to redirect_url, notice: 'Customer was successfully updated.'
      else
        redirect_to @customer, notice: 'Customer was successfully updated.'
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end
  
  def destroy
    begin
      # Count related records before deletion for feedback
      delivery_assignments_count = @customer.delivery_assignments.count
      delivery_schedules_count = @customer.delivery_schedules.count
      invoices_count = @customer.invoices.count

      # Delete customer and all related data (using dependent: :destroy associations)
      @customer.destroy!

      message = "Customer was successfully deleted along with #{delivery_assignments_count} delivery assignments, #{delivery_schedules_count} delivery schedules, and #{invoices_count} invoices."

      respond_to do |format|
        format.html { redirect_to customers_url, notice: message }
        format.json { render json: { success: true, message: message } }
      end
    rescue ActiveRecord::RecordNotDestroyed => e
      error_message = "Failed to delete customer: #{e.message}"
      respond_to do |format|
        format.html { redirect_to customers_url, alert: error_message }
        format.json { render json: { success: false, message: error_message } }
      end
    rescue => e
      Rails.logger.error "Error deleting customer #{@customer.id}: #{e.message}"
      error_message = "An unexpected error occurred while deleting the customer."
      respond_to do |format|
        format.html { redirect_to customers_url, alert: error_message }
        format.json { render json: { success: false, message: error_message } }
      end
    end
  end
  
  # Bulk import form
  def bulk_import
    @csv_template = Customer.csv_template
  end
  
  # Process bulk import
  def process_bulk_import
    csv_data = params[:csv_data]
    
    if csv_data.blank?
      render json: { 
        success: false, 
        message: "Please paste CSV data" 
      }
      return
    end
    
    result = Customer.import_from_csv(csv_data, current_user)
    
    render json: result
  end
  
  # AJAX validation for CSV
  def validate_csv
    csv_data = params[:csv_data]
    
    if csv_data.blank?
      render json: { valid: false, message: "Please paste CSV data" }
      return
    end
    
    begin
      require 'csv'
      csv = CSV.parse(csv_data.strip, headers: true, header_converters: :symbol)
      
      required_headers = [:name, :phone_number, :address]
      missing_headers = required_headers - csv.headers.compact.map(&:to_sym)
      
      if missing_headers.any?
        render json: { 
          valid: false, 
          message: "Missing required columns: #{missing_headers.join(', ')}" 
        }
      else
        render json: { 
          valid: true, 
          message: "CSV format is valid. Found #{csv.count} rows ready for import.",
          row_count: csv.count,
          headers: csv.headers
        }
      end
    rescue CSV::MalformedCSVError => e
      render json: { valid: false, message: "Invalid CSV format: #{e.message}" }
    rescue => e
      render json: { valid: false, message: "Error validating CSV: #{e.message}" }
    end
  end
  
  # Download CSV template
  def download_template
    template_content = Customer.csv_template
    
    respond_to do |format|
      format.csv do
        send_data template_content,
                  filename: 'customers_template.csv',
                  type: 'text/csv',
                  disposition: 'attachment'
      end
    end
  end
  
  # Enhanced bulk import form
  def enhanced_bulk_import
    @csv_template = Customer.enhanced_csv_template
    @delivery_people = User.delivery_people.order(:name)
    @products = Product.order(:name)
  end
  
  # Process enhanced bulk import
  def process_enhanced_bulk_import
    csv_data = params[:csv_data]
    
    if csv_data.blank?
      render json: { 
        success: false, 
        message: "Please paste CSV data" 
      }
      return
    end
    
    result = Customer.enhanced_bulk_import(csv_data, current_user)
    
    render json: result
  end
  
  # AJAX validation for enhanced CSV
  def validate_enhanced_csv
    csv_data = params[:csv_data]

    if csv_data.blank?
      render json: { valid: false, message: "Please paste CSV data" }
      return
    end

    begin
      require 'csv'
      csv = CSV.parse(csv_data.strip, headers: true, header_converters: :symbol)

      # Check for required headers
      required_headers = [:name, :phone_number, :address]
      optional_headers = [:email, :gst_number, :pan_number, :member_id, :latitude, :longitude, :delivery_person_id, :product_id, :quantity, :start_date, :end_date]

      # Check if any required headers are missing
      missing_headers = required_headers - csv.headers.compact.map(&:to_sym)

      if missing_headers.any?
        render json: {
          valid: false,
          message: "Missing required columns: #{missing_headers.join(', ')}"
        }
        return
      end

      # Check for common header typos
      header_corrections = {
        quality: 'quantity',
        quanity: 'quantity',
        qty: 'quantity',
        mobile: 'phone_number',
        mobile_number: 'phone_number',
        phone: 'phone_number',
        del_person_id: 'delivery_person_id',
        delivery_id: 'delivery_person_id'
      }

      suggested_corrections = []
      csv.headers.compact.map(&:to_sym).each do |header|
        if header_corrections[header]
          suggested_corrections << "#{header} → #{header_corrections[header]}"
        end
      end

      if suggested_corrections.any?
        render json: {
          valid: false,
          message: "Header name corrections needed: #{suggested_corrections.join(', ')}"
        }
        return
      end

      # Validate data content
      errors = []
      valid_rows = 0

      csv.each_with_index do |row, index|
        row_num = index + 2 # +2 because CSV is 1-indexed and we have headers
        row_errors = []

        # Validate required fields
        if row[:name].blank?
          row_errors << "Name is required"
        end

        if row[:phone_number].blank?
          row_errors << "Phone number is required"
        elsif !valid_phone_number?(row[:phone_number])
          row_errors << "Invalid phone number format (must be 10 digits)"
        end

        if row[:address].blank?
          row_errors << "Address is required"
        end

        # Validate optional fields if present
        if row[:email].present? && !valid_email?(row[:email])
          row_errors << "Invalid email format"
        end

        if row[:delivery_person_id].present? && !User.delivery_people.exists?(id: row[:delivery_person_id])
          row_errors << "Delivery person ID #{row[:delivery_person_id]} not found"
        end

        if row[:product_id].present? && !Product.exists?(id: row[:product_id])
          row_errors << "Product ID #{row[:product_id]} not found"
        end

        if row[:quantity].present? && (row[:quantity].to_f <= 0)
          row_errors << "Quantity must be greater than 0"
        end

        if row[:start_date].present? && !valid_date?(row[:start_date])
          row_errors << "Invalid start date format (use YYYY-MM-DD)"
        end

        if row[:end_date].present? && !valid_date?(row[:end_date])
          row_errors << "Invalid end date format (use YYYY-MM-DD)"
        end

        if row_errors.any?
          errors << "Row #{row_num}: #{row_errors.join(', ')}"
        else
          valid_rows += 1
        end
      end

      if errors.any?
        # Limit error display to first 10 errors
        error_message = "Found #{errors.length} validation errors:\n\n"
        error_message += errors.first(10).join("\n")
        if errors.length > 10
          error_message += "\n\n... and #{errors.length - 10} more errors."
        end

        render json: {
          valid: false,
          message: error_message,
          error_count: errors.length,
          valid_count: valid_rows
        }
      else
        render json: {
          valid: true,
          message: "✓ CSV is valid! Found #{valid_rows} customers ready for enhanced import with delivery assignments.",
          row_count: valid_rows,
          headers: csv.headers
        }
      end

    rescue CSV::MalformedCSVError => e
      render json: { valid: false, message: "Invalid CSV format: #{e.message}" }
    rescue => e
      render json: { valid: false, message: "Error validating CSV: #{e.message}" }
    end
  end

  private

  def valid_phone_number?(phone)
    # Remove any non-digits and check if it's exactly 10 digits
    phone_digits = phone.to_s.gsub(/\D/, '')
    phone_digits.length == 10 && phone_digits.match?(/^[6-9]\d{9}$/)
  end

  def valid_email?(email)
    email.to_s.match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
  end

  def valid_date?(date_str)
    Date.parse(date_str.to_s)
    true
  rescue ArgumentError
    false
  end
  
  # Download enhanced CSV template
  def download_enhanced_template
    template_content = Customer.enhanced_csv_template
    
    respond_to do |format|
      format.csv do
        send_data template_content,
                  filename: 'customers_enhanced_template.csv',
                  type: 'text/csv',
                  disposition: 'attachment'
      end
    end
  end
  
  # Reassign delivery person for a customer
  def reassign_delivery_person
    @customer = Customer.find(params[:id])
    new_delivery_person_id = params[:delivery_person_id]
    
    if new_delivery_person_id.blank?
      render json: { 
        success: false, 
        message: "Please select a delivery person" 
      }, status: :unprocessable_entity
      return
    end
    
    # Validate delivery person exists
    new_delivery_person = User.delivery_people.find_by(id: new_delivery_person_id)
    if new_delivery_person.nil?
      render json: { 
        success: false, 
        message: "Invalid delivery person selected" 
      }, status: :unprocessable_entity
      return
    end
    
    # Calculate tomorrow's date for updating future assignments
    tomorrow = Date.current + 1.day
    
    begin
      ActiveRecord::Base.transaction do
        # Update customer's delivery person
        @customer.update!(delivery_person_id: new_delivery_person_id)
        
        # Update delivery schedules from tomorrow onwards
        updated_schedules = @customer.delivery_schedules
                                   .where('start_date >= ? OR end_date >= ?', tomorrow, tomorrow)
                                   .update_all(user_id: new_delivery_person_id)
        
        # Update delivery assignments from tomorrow onwards
        updated_assignments = @customer.delivery_assignments
                                      .where('scheduled_date >= ?', tomorrow)
                                      .where(status: ['pending', 'scheduled'])
                                      .update_all(user_id: new_delivery_person_id)
        
        render json: { 
          success: true, 
          message: "Successfully updated #{updated_schedules} schedules and #{updated_assignments} assignments",
          customer: {
            id: @customer.id,
            name: @customer.name,
            delivery_person: {
              id: new_delivery_person.id,
              name: new_delivery_person.name
            }
          },
          updates: {
            schedules: updated_schedules,
            assignments: updated_assignments
          }
        }
      end
    rescue ActiveRecord::RecordInvalid => e
      render json: { 
        success: false, 
        message: "Failed to reassign delivery person: #{e.message}" 
      }, status: :unprocessable_entity
    rescue => e
      Rails.logger.error "Error reassigning delivery person: #{e.message}"
      render json: { 
        success: false, 
        message: "An error occurred while reassigning the delivery person" 
      }, status: :internal_server_error
    end
  end
  
  private
  
  def set_customer
    @customer = Customer.find(params[:id])
  end
  
  def customer_params
    params.require(:customer).permit(
      :name, :address, :shipping_address, :latitude, :longitude,
      :user_id, :delivery_person_id, :image_url,
      :phone_number, :email, :gst_number, :pan_number, :member_id
    )
  end

  # Creates delivery schedules and daily delivery assignments for multiple products if provided
  def maybe_create_initial_delivery_setup(customer)
    details = params[:delivery_details] || {}
    products_data = params[:products] || {}
    
    return if details.blank? || products_data.blank?

    begin
      start_date = details[:start_date].presence && Date.parse(details[:start_date])
      end_date   = details[:end_date].presence && Date.parse(details[:end_date])
    rescue ArgumentError
      start_date = nil
      end_date = nil
    end

    # Determine delivery person
    delivery_person_id = details[:delivery_person_id].presence&.to_i
    
    # Return if essential details are missing
    return if start_date.blank? || end_date.blank? || delivery_person_id.blank?

    # Validate delivery person exists
    delivery_person = User.delivery_people.find_by(id: delivery_person_id)
    return if delivery_person.nil?

    # Process each product
    schedules_created = 0
    assignments_created = 0

    ActiveRecord::Base.transaction do
      products_data.each do |index, product_data|
        next if product_data[:product_id].blank? || product_data[:quantity].blank?

        product = Product.find_by(id: product_data[:product_id])
        next if product.nil?

        quantity = product_data[:quantity].to_f
        next if quantity <= 0

        unit = product_data[:unit].presence || product.unit_type
        discount_amount = product_data[:discount_amount].to_f

        # Create delivery schedule for this product
        schedule = DeliverySchedule.create!(
          customer_id: customer.id,
          user_id: delivery_person_id,
          product_id: product.id,
          start_date: start_date,
          end_date: end_date,
          frequency: 'daily',
          status: 'active',
          default_quantity: quantity,
          default_unit: unit,
          default_discount_amount: discount_amount
        )

        schedules_created += 1

        # Generate daily assignments for the date range
        current_date = start_date
        while current_date <= end_date
          assignment = DeliveryAssignment.create!(
            customer_id: customer.id,
            user_id: delivery_person_id,
            product_id: product.id,
            quantity: quantity,
            unit: unit,
            scheduled_date: current_date,
            status: 'pending',
            delivery_schedule_id: schedule.id,
            discount_amount: discount_amount
          )
          
          # Calculate and save final amount
          assignment.calculate_final_amount_after_discount
          
          assignments_created += 1
          current_date += 1.day
        end
      end

      # Ensure the customer is assigned to the delivery person if not already
      if customer.delivery_person_id.blank?
        customer.update!(delivery_person_id: delivery_person_id)
      end
    end

    Rails.logger.info "Created #{schedules_created} schedules and #{assignments_created} assignments for customer #{customer.id}"
    
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Error creating delivery setup for customer #{customer.id}: #{e.message}"
    # Don't fail the customer creation if delivery setup fails
  rescue => e
    Rails.logger.error "Unexpected error creating delivery setup for customer #{customer.id}: #{e.message}"
  end
end