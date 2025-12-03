class Customer < ApplicationRecord
  # Associations
  has_secure_password
  
  # Virtual attribute for password confirmation
  attr_accessor :password_confirmation
  
  # Callbacks
  before_save :normalize_member_id
  
  belongs_to :user
  belongs_to :delivery_person, class_name: 'User', optional: true
  has_many :deliveries, dependent: :destroy
  has_many :delivery_assignments, dependent: :destroy
  has_many :delivery_schedules, dependent: :destroy
  has_many :invoices, dependent: :destroy
  has_many :faqs, dependent: :destroy
  has_many :support_tickets, dependent: :destroy
  has_many :customer_addresses, dependent: :destroy
  has_one :customer_preference, dependent: :destroy
  has_one :referral_code, dependent: :destroy
  has_many :refresh_tokens, dependent: :destroy
  has_many :customer_points, dependent: :destroy

  # Validations
  validates :name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :phone_number, presence: true
  validates :address, presence: true, length: { minimum: 5, maximum: 255 }
  validates :user_id, presence: true
  validates :member_id, uniqueness: { allow_blank: true }, allow_blank: true
  validates :latitude, numericality: { 
    greater_than_or_equal_to: -90, 
    less_than_or_equal_to: 90,
    allow_blank: true,
    message: "must be between -90 and 90 degrees"
  }
  validates :longitude, numericality: { 
    greater_than_or_equal_to: -180, 
    less_than_or_equal_to: 180,
    allow_blank: true,
    message: "must be between -180 and 180 degrees"
  }

  # Custom validation for delivery person assignment
  validate :delivery_person_capacity_check, if: :delivery_person_id_changed?

  # Custom validation to ensure both lat and lng are provided together
  validate :coordinates_presence

  # Optimized Scopes with proper includes to prevent N+1 queries

  # Fast index scope - optimized for customer list
  scope :fast_index, -> {
    select(:id, :name, :address, :phone_number, :email, :member_id,
           :delivery_person_id, :user_id, :is_active, :created_at, :updated_at,
           :image_url, :latitude, :longitude)
    .where(is_active: true)
  }

  # Cache delivery people count to avoid repeated queries
  scope :with_delivery_person_cache, -> {
    includes(:delivery_person)
    .select('customers.*, users.name as delivery_person_name')
    .joins('LEFT JOIN users ON users.id = customers.delivery_person_id')
  }
  scope :assigned, -> { where.not(delivery_person_id: nil) }
  scope :unassigned, -> { where(delivery_person_id: nil) }
  scope :with_coordinates, -> { where.not(latitude: nil, longitude: nil) }
  scope :without_coordinates, -> { where(latitude: nil, longitude: nil) }
  scope :search, ->(term) {
    where(
      "name ILIKE :q OR address ILIKE :q OR phone_number ILIKE :q OR alt_phone_number ILIKE :q OR email ILIKE :q OR member_id ILIKE :q",
      q: "%#{term}%"
    )
  }
  scope :by_user, ->(user) { where(user: user) }
  scope :by_delivery_person, ->(dp) { where(delivery_person: dp) }
  scope :recent, -> { order(created_at: :desc) }
  scope :active, -> { where(is_active: true) }

  # N+1 Prevention Scopes
  scope :with_delivery_person, -> { includes(:delivery_person) }
  scope :with_user, -> { includes(:user) }
  scope :with_full_associations, -> {
    includes(:user, :delivery_person, :delivery_assignments, :delivery_schedules, :invoices, :customer_preference)
  }
  scope :with_basic_associations, -> { includes(:user, :delivery_person) }
  scope :with_delivery_data, -> {
    includes(:delivery_assignments, :delivery_schedules, delivery_assignments: :product)
  }

  # Performance optimized scopes
  scope :with_delivery_counts, -> {
    left_joins(:delivery_assignments)
    .select('customers.*, COUNT(delivery_assignments.id) AS delivery_assignments_count')
    .group('customers.id')
  }

  scope :with_invoice_totals, -> {
    left_joins(:invoices)
    .select('customers.*, COALESCE(SUM(invoices.total_amount), 0) AS total_invoice_amount')
    .group('customers.id')
  }

  # Combined scope to avoid SELECT conflicts when chaining
  scope :with_stats, -> {
    left_joins(:delivery_assignments, :invoices)
    .select('customers.*',
            'COUNT(DISTINCT delivery_assignments.id) AS delivery_assignments_count',
            'COALESCE(SUM(invoices.total_amount), 0) AS total_invoice_amount')
    .group('customers.id')
  }

  # Simplified scope for index pages - just basic associations
  scope :for_index, -> {
    includes(:user, :delivery_person)
  }

  # Optimized scope for paginated index (simple version to avoid SQL conflicts)
  scope :for_paginated_index, -> {
    includes(:user, :delivery_person)
  }

  # Customer type scopes (Legacy - based on customer_type field)
  scope :regular_customers_legacy, -> { where(customer_type: 0) }
  scope :irregular_customers_legacy, -> { where.not(customer_type: [0, 1]) }

  # New customer categorization based on interval_days
  scope :regular_customers, -> { where(interval_days: "7") }
  scope :all_customers_with_intervals, -> { where.not(interval_days: nil) }


  # CSV template for bulk import
  def self.csv_template
    "name,phone_number,address,email,gst_number,pan_number,member_id,latitude,longitude\n" +
    "John Doe,9999999999,123 Main St,john@example.com,GST123,PAN123,MEM123,12.9716,77.5946\n" +
    "Jane Smith,8888888888,456 Oak Ave,jane@example.com,,,,,\n"
  end
  
  # Import customers from CSV data
  def self.import_from_csv(csv_data, current_user)
    require 'csv'
    
    result = {
      success: false,
      imported_count: 0,
      errors: [],
      skipped_rows: [],
      message: ''
    }
    
    begin
      # Parse CSV data
      csv = CSV.parse(csv_data.strip, headers: true, header_converters: :symbol)
      
      if csv.empty?
        result[:message] = "CSV file is empty"
        return result
      end
      
      # Validate required headers
      required_headers = [:name, :phone_number, :address]
      missing_headers = required_headers - csv.headers.compact.map(&:to_sym)
      
      if missing_headers.any?
        result[:message] = "Missing required columns: #{missing_headers.join(', ')}"
        return result
      end
      
      imported_count = 0
      csv.each_with_index do |row, index|
        row_number = index + 2 # +2 because index starts at 0 and we have headers
        
        # Skip empty rows
        if row[:name].blank? && row[:phone_number].blank? && row[:address].blank?
          result[:skipped_rows] << "Row #{row_number}: Empty row"
          next
        end
        
        # Validate required fields
        if row[:name].blank?
          result[:errors] << "Row #{row_number}: Name is required"
          next
        end
        
        if row[:phone_number].blank?
          result[:errors] << "Row #{row_number}: Phone number is required"
          next
        end
        
        if row[:address].blank?
          result[:errors] << "Row #{row_number}: Address is required"
          next
        end
        
        # Check if customer already exists
        existing_customer = Customer.find_by(
          name: row[:name].to_s.strip,
          phone_number: row[:phone_number].to_s.strip
        )
        
        if existing_customer
          result[:errors] << "Row #{row_number}: Customer '#{row[:name]}' with phone '#{row[:phone_number]}' already exists"
          next
        end
        
        # Create customer
        customer = Customer.new(
          name: row[:name].to_s.strip,
          phone_number: row[:phone_number].to_s.strip,
          address: row[:address].to_s.strip,
          email: row[:email].to_s.strip.presence,
          gst_number: row[:gst_number].to_s.strip.presence,
          pan_number: row[:pan_number].to_s.strip.presence,
          member_id: row[:member_id].to_s.strip.presence,
          user: current_user
        )
        
        # Set default password as specified by user
        customer.password = "customer@123"
        customer.password_confirmation = "customer@123"
        
        # Handle coordinates if provided
        if row[:latitude].present? && row[:longitude].present?
          customer.latitude = row[:latitude].to_f
          customer.longitude = row[:longitude].to_f
        end
        
        if customer.save
          imported_count += 1
        else
          error_messages = customer.errors.full_messages.join(', ')
          result[:errors] << "Row #{row_number}: #{error_messages}"
        end
      end
      
      result[:success] = true
      result[:imported_count] = imported_count
      result[:message] = "Import completed successfully"
      
    rescue CSV::MalformedCSVError => e
      result[:message] = "Invalid CSV format: #{e.message}"
    rescue => e
      result[:message] = "Error processing CSV: #{e.message}"
    end
    
    result
  end
  
  # Enhanced bulk import with delivery assignments and schedules
  def self.enhanced_bulk_import(csv_data, current_user)
    require 'csv'
    
    result = {
      success: false,
      imported_count: 0,
      errors: [],
      skipped_rows: [],
      message: '',
      delivery_assignments_created: 0,
      delivery_schedules_created: 0
    }
    
    begin
      # Parse CSV data
      csv = CSV.parse(csv_data.strip, headers: true, header_converters: :symbol)
      
      if csv.empty?
        result[:message] = "CSV file is empty"
        return result
      end
      
      # Validate required headers for enhanced format - only customer data is required
      required_headers = [:name, :phone_number, :address]
      missing_headers = required_headers - csv.headers.compact.map(&:to_sym)

      if missing_headers.any?
        result[:message] = "Missing required columns: #{missing_headers.join(', ')}"
        return result
      end
      
      # Check user limit (maximum 50 customers)
      if csv.length > 50
        result[:message] = "Maximum 50 customers allowed per bulk import. Your file contains #{csv.length} rows."
        return result
      end
      
      imported_count = 0
      delivery_assignments_created = 0
      delivery_schedules_created = 0
      
      ActiveRecord::Base.transaction do
        csv.each_with_index do |row, index|
          row_number = index + 2 # +2 because index starts at 0 and we have headers
          
          # Skip empty rows
          if row[:name].blank? && row[:phone_number].blank? && row[:address].blank?
            result[:skipped_rows] << "Row #{row_number}: Empty row"
            next
          end
          
          # Validate required fields
          if row[:name].blank?
            result[:errors] << "Row #{row_number}: Name is required"
            next
          end
          
          if row[:phone_number].blank?
            result[:errors] << "Row #{row_number}: Phone number is required"
            next
          end
          
          if row[:address].blank?
            result[:errors] << "Row #{row_number}: Address is required"
            next
          end
          
          # Initialize variables for optional delivery assignment fields
          delivery_person = nil
          product = nil
          start_date = nil
          end_date = nil

          # Validate delivery person exists (if provided)
          if row[:delivery_person_id].present?
            delivery_person = User.find_by(id: row[:delivery_person_id], role: 'delivery_person')
            if delivery_person.nil?
              result[:errors] << "Row #{row_number}: Invalid delivery person ID #{row[:delivery_person_id]}"
              next
            end
          end

          # Validate product exists (if provided)
          if row[:product_id].present?
            product = Product.find_by(id: row[:product_id])
            if product.nil?
              result[:errors] << "Row #{row_number}: Invalid product ID #{row[:product_id]}"
              next
            end
          end
          
          # Validate dates (if provided)
          if row[:start_date].present? || row[:end_date].present?
            begin
              start_date = Date.parse(row[:start_date].to_s) if row[:start_date].present?
              end_date = Date.parse(row[:end_date].to_s) if row[:end_date].present?

              if start_date && end_date && start_date > end_date
                result[:errors] << "Row #{row_number}: Start date cannot be after end date"
                next
              end
            rescue ArgumentError
              result[:errors] << "Row #{row_number}: Invalid date format. Use YYYY-MM-DD format"
              next
            end
          end
          
          # Check if customer already exists
          existing_customer = Customer.find_by(
            name: row[:name].to_s.strip,
            phone_number: row[:phone_number].to_s.strip
          )
          
          if existing_customer
            result[:errors] << "Row #{row_number}: Customer '#{row[:name]}' with phone '#{row[:phone_number]}' already exists"
            next
          end
          
          # Create customer (columns 1-6)
          customer = Customer.new(
            name: row[:name].to_s.strip,
            phone_number: row[:phone_number].to_s.strip,
            address: row[:address].to_s.strip,
            email: row[:email].to_s.strip.presence,
            gst_number: row[:gst_number].to_s.strip.presence,
            pan_number: row[:pan_number].to_s.strip.presence,
            delivery_person_id: delivery_person&.id,
            user: current_user
          )
          
          # Set default password
          customer.password = "customer@123"
          customer.password_confirmation = "customer@123"
          
          if customer.save
            imported_count += 1
          else
            error_messages = customer.errors.full_messages.join(', ')
            result[:errors] << "Row #{row_number}: #{error_messages}"
            next
          end
          
          # Create delivery schedule and assignments if ALL optional fields are provided
          if product.present? && row[:quantity].present? && start_date.present? && end_date.present?
            schedule = DeliverySchedule.create(
              customer_id: customer.id,
              user_id: delivery_person&.id || current_user.id,
              product_id: product&.id,
              start_date: start_date,
              end_date: end_date,
              frequency: 'daily',
              status: 'active',
              default_quantity: row[:quantity].to_f,
              default_unit: product&.unit_type || 'pieces'
            )
            
            if schedule.persisted?
              delivery_schedules_created += 1
              
              # Create daily assignments
              (start_date..end_date).each do |date|
                DeliveryAssignment.create(
                  delivery_schedule_id: schedule.id,
                  customer_id: customer.id,
                  user_id: delivery_person&.id || current_user.id,
                  scheduled_date: date,
                  status: 'scheduled',
                  product_id: product&.id,
                  quantity: row[:quantity].to_f,
                  unit: product&.unit_type || 'pieces',
                  delivery_person_id: delivery_person&.id
                )
              end
              delivery_assignments_created += (end_date - start_date).to_i + 1
            end
          end
        end
      end
      
      result[:success] = true
      result[:imported_count] = imported_count
      result[:delivery_assignments_created] = delivery_assignments_created
      result[:delivery_schedules_created] = delivery_schedules_created
      result[:message] = "Enhanced import completed successfully"
      
    rescue CSV::MalformedCSVError => e
      result[:message] = "Invalid CSV format: #{e.message}"
    rescue => e
      result[:message] = "Error processing CSV: #{e.message}"
    end
    
    result
  end
  
  # Enhanced CSV template for bulk import with delivery assignments
  def self.enhanced_csv_template
    "name,phone_number,address,email,gst_number,pan_number,delivery_person_id,product_id,quantity,start_date,end_date\n" +
    "John Doe,9999999999,123 Main St Delhi,john@example.com,GST123,PAN123,1,1,5,2024-01-01,2024-01-31\n" +
    "Jane Smith,8888888888,456 Oak Ave Mumbai,jane@example.com,GST456,PAN456,2,2,3,2024-01-01,2024-01-31\n"
  end
  
  # Instance methods
  def assigned?
    delivery_person.present?
  end

  def has_coordinates?
    latitude.present? && longitude.present?
  end

  def coordinates
    return nil unless has_coordinates?
    [latitude.to_f, longitude.to_f]
  end

  def coordinates_string
    return "No coordinates" unless has_coordinates?
    "#{latitude.to_f.round(6)}, #{longitude.to_f.round(6)}"
  end

  def google_maps_url
    return nil unless has_coordinates?
    "https://www.google.com/maps/search/?api=1&query=#{latitude},#{longitude}"
  end

  def initials
    name.split.map(&:first).join.upcase[0, 2]
  end

  def full_address_with_coordinates
    address_parts = [address]
    address_parts << coordinates_string if has_coordinates?
    address_parts.join(" | ")
  end

  def customer_since
    created_at.strftime("%B %Y")
  end

  def formatted_id
    "##{id.to_s.rjust(6, '0')}"
  end

  def delivery_person_name
    delivery_person&.name || "Not Assigned"
  end

  # Customer type helper methods
  def customer_type_name
    case customer_type
    when 0
      'Regular'
    else
      'Irregular'
    end
  end

  def regular_customer?
    customer_type == 0
  end

  def irregular_customer?
    !regular_customer?
  end

  # Get delivery days for this customer
  def delivery_days
    delivered_dates = delivery_assignments.completed.pluck(:scheduled_date)
    return [] if delivered_dates.empty?

    if delivered_dates.length >= 28 # Assuming almost full month
      'Every day'
    else
      delivered_dates.map { |date| date.day }.sort.join(', ')
    end
  end

  # Get regular product name
  def regular_product_name
    return nil unless regular_product_id
    Product.find_by(id: regular_product_id)&.name
  end

  # Optimized Delivery related methods to prevent N+1 queries
  def total_deliveries
    # Count delivery assignments directly
    delivery_assignments.count
  end

  def pending_deliveries
    delivery_assignments.where(status: 'pending').count
  end

  def completed_deliveries
    delivery_assignments.where(status: 'completed').count
  end

  def last_delivery_date
    delivery_assignments.completed.order(:scheduled_date).last&.scheduled_date
  end

  def delivery_assignments_count
    # Since counter cache column doesn't exist, just count directly
    delivery_assignments.count
  end

  def active_schedules
    delivery_schedules.where(status: 'active')
  end

  def has_active_schedule?
    active_schedules.exists?
  end

  # Optimized Invoice related methods
  def total_invoices
    # Count invoices directly since counter cache was removed
    invoices.count
  end

  def total_invoice_amount
    # Use preloaded data if available, otherwise calculate
    if respond_to?(:total_invoice_amount) && attributes['total_invoice_amount'].present?
      attributes['total_invoice_amount'].to_f
    else
      amount = invoices.sum(:total_amount)
      amount.nil? ? 0 : amount.to_f
    end
  end

  def pending_invoice_amount
    amount = invoices.where(status: 'pending').sum(:total_amount)
    amount.nil? ? 0 : amount.to_f
  end

  # Scheduling methods
  def create_schedule_with_assignments(schedule_params)
    ActiveRecord::Base.transaction do
      # Create the schedule
      schedule = delivery_schedules.create!(schedule_params.merge(status: 'active'))
      
      # Generate assignments based on frequency
      assignments = generate_assignments_for_schedule(schedule)
      
      # Bulk create assignments
      DeliveryAssignment.insert_all(assignments) if assignments.any?
      
      schedule
    end
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Failed to create schedule: #{e.message}"
    false
  end

  # Distance calculation (if you want to add distance-based features later)
  def distance_from(lat, lng)
    return nil unless has_coordinates?
    return nil if lat.nil? || lng.nil?

    # Convert to float and validate
    lat_f = lat.to_f
    lng_f = lng.to_f
    my_lat_f = latitude.to_f
    my_lng_f = longitude.to_f

    return nil if lat_f.zero? || lng_f.zero? || my_lat_f.zero? || my_lng_f.zero?

    # Using Haversine formula for distance calculation
    rad_per_deg = Math::PI / 180  # PI / 180
    rkm = 6371                    # Earth radius in kilometers
    rm = rkm * 1000               # Radius in meters

    dlat_rad = (lat_f - my_lat_f) * rad_per_deg
    dlon_rad = (lng_f - my_lng_f) * rad_per_deg

    lat1_rad, lat2_rad = my_lat_f * rad_per_deg, lat_f * rad_per_deg

    a = Math.sin(dlat_rad / 2)**2 + Math.cos(lat1_rad) * Math.cos(lat2_rad) * Math.sin(dlon_rad / 2)**2
    c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))

    rm * c # Distance in meters
  end

  # Class methods
  def self.with_pending_deliveries
    joins(:deliveries).where(deliveries: { status: 'pending' }).distinct
  end

  def self.without_deliveries
    left_joins(:deliveries).where(deliveries: { id: nil })
  end

  def self.active_customers
    joins(:deliveries).where('deliveries.created_at > ?', 3.months.ago).distinct
  end

  def self.available_for_assignment
    unassigned.includes(:user)
  end

  # Monthly customer pattern analysis - OPTIMIZED with pagination support
  def self.analyze_monthly_patterns_paginated(month = Date.current.month, year = Date.current.year, delivery_person_id = nil, page = 1, per_page = 25)
    start_date = Date.new(year, month, 1).beginning_of_month
    end_date = start_date.end_of_month
    days_in_month = end_date.day

    # Filter customers by delivery person if specified
    customer_scope = Customer.includes(:delivery_person, :user).where(is_active: true)
    if delivery_person_id.present?
      customer_scope = customer_scope.where(delivery_person_id: delivery_person_id)
    end

    # Get total count for pagination
    total_customers = customer_scope.count

    # Apply pagination to customer scope
    offset = (page - 1) * per_page
    paginated_customers = customer_scope.limit(per_page).offset(offset).order(:name)
    customer_ids = paginated_customers.pluck(:id)

    # Get delivery assignments only for paginated customers
    delivery_data = DeliveryAssignment
      .joins(:product)
      .where(customer_id: customer_ids, scheduled_date: start_date..end_date)
      .select(
        'delivery_assignments.*',
        'products.name as product_name',
        'products.unit_type as product_unit_type'
      )

    # Group data by customer to avoid N+1
    customer_deliveries = delivery_data.group_by(&:customer_id)

    # Get all products in one query
    product_ids = delivery_data.map(&:product_id).uniq
    products_map = Product.where(id: product_ids).index_by(&:id)

    # Process only the paginated customers
    results = paginated_customers.map do |customer|
      deliveries = customer_deliveries[customer.id] || []

      # Calculate metrics from the deliveries
      delivery_days = deliveries.map { |d| d.scheduled_date.day }.uniq.sort

      # Calculate total liters from ALL delivery statuses
      total_liters = deliveries
        .select { |d| d.product_unit_type == 'liters' }
        .sum(&:quantity)

      # Calculate estimated amount (sum of final_amount_after_discount)
      estimated_amount = deliveries.sum do |delivery|
        delivery.final_amount_after_discount.to_f || 0
      end

      # Find primary product (most frequent)
      primary_product = if deliveries.any?
        product_counts = deliveries.group_by(&:product_id)
          .transform_values(&:count)
        most_frequent_product_id = product_counts.max_by { |_, count| count }.first
        products_map[most_frequent_product_id]
      else
        nil
      end

      # Determine customer pattern
      pattern = determine_customer_pattern(delivery_days, days_in_month, total_liters)

      {
        customer: customer,
        delivery_person_name: customer.delivery_person&.name || "Not Assigned",
        total_liters: total_liters.round(2),
        primary_product: primary_product,
        delivery_days: delivery_days,
        days_delivered: delivery_days.length,
        estimated_amount: estimated_amount.round(2),
        pattern: pattern,
        pattern_description: get_pattern_description(delivery_days, days_in_month),
        deliveries: deliveries,
        total_assignments: deliveries.length
      }
    end

    {
      results: results,
      total_customers: total_customers,
      total_pages: (total_customers.to_f / per_page).ceil,
      current_page: page,
      per_page: per_page
    }
  end

  # Keep the original method for backward compatibility (but optimize it)
  def self.analyze_monthly_patterns(month = Date.current.month, year = Date.current.year, delivery_person_id = nil)
    result = analyze_monthly_patterns_paginated(month, year, delivery_person_id, 1, 1000) # Large page to get all
    result[:results]
  end

  def self.determine_customer_pattern(delivery_days, days_in_month, total_liters)
    return 'irregular' if delivery_days.empty?

    # Regular: delivered every day and at least 0.5 liters total
    if delivery_days.length >= (days_in_month * 0.9) && total_liters >= 0.5
      'regular'
    else
      'irregular'
    end
  end

  def self.get_pattern_description(delivery_days, days_in_month)
    return 'No deliveries' if delivery_days.empty?

    if delivery_days.length >= (days_in_month * 0.9)
      'Every day'
    else
      "Days: #{delivery_days.join(', ')}"
    end
  end

  # Helper methods for new features
  def default_address
    customer_addresses.default_address.first || customer_addresses.first
  end

  def preferences
    customer_preference || build_customer_preference
  end

  def preferred_language
    preferences.language || 'en'
  end

  def delivery_time_window
    preferences.delivery_time_window
  end

  def notification_preferences
    preferences.notification_settings
  end

  def referral
    referral_code || create_referral_code
  end

  def total_points
    CustomerPoint.total_points_for_customer(id)
  end

  def award_points(points, action_type, reference = nil, description = nil)
    CustomerPoint.award_points(
      customer: self,
      points: points,
      action_type: action_type,
      reference: reference,
      description: description
    )
  end

  private

  def normalize_member_id
    self.member_id = member_id.presence&.strip
  end

  def delivery_person_capacity_check
    return if delivery_person_id.blank?
    # Assume a capacity check exists elsewhere; this is a placeholder
    true
  end

  def coordinates_presence
    # Only validate if one is present but not the other
    lat_present = latitude.present? && !latitude.to_s.strip.empty?
    lng_present = longitude.present? && !longitude.to_s.strip.empty?

    if lat_present ^ lng_present
      errors.add(:base, "Both latitude and longitude must be provided together")
    end
  end
  
  # Check if customer has a valid WhatsApp number
  def has_whatsapp?
    return false if phone_number.blank?
    
    # Use WhatsApp service to validate number
    whatsapp_service = WhatsappService.new
    whatsapp_service.valid_whatsapp_number?(phone_number)
  end

  def generate_assignments_for_schedule(schedule)
    return [] unless schedule.persisted?
    
    assignments = []
    current_date = schedule.start_date
    today = Date.current
    
    while current_date <= schedule.end_date
      # Create assignment for every day in the date range
      # Determine status based on whether the date is in the past
      assignment_status = current_date < today ? 'completed' : 'pending'
      
      assignments << {
        delivery_schedule_id: schedule.id,
        customer_id: id,
        user_id: schedule.user_id,
        product_id: schedule.product_id,
        scheduled_date: current_date,
        status: assignment_status,
        quantity: schedule.default_quantity || 1,
        unit: schedule.default_unit || 'pieces',
        created_at: Time.current,
        updated_at: Time.current
      }
      
      current_date += 1.day
    end
    
    assignments
  end

  def should_create_assignment_for_date?(date, frequency)
    case frequency
    when 'daily'
      true
    when 'weekly'
      date.wday == 1 # Monday
    when 'monthly'
      date.day == 1
    else
      true # Default to daily
    end
  end

  # Helper method to generate delivery assignments for a schedule
  def self.generate_delivery_assignments_for_schedule(schedule)
    assignments_created = 0
    current_date = schedule.start_date
    while current_date <= schedule.end_date
      # Determine status based on whether the date is in the past

      assignment = DeliveryAssignment.new(
        delivery_schedule: schedule,
        customer: schedule.customer,
        user: schedule.user,
        product: schedule.product,
        scheduled_date: current_date,
        status: 'completed', # ✅ Use calculated status
        quantity: schedule.default_quantity,
        unit: schedule.default_unit || 'pieces'
      )
      assignments_created += 1 if assignment.save

      current_date += 1.day
    end

    assignments_created
  end
end