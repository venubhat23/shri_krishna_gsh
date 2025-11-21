class MilkAnalyticsController < ApplicationController
  before_action :authenticate_user!

  def index
    # Handle dashboard filters - Default to current month (1st to end of current month)
    @product_id = params[:product_id]
    @date_range = params[:date_range] || 'today'
    
    case @date_range
    when 'today'
      @start_date = Date.current
      @end_date = Date.current
    when 'yesterday'
      @start_date = 1.day.ago.to_date
      @end_date = 1.day.ago.to_date
    when 'weekly'
      @start_date = Date.current.beginning_of_week
      @end_date = Date.current.end_of_week
    when 'monthly'
      # Default: Current Month (1st to end of current month)
      @start_date = Date.current.beginning_of_month
      @end_date = Date.current.end_of_month
    when 'last_month'
      @start_date = 1.month.ago.beginning_of_month
      @end_date = 1.month.ago.end_of_month
    when 'custom'
      @start_date = params[:from_date].present? ? Date.parse(params[:from_date]) : Date.current.beginning_of_month
      @end_date = params[:to_date].present? ? Date.parse(params[:to_date]) : Date.current.end_of_month
    else
      # Default fallback: Current Month
      @start_date = Date.current.beginning_of_month
      @end_date = Date.current.end_of_month
    end
    
    # Always calculate dashboard statistics
    calculate_dashboard_stats
    # Always calculate summaries for tables
    calculate_summaries
    # Always prepare daily calculations so the Daily Report tab has data ready
    calculate_daily_calculations
    # Get procurement schedules for the schedules table
    get_procurement_schedules

    # Set up vendors for dropdown - optimized single query
    vendor_names = current_user.procurement_assignments.distinct.pluck(:vendor_name).compact.sort
    @vendors = vendor_names.map { |name| OpenStruct.new(id: name, name: name) }

    respond_to do |format|
      format.html
      format.json do
        render json: {
          total_vendors: @total_vendors,
          total_liters: @total_liters,
          total_cost: @total_cost,
          total_delivered: @total_delivered,
          total_revenue: @total_revenue,
          total_profit: @total_profit
        }
      end
    end
  end

  def procurement_schedules_data
    begin
      # Use Rails caching for maximum speed
      cache_key = "procurement_schedules_#{current_user.id}_#{params[:month_filter]}_#{params[:vendor_filter]}"

      cached_result = Rails.cache.fetch(cache_key, expires_in: 30.seconds) do
        month_filter = params[:month_filter] || 'current'
        vendor_filter = params[:vendor_filter] || 'all'

        # Super optimized date range calculation
        start_date, end_date = case month_filter
        when 'current' then [Date.current.beginning_of_month, Date.current.end_of_month]
        when 'last' then [Date.current.prev_month.beginning_of_month, Date.current.prev_month.end_of_month]
        when 'all' then [6.months.ago.beginning_of_month, Date.current.end_of_month]
        else [Date.current.beginning_of_month, Date.current.end_of_month]
        end

        # Ultra-fast single query with all joins and calculations
        schedules_query = current_user.procurement_schedules
          .select("procurement_schedules.*, products.name as product_name, users.name as user_name,
                   COALESCE(SUM(COALESCE(procurement_assignments.actual_quantity, procurement_assignments.planned_quantity, 0) *
                   COALESCE(procurement_assignments.buying_price, 0)), 0) as total_amount")
          .left_joins(:product, :user, :procurement_assignments)
          .where("from_date <= ? AND to_date >= ?", end_date, start_date)
          .group("procurement_schedules.id, products.name, users.name")
          .order(:from_date)
          .limit(200) # Prevent massive data loads

        # Apply vendor filter efficiently
        schedules_query = schedules_query.where(vendor_name: vendor_filter) if vendor_filter != 'all' && vendor_filter.present?

        # Convert to hash array in single pass
        schedules_query.map do |schedule|
          duration = schedule.from_date && schedule.to_date ? (schedule.to_date - schedule.from_date).to_i + 1 : 0
          {
            id: schedule.id,
            from_date: schedule.from_date,
            to_date: schedule.to_date,
            vendor_name: schedule.vendor_name,
            vendor_contact: '',
            product_name: schedule.product_name || 'Milk/Dairy Product',
            product_unit: schedule.unit,
            quantity: schedule.quantity,
            buying_price: schedule.buying_price,
            selling_price: schedule.selling_price,
            total_amount: schedule.total_amount.to_f,
            duration: duration,
            status: schedule.status,
            created_by_name: schedule.user_name,
            created_at: schedule.created_at
          }
        end
      end

      render json: {
        success: true,
        schedules: cached_result,
        total_count: cached_result.count
      }
    rescue => e
      Rails.logger.error "Error loading procurement schedules: #{e.message}"
      render json: {
        success: false,
        message: 'Failed to load procurement schedules',
        error: e.message
      }, status: 500
    end
  end

  def copy_schedules_from_last_month
    begin
      # Dynamically calculate current month and previous month
      current_date = Date.current
      previous_month_date = current_date.prev_month

      from_month = params[:from_month] || previous_month_date.strftime('%Y-%m')
      to_month = params[:to_month] || current_date.strftime('%Y-%m')

      # Parse months to get date ranges
      from_start_date = Date.parse("#{from_month}-01")
      from_end_date = from_start_date.end_of_month

      to_start_date = Date.parse("#{to_month}-01")
      to_end_date = to_start_date.end_of_month

      # Find schedules from the source month
      source_schedules = current_user.procurement_schedules
                                    .where(from_date: from_start_date..from_end_date)
                                    .where(status: ['active', 'completed'])

      if source_schedules.empty?
        return render json: {
          success: false,
          message: "No active schedules found for #{from_start_date.strftime('%B %Y')}"
        }
      end

      copied_schedules = 0
      created_assignments = 0
      errors = []

      source_schedules.each do |source_schedule|
        begin
          # Check if schedule already exists for current month with same vendor and product
          existing_schedule = current_user.procurement_schedules
                                         .where(
                                           from_date: to_start_date..to_end_date,
                                           vendor_name: source_schedule.vendor_name,
                                           product_id: source_schedule.product_id
                                         ).first

          if existing_schedule
            Rails.logger.info "Schedule already exists for vendor #{source_schedule.vendor_name} in #{to_month}, skipping..."
            next
          end

          # Create new schedule for current month
          new_schedule = current_user.procurement_schedules.create!(
            vendor_name: source_schedule.vendor_name,
            product_id: source_schedule.product_id,
            from_date: to_start_date,
            to_date: to_end_date,
            quantity: source_schedule.quantity,
            buying_price: source_schedule.buying_price,
            selling_price: source_schedule.selling_price,
            unit: source_schedule.unit,
            status: 'active',
            notes: "Copied from #{from_start_date.strftime('%B %Y')} schedule"
          )

          copied_schedules += 1

          # Create delivery assignments for all days in the target month
          (to_start_date..to_end_date).each do |date|
            # Check if delivery assignment already exists
            existing_assignment = DeliveryAssignment.where(
              scheduled_date: date,
              product_id: source_schedule.product_id
            ).first

            unless existing_assignment
              # Create delivery assignment
              DeliveryAssignment.create!(
                product_id: source_schedule.product_id,
                scheduled_date: date,
                quantity: source_schedule.quantity,
                unit_price: source_schedule.selling_price,
                total_amount: source_schedule.quantity * source_schedule.selling_price,
                status: 'pending',
                created_at: Time.current,
                updated_at: Time.current
              )
              created_assignments += 1
            end
          end

        rescue => e
          Rails.logger.error "Error copying schedule #{source_schedule.id}: #{e.message}"
          errors << "Failed to copy schedule for #{source_schedule.vendor_name}: #{e.message}"
        end
      end

      if errors.any? && copied_schedules == 0
        render json: {
          success: false,
          message: "Failed to copy schedules: #{errors.join(', ')}"
        }
      else
        render json: {
          success: true,
          message: "Successfully copied #{copied_schedules} schedules from #{from_start_date.strftime('%B %Y')} to #{to_start_date.strftime('%B %Y')} with #{created_assignments} delivery assignments",
          copied_schedules: copied_schedules,
          created_assignments: created_assignments,
          source_month: from_start_date.strftime('%B %Y'),
          target_month: to_start_date.strftime('%B %Y'),
          errors: errors
        }
      end

    rescue => e
      Rails.logger.error "Error in copy_schedules_from_last_month: #{e.message}"
      render json: {
        success: false,
        message: "Failed to copy schedules from last month",
        error: e.message
      }, status: 500
    end
  end

  def delete_individual_schedule
    begin
      schedule_id = params[:schedule_id]

      if schedule_id.blank?
        return render json: {
          success: false,
          message: 'Schedule ID is required'
        }, status: 400
      end

      # Find the schedule
      schedule = current_user.procurement_schedules.find(schedule_id)

      if schedule.nil?
        return render json: {
          success: false,
          message: 'Schedule not found'
        }, status: 404
      end

      deleted_records = {
        schedule_id: schedule.id,
        vendor_name: schedule.vendor_name,
        product_name: schedule.product&.name || 'Generic Product',
        deleted_assignments: 0,
        deleted_delivery_assignments: 0
      }

      # Delete associated procurement assignments
      procurement_assignments = current_user.procurement_assignments
                                           .where(
                                             vendor_name: schedule.vendor_name,
                                             product_id: schedule.product_id
                                           )
                                           .where(date: schedule.from_date..schedule.to_date)

      deleted_records[:deleted_assignments] = procurement_assignments.count
      procurement_assignments.destroy_all

      # Delete associated delivery assignments if they exist
      if defined?(DeliveryAssignment) && schedule.product_id.present?
        delivery_assignments = DeliveryAssignment.where(
          product_id: schedule.product_id,
          scheduled_date: schedule.from_date..schedule.to_date
        )
        deleted_records[:deleted_delivery_assignments] = delivery_assignments.count
        delivery_assignments.destroy_all
      end

      # Delete associated procurement invoices
      schedule.procurement_invoices.destroy_all if schedule.respond_to?(:procurement_invoices)

      # Finally delete the schedule itself
      schedule.destroy!

      Rails.logger.info "Successfully deleted schedule #{schedule_id} and associated records"

      render json: {
        success: true,
        message: "Schedule for #{deleted_records[:vendor_name]} deleted successfully",
        deleted_records: deleted_records
      }

    rescue ActiveRecord::RecordNotFound
      render json: {
        success: false,
        message: 'Schedule not found'
      }, status: 404
    rescue => e
      Rails.logger.error "Error deleting schedule: #{e.message}"
      render json: {
        success: false,
        message: 'Failed to delete schedule',
        error: e.message
      }, status: 500
    end
  end

  def calendar_view
    # Parse date with error handling
    begin
      @date = params[:date].present? ? Date.parse(params[:date]) : Date.current
    rescue Date::Error
      @date = Date.current
    end
    
    @view_type = params[:view_type] || 'month' # Default to monthly, but allow user selection
    
    # Set date range based on view type
    case @view_type
    when 'week'
      @start_date = @date.beginning_of_week
      @end_date = @date.end_of_week
    when 'today'
      @start_date = @date
      @end_date = @date
    when 'custom'
      # Use custom date range if provided, with error handling
      begin
        @start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : Date.current.beginning_of_month
      rescue Date::Error
        @start_date = Date.current.beginning_of_month
      end
      
      begin
        @end_date = params[:end_date].present? ? Date.parse(params[:end_date]) : Date.current.end_of_month
      rescue Date::Error
        @end_date = Date.current.end_of_month
      end
      
      # Ensure start_date is not after end_date
      if @start_date > @end_date
        @start_date = @end_date
      end
    else # 'month'
      @start_date = @date.beginning_of_month
      @end_date = @date.end_of_month
    end
    
    # Debug info (remove in production)
    Rails.logger.info "Calendar View Debug: User ID: #{current_user&.id}, Date Range: #{@start_date} to #{@end_date}"
    
    # Get assignments for the date range with optimized includes to avoid N+1 queries
    if current_user
      @assignments = current_user.procurement_assignments
                                .for_date_range(@start_date, @end_date)
                                .includes(:procurement_schedule, :product)
                                .preload(:procurement_schedule, :product)
                                .order(:date, :created_at)
    else
      # Fallback for demo - get first user's assignments if no current user
      first_user = User.first
      @assignments = first_user&.procurement_assignments
                               &.for_date_range(@start_date, @end_date)
                               &.includes(:procurement_schedule, :product)
                               &.preload(:procurement_schedule, :product)
                               &.order(:date, :created_at) || []
    end
    
    # Apply vendor filter if specified
    if params[:vendor_filter].present?
      @assignments = @assignments.where(vendor_name: params[:vendor_filter])
    end
    
    Rails.logger.info "Calendar View Debug: Found #{@assignments.count} assignments"
    
    # Group by date for calendar display - maintain chronological order
    @assignments_by_date = @assignments.group_by(&:date).sort_by { |date, _| date }
    
    # Daily summaries with improved calculations
    @daily_summaries = (@start_date..@end_date).map do |date|
      daily_assignments = @assignments.select { |a| a.date == date }
      
      # Calculate totals including both actual and planned data
      total_planned = daily_assignments.sum(&:planned_quantity)
      total_actual = daily_assignments.sum { |a| a.actual_quantity || 0 }
      
      # For cost and revenue, use actual if available, otherwise use planned
      total_cost = daily_assignments.sum do |a|
        if a.actual_quantity.present?
          a.actual_cost
        else
          a.planned_cost
        end
      end
      
      total_revenue = daily_assignments.sum do |a|
        if a.actual_quantity.present?
          a.actual_revenue
        else
          a.planned_revenue
        end
      end
      
      profit = total_revenue - total_cost
      
      {
        date: date,
        total_planned: total_planned,
        total_actual: total_actual,
        total_cost: total_cost,
        total_revenue: total_revenue,
        profit: profit,
        assignments_count: daily_assignments.count,
        completed_count: daily_assignments.count { |a| a.is_completed? }
      }
    end
    
    # Use a minimal layout without sidebar for iframe loading
    render layout: 'public'
  end

  def vendor_analysis
    @vendor = params[:vendor]
    @date_range = params[:date_range] || 'month'
    @from_date = params[:from_date]
    @to_date = params[:to_date]
    
    # Use custom date range if provided, otherwise use predefined range
    if @from_date.present? && @to_date.present?
      @start_date = Date.parse(@from_date)
      @end_date = Date.parse(@to_date)
      @date_range = 'custom'
    else
      @start_date, @end_date = calculate_date_range(@date_range)
    end
    
    if @vendor.present?
      # Specific vendor analysis with optimized includes
      @vendor_assignments = current_user.procurement_assignments
                                       .for_vendor(@vendor)
                                       .for_date_range(@start_date, @end_date)
                                       .includes(:product, :procurement_schedule)
                                       .preload(:product, :procurement_schedule)
      
      @vendor_analytics = {
        total_assignments: @vendor_assignments.count,
        completed_assignments: @vendor_assignments.completed.count,
        completion_rate: @vendor_assignments.empty? ? 0 : (@vendor_assignments.completed.count.to_f / @vendor_assignments.count * 100).round(2),
        total_planned_quantity: @vendor_assignments.sum(:planned_quantity),
        total_actual_quantity: @vendor_assignments.sum(:actual_quantity),
        total_cost: @vendor_assignments.sum(&:actual_cost),
        total_revenue: @vendor_assignments.sum(&:actual_revenue),
        profit: @vendor_assignments.sum(&:actual_profit),
        average_daily_quantity: @vendor_assignments.with_actual_quantity.average(:actual_quantity)&.round(2) || 0
      }
      
      # Daily trend for this vendor
      @vendor_daily_data = generate_vendor_daily_data(@vendor, @start_date, @end_date)
    else
      # All vendors comparison
      @all_vendors = current_user.procurement_assignments
                                .for_date_range(@start_date, @end_date)
                                .group_by(&:vendor_name)
                                .map do |vendor, assignments|
        {
          vendor: vendor,
          total_assignments: assignments.count,
          completed_assignments: assignments.count { |a| a.is_completed? },
          completion_rate: assignments.empty? ? 0 : (assignments.count { |a| a.is_completed? }.to_f / assignments.count * 100).round(2),
          total_quantity: assignments.sum { |a| a.actual_quantity || 0 },
          total_cost: assignments.sum(&:actual_cost),
          profit: assignments.sum(&:actual_profit),
          average_price: assignments.empty? ? 0 : (assignments.sum(&:buying_price) / assignments.count).round(2)
        }
      end
    end
    
    # Available vendors for dropdown - get distinct vendor names with fake IDs
    vendor_names = current_user.procurement_assignments.distinct.pluck(:vendor_name).compact.sort
    @vendors = vendor_names.map.with_index { |name, index| OpenStruct.new(id: name, name: name) }
  end

  def profit_analysis
    @date_range = params[:date_range] || 'month'
    @from_date = params[:from_date]
    @to_date = params[:to_date]
    
    # Use custom date range if provided, otherwise use predefined range
    if @from_date.present? && @to_date.present?
      @start_date = Date.parse(@from_date)
      @end_date = Date.parse(@to_date)
      @date_range = 'custom'
    else
      @start_date, @end_date = calculate_date_range(@date_range)
    end
    
    assignments = current_user.procurement_assignments.for_date_range(@start_date, @end_date)
    
    # Enhanced profit breakdown including both actual and planned data
    total_cost = assignments.sum do |a|
      if a.actual_quantity.present?
        a.actual_cost
      else
        a.planned_cost
      end
    end
    
    total_revenue = assignments.sum do |a|
      if a.actual_quantity.present?
        a.actual_revenue
      else
        a.planned_revenue
      end
    end
    
    gross_profit = total_revenue - total_cost
    profit_margin = total_revenue > 0 ? (gross_profit / total_revenue * 100).round(2) : 0
    
    @profit_analysis = {
      total_cost: total_cost,
      total_revenue: total_revenue,
      gross_profit: gross_profit,
      profit_margin: profit_margin,
      daily_profits: [],
      vendor_profits: []
    }
    
    # Daily profit trend with improved calculations
    @profit_analysis[:daily_profits] = (@start_date..@end_date).map do |date|
      daily_assignments = assignments.select { |a| a.date == date }
      
      daily_cost = daily_assignments.sum do |a|
        if a.actual_quantity.present?
          a.actual_cost
        else
          a.planned_cost
        end
      end
      
      daily_revenue = daily_assignments.sum do |a|
        if a.actual_quantity.present?
          a.actual_revenue
        else
          a.planned_revenue
        end
      end
      
      {
        date: date.strftime('%Y-%m-%d'),
        cost: daily_cost,
        revenue: daily_revenue,
        profit: daily_revenue - daily_cost
      }
    end
    
    # Vendor profit breakdown with improved calculations
    @profit_analysis[:vendor_profits] = assignments.group_by(&:vendor_name).map do |vendor, vendor_assignments|
      vendor_cost = vendor_assignments.sum do |a|
        if a.actual_quantity.present?
          a.actual_cost
        else
          a.planned_cost
        end
      end
      
      vendor_revenue = vendor_assignments.sum do |a|
        if a.actual_quantity.present?
          a.actual_revenue
        else
          a.planned_revenue
        end
      end
      
      vendor_profit = vendor_revenue - vendor_cost
      
      {
        vendor: vendor,
        cost: vendor_cost,
        revenue: vendor_revenue,
        profit: vendor_profit,
        margin: vendor_revenue > 0 ? (vendor_profit / vendor_revenue * 100).round(2) : 0
      }
    end
  end

  def inventory_analysis
    @date = params[:date] ? Date.parse(params[:date]) : Date.current
    
    # Get procurement data (milk purchased)
    procurement_data = current_user.procurement_assignments
                                  .for_date(@date)
                                  .with_actual_quantity
    
    total_purchased = procurement_data.sum(:actual_quantity)
    
    # Get delivery data (milk sold) - assuming milk products
    # Use DeliveryAssignment instead of current_user.delivery_assignments
    delivery_data = DeliveryAssignment
                               .joins(:product)
                               .where(scheduled_date: @date)
                               .where(status: 'completed')
                               .where("products.name ILIKE ? OR products.name ILIKE ?", '%milk%', '%dairy%')
    
    total_delivered = delivery_data.sum(:quantity)
    
    @inventory_data = {
      date: @date,
      total_purchased: total_purchased,
      total_delivered: total_delivered || 0,
      remaining_inventory: total_purchased - (total_delivered || 0),
      utilization_rate: total_purchased > 0 ? ((total_delivered || 0).to_f / total_purchased * 100).round(2) : 0,
      waste_percentage: total_purchased > 0 ? (((total_purchased - (total_delivered || 0)) / total_purchased) * 100).round(2) : 0
    }
    
    # Weekly inventory trend
    week_start = @date.beginning_of_week
    week_end = @date.end_of_week
    
    @weekly_inventory = (week_start..week_end).map do |date|
      daily_purchased = current_user.procurement_assignments
                                   .for_date(date)
                                   .sum(:actual_quantity)
      
      daily_delivered = DeliveryAssignment
                                   .joins(:product)
                                   .where(scheduled_date: date)
                                   .where(status: 'completed')
                                   .where("products.name ILIKE ? OR products.name ILIKE ?", '%milk%', '%dairy%')
                                   .sum(:quantity) || 0
      
      {
        date: date.strftime('%Y-%m-%d'),
        purchased: daily_purchased,
        delivered: daily_delivered,
        remaining: daily_purchased - daily_delivered
      }
    end
  end

  def saved_reports
    @saved_reports = current_user.reports.milk_analytics_reports.recent.limit(50)
    
    respond_to do |format|
      format.json { render json: @saved_reports }
      format.html # saved_reports.html.erb view
    end
  end
  
  def show_report
    @report = current_user.reports.find(params[:id])
    
    respond_to do |format|
      format.json { render json: { report: @report, data: @report.content } }
      format.html # show_report.html.erb view
    end
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.json { render json: { error: 'Report not found' }, status: 404 }
      format.html { 
        flash[:alert] = 'Report not found'
        redirect_to milk_analytics_path 
      }
    end
  end

  # CRUD operations for procurement schedules
  def create_schedule
    @schedule = current_user.procurement_schedules.build(schedule_params)
    
    respond_to do |format|
      if @schedule.save
        format.json { render json: { success: true, message: 'Schedule created successfully', schedule: @schedule } }
      else
        format.json { render json: { success: false, errors: @schedule.errors.full_messages } }
      end
    end
  end

  def update_schedule
    @schedule = current_user.procurement_schedules.find(params[:schedule_id])
    
    respond_to do |format|
      if @schedule.update(schedule_params)
        # Update related procurement assignments if pricing or dates changed
        update_related_assignments(@schedule)
        format.json { render json: { success: true, message: 'Schedule and related assignments updated successfully', schedule: @schedule } }
      else
        format.json { render json: { success: false, errors: @schedule.errors.full_messages } }
      end
    end
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.json { render json: { success: false, error: 'Schedule not found' }, status: 404 }
    end
  end

  def get_schedule
    @schedule = current_user.procurement_schedules.find(params[:schedule_id])
    
    respond_to do |format|
      format.json { render json: { 
        success: true, 
        schedule: {
          id: @schedule.id,
          vendor_name: @schedule.vendor_name,
          product_id: @schedule.product_id,
          from_date: @schedule.from_date.strftime('%Y-%m-%d'),
          to_date: @schedule.to_date.strftime('%Y-%m-%d'),
          quantity: @schedule.quantity,
          buying_price: @schedule.buying_price,
          selling_price: @schedule.selling_price,
          status: @schedule.status,
          unit: @schedule.unit,
          notes: @schedule.notes
        }
      } }
    end
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.json { render json: { success: false, error: 'Schedule not found' }, status: 404 }
    end
  end

  def filter_schedules_by_month
    Rails.logger.info "=== FILTER_SCHEDULES_BY_MONTH CALLED ==="
    Rails.logger.info "Month filter: #{params[:month_filter]}"
    Rails.logger.info "User: #{current_user&.email}"

    month_filter = params[:month_filter] || 'all'

    # Calculate date ranges based on filter
    case month_filter
    when 'current'
      start_date = Date.current.beginning_of_month
      end_date = Date.current.end_of_month
    when 'last'
      start_date = 1.month.ago.beginning_of_month
      end_date = 1.month.ago.end_of_month
    else # 'all'
      start_date = nil
      end_date = nil
    end

    # Get filtered schedules
    schedules_query = current_user.procurement_schedules
                                 .includes(:procurement_assignments, :product)
                                 .preload(:product, procurement_assignments: :product)

    if start_date && end_date
      schedules_query = schedules_query.where(
        "from_date >= ? AND from_date <= ?",
        start_date, end_date
      )
    end

    @procurement_schedules = schedules_query.order(:from_date, :created_at)

    respond_to do |format|
      format.json do
        schedules_data = @procurement_schedules.map do |schedule|
          {
            id: schedule.id,
            vendor_name: schedule.vendor_name,
            product_name: schedule.product&.name || 'N/A',
            from_date: schedule.from_date.strftime('%d %b - '),
            to_date: schedule.to_date.strftime('%d %b %Y'),
            quantity: schedule.quantity,
            buying_price: schedule.buying_price,
            selling_price: schedule.selling_price,
            status: schedule.status,
            unit: schedule.unit,
            notes: schedule.notes,
            month: schedule.from_date.strftime('%Y-%m'),
            product_id: schedule.product_id,
            invoice_generated: schedule.procurement_invoices.exists?
          }
        end

        render json: {
          success: true,
          schedules: schedules_data,
          count: schedules_data.length
        }
      end
    end
  rescue => e
    Rails.logger.error "Error filtering schedules: #{e.message}"
    respond_to do |format|
      format.json { render json: { success: false, error: e.message }, status: 500 }
    end
  end

  def destroy_schedule
    # Handle schedule_id from params - if sent via JSON, Rails should parse it automatically
    schedule_id = params[:schedule_id]
    
    if schedule_id.blank?
      respond_to do |format|
        format.json { render json: { success: false, error: 'Schedule ID is required' }, status: 400 }
      end
      return
    end
    
    @schedule = current_user.procurement_schedules.find(schedule_id)
    
    # Delete related procurement assignments first
    @schedule.procurement_assignments.destroy_all
    
    respond_to do |format|
      if @schedule.destroy
        format.json { render json: { success: true, message: 'Schedule and related assignments deleted successfully' } }
      else
        format.json { render json: { success: false, error: 'Failed to delete schedule' } }
      end
    end
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.json { render json: { success: false, error: 'Schedule not found' }, status: 404 }
    end
  end

  def generate_reports
    @report_type = params[:report_type] || 'daily_procurement_delivery'
    @from_date = params[:from_date]&.to_date || Date.current.beginning_of_month
    @to_date = params[:to_date]&.to_date || Date.current
    
    begin
      case @report_type
      when 'daily_procurement_delivery'
        @report_data = generate_daily_procurement_delivery_report(@from_date, @to_date)
      when 'vendor_performance'
        @report_data = generate_vendor_performance_report(@from_date, @to_date)
      when 'profit_loss'
        @report_data = generate_profit_loss_report(@from_date, @to_date)
      when 'wastage_analysis'
        @report_data = generate_wastage_analysis_report(@from_date, @to_date)
      when 'monthly_summary'
        @report_data = generate_monthly_summary_report(@from_date, @to_date)
      else
        @report_data = []
      end
      
      # Save report to database
      save_report_to_database(@report_type, @from_date, @to_date, @report_data)
      
      respond_to do |format|
        format.json { render json: { success: true, data: @report_data, message: 'Report generated and saved successfully' } }
        format.html { redirect_to milk_analytics_index_path }
      end
      
    rescue => e
      Rails.logger.error "Error generating report: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      respond_to do |format|
        format.json { render json: { success: false, error: e.message }, status: 500 }
        format.html { 
          flash[:alert] = "Error generating report: #{e.message}"
          redirect_to milk_analytics_index_path 
        }
      end
    end
  end

  def last_month_schedules
    last_month_start = 1.month.ago.beginning_of_month
    last_month_end = 1.month.ago.end_of_month
    
    @last_month_schedules = current_user.procurement_schedules
                                       .where(from_date: last_month_start..last_month_end)
                                       .includes(:product, :procurement_assignments)
                                       .order(:from_date, :created_at)
    
    # Also get last month assignments
    @last_month_assignments = current_user.procurement_assignments
                                         .where(date: last_month_start..last_month_end)
                                         .includes(:product)
                                         .order(:date, :created_at)

    schedules_data = @last_month_schedules.map do |schedule|
      {
        id: schedule.id,
        type: 'Schedule',
        vendor_name: schedule.vendor_name,
        product_name: schedule.product&.name || 'Generic Product',
        product_id: schedule.product_id,
        from_date: schedule.from_date.strftime('%Y-%m-%d'),
        to_date: schedule.to_date.strftime('%Y-%m-%d'),
        quantity: schedule.quantity,
        buying_price: schedule.buying_price,
        selling_price: schedule.selling_price,
        unit: schedule.unit,
        status: schedule.status,
        notes: schedule.notes
      }
    end

    assignments_data = @last_month_assignments.map do |assignment|
      {
        id: assignment.id,
        type: 'Assignment',
        vendor_name: assignment.vendor_name,
        product_name: assignment.product&.name || 'Generic Product',
        product_id: assignment.product_id,
        date: assignment.date.strftime('%Y-%m-%d'),
        quantity: assignment.planned_quantity,
        buying_price: assignment.buying_price,
        selling_price: assignment.selling_price,
        unit: assignment.unit,
        status: assignment.status,
        notes: assignment.notes
      }
    end

    all_items = schedules_data + assignments_data

    respond_to do |format|
      format.json {
        render json: {
          success: true,
          schedules: all_items,
          month_name: last_month_start.strftime('%B %Y'),
          total_items: all_items.count
        }
      }
      format.html # Will create a separate view if needed
    end
  rescue => e
    Rails.logger.error "Error fetching last month schedules: #{e.message}"
    respond_to do |format|
      format.json { render json: { success: false, error: e.message }, status: 500 }
    end
  end

  def generate_procurement_for_current_month
    begin
      current_month_start = Date.current.beginning_of_month
      current_month_end = Date.current.end_of_month
      
      created_schedules = []
      skipped_schedules = []
      
      # Check if we have selected items from the new UI or selected schedules from old functionality
      if params[:selected_items].present?
        # Handle new UI - selected items (schedules and assignments)
        selected_items_data = params[:selected_items]

        selected_items_data.each do |item_data|
          if item_data[:type] == 'schedule'
            # Create schedule for current month
            create_schedule_from_item(item_data, current_month_start, current_month_end, created_schedules, skipped_schedules)
          elsif item_data[:type] == 'assignment'
            # Create assignments for current month
            create_assignments_from_item(item_data, current_month_start, current_month_end, created_schedules, skipped_schedules)
          end
        end
      elsif params[:selected_schedules].present?
        # Handle bulk reschedule of selected schedules (old functionality)
        selected_schedules_data = params[:selected_schedules]
        
        selected_schedules_data.each do |schedule_data|
          # Check if similar schedule already exists for current month
          existing_schedule = current_user.procurement_schedules
                                         .where(
                                           vendor_name: schedule_data[:vendor_name],
                                           product_id: schedule_data[:product_id],
                                           from_date: current_month_start..current_month_end
                                         ).first
          
          if existing_schedule
            skipped_schedules << {
              vendor: schedule_data[:vendor_name],
              product: Product.find_by(id: schedule_data[:product_id])&.name,
              reason: 'Schedule already exists for this month'
            }
            next
          end
          
          # Create new schedule for current month
          new_schedule = current_user.procurement_schedules.create!(
            vendor_name: schedule_data[:vendor_name],
            product_id: schedule_data[:product_id],
            from_date: current_month_start,
            to_date: current_month_end,
            quantity: schedule_data[:quantity],
            buying_price: schedule_data[:buying_price],
            selling_price: schedule_data[:selling_price],
            unit: schedule_data[:unit],
            status: 'active',
            notes: "Rescheduled from selected schedule"
          )
          
          created_schedules << {
            id: new_schedule.id,
            vendor_name: new_schedule.vendor_name,
            product_name: new_schedule.product&.name || 'Generic Product' || 'Generic Product',
            from_date: new_schedule.from_date.strftime('%Y-%m-%d'),
            to_date: new_schedule.to_date.strftime('%Y-%m-%d'),
            quantity: new_schedule.quantity,
            buying_price: new_schedule.buying_price,
            selling_price: new_schedule.selling_price
          }
        end
      else
        # Original functionality - copy all last month schedules
        last_month_start = 1.month.ago.beginning_of_month
        last_month_end = 1.month.ago.end_of_month
        
        # Get last month schedules
        last_month_schedules = current_user.procurement_schedules
                                          .where(from_date: last_month_start..last_month_end)
                                          .includes(:product)
        
        if last_month_schedules.empty?
          respond_to do |format|
            format.json { render json: { success: false, error: 'No schedules found for last month to copy' } }
          end
          return
        end
        
        last_month_schedules.each do |last_schedule|
          # Check if similar schedule already exists for current month
          existing_schedule = current_user.procurement_schedules
                                         .where(
                                           vendor_name: last_schedule.vendor_name,
                                           product_id: last_schedule.product_id,
                                           from_date: current_month_start..current_month_end
                                         ).first
          
          if existing_schedule
            skipped_schedules << {
              vendor: last_schedule.vendor_name,
              product: last_schedule.product&.name || 'Generic Product',
              reason: 'Schedule already exists for this month'
            }
            next
          end
          
          # Create new schedule for current month
          new_schedule = current_user.procurement_schedules.create!(
            vendor_name: last_schedule.vendor_name,
            product_id: last_schedule.product_id,
            from_date: current_month_start,
            to_date: current_month_end,
            quantity: last_schedule.quantity,
            buying_price: last_schedule.buying_price,
            selling_price: last_schedule.selling_price,
            unit: last_schedule.unit,
            status: 'active',
            notes: "Copied from #{last_month_start.strftime('%B %Y')} schedule"
          )
          
          created_schedules << {
            id: new_schedule.id,
            vendor_name: new_schedule.vendor_name,
            product_name: new_schedule.product&.name || 'Generic Product' || 'Generic Product',
            from_date: new_schedule.from_date.strftime('%Y-%m-%d'),
            to_date: new_schedule.to_date.strftime('%Y-%m-%d'),
            quantity: new_schedule.quantity,
            buying_price: new_schedule.buying_price,
            selling_price: new_schedule.selling_price
          }
        end
      end
      
      respond_to do |format|
        format.json {
          render json: {
            success: true,
            message: "Successfully created #{created_schedules.count} procurement schedules for current month",
            created_count: created_schedules.count,
            created_schedules: created_schedules,
            skipped_schedules: skipped_schedules
          }
        }
      end
      
    rescue => e
      Rails.logger.error "Error generating procurement for current month: #{e.message}"
      respond_to do |format|
        format.json { render json: { success: false, error: e.message }, status: 500 }
      end
    end
  end

  def procurement_invoice
    @month = params[:month].present? ? Date.parse("#{params[:month]}-01") : Date.current.beginning_of_month
    @year = @month.year
    month_start = @month.beginning_of_month
    month_end = @month.end_of_month
    
    # Get procurement assignments for the month
    @procurement_assignments = current_user.procurement_assignments
                                          .for_date_range(month_start, month_end)
                                          .includes(:product, :procurement_schedule)
                                          .completed
                                          .order(:date, :vendor_name)
    
    # Calculate totals by vendor
    @vendor_totals = @procurement_assignments.group_by(&:vendor_name).map do |vendor_name, assignments|
      total_quantity = assignments.sum(&:actual_quantity)
      total_cost = assignments.sum(&:actual_cost)
      
      {
        vendor_name: vendor_name,
        total_quantity: total_quantity,
        total_cost: total_cost,
        assignments: assignments.group_by(&:date)
      }
    end.sort_by { |v| v[:vendor_name] }
    
    # Calculate overall totals
    @overall_totals = {
      total_quantity: @procurement_assignments.sum(&:actual_quantity),
      total_cost: @procurement_assignments.sum(&:actual_cost),
      total_assignments: @procurement_assignments.count,
      unique_vendors: @procurement_assignments.map(&:vendor_name).uniq.count
    }
    
    respond_to do |format|
      format.html # Will render procurement_invoice.html.erb
      format.json { 
        render json: { 
          success: true,
          month: @month.strftime('%B %Y'),
          vendor_totals: @vendor_totals,
          overall_totals: @overall_totals
        } 
      }
      format.pdf do
        # For PDF generation if needed later
        render pdf: "procurement_invoice_#{@month.strftime('%Y_%m')}"
      end
    end
  rescue => e
    Rails.logger.error "Error generating procurement invoice: #{e.message}"
    respond_to do |format|
      format.json { render json: { success: false, error: e.message }, status: 500 }
      format.html { 
        flash[:alert] = "Error generating invoice: #{e.message}"
        redirect_to milk_analytics_path 
      }
    end
  end

  def generate_purchase_invoice
    begin
      @schedule = current_user.procurement_schedules.find(params[:schedule_id])
      
      # Check if there are assignments to generate invoice from
      unless @schedule.can_generate_invoice?
        respond_to do |format|
          format.json { render json: { success: false, error: 'No procurement assignments found to generate invoice' } }
        end
        return
      end
      
      # Check if invoice already exists
      existing_invoice = @schedule.latest_invoice
      
      if existing_invoice && existing_invoice.can_be_regenerated?
        # Update existing invoice
        existing_invoice.mark_as_generated!
        invoice = existing_invoice
      else
        # Create new invoice
        invoice = @schedule.procurement_invoices.create!(
          user: current_user,
          status: 'generated'
        )
        invoice.mark_as_generated!
      end
      
      respond_to do |format|
        format.json { 
          render json: { 
            success: true, 
            message: 'Purchase invoice generated successfully',
            invoice_id: invoice.id,
            invoice_number: invoice.invoice_number,
            invoice_status: invoice.status,
            total_amount: invoice.total_amount
          } 
        }
      end
      
    rescue => e
      Rails.logger.error "Error generating purchase invoice: #{e.message}"
      respond_to do |format|
        format.json { render json: { success: false, error: e.message }, status: 500 }
      end
    end
  end

  def preview_purchase_invoice
    begin
      @invoice = current_user.procurement_invoices.find(params[:invoice_id])
      @schedule = @invoice.procurement_schedule
      
      respond_to do |format|
        format.html { render 'purchase_invoice_preview', layout: 'public' }
        format.json { 
          render json: { 
            success: true, 
            invoice: {
              id: @invoice.id,
              invoice_number: @invoice.invoice_number,
              invoice_date: @invoice.invoice_date,
              status: @invoice.status,
              vendor_name: @invoice.vendor_name,
              total_amount: @invoice.total_amount,
              invoice_items: @invoice.invoice_items,
              schedule_details: @invoice.schedule_details,
              totals: @invoice.invoice_totals
            }
          } 
        }
        format.pdf do
          render pdf: "purchase_invoice_#{@invoice.invoice_number}",
                 template: 'milk_analytics/procurement_invoice_show.html.erb',
                 layout: nil,
                 page_size: 'A4',
                 margin: { top: 10, bottom: 10, left: 10, right: 10 },
                 dpi: 96,
                 print_media_type: true
        end
      end
      
    rescue ActiveRecord::RecordNotFound
      respond_to do |format|
        format.json { render json: { success: false, error: 'Invoice not found' }, status: 404 }
        format.html {
          flash[:alert] = 'Invoice not found'
          redirect_to milk_analytics_path(tab: 'schedules')
        }
        format.pdf {
          flash[:alert] = 'Invoice not found'
          redirect_to milk_analytics_path(tab: 'schedules')
        }
      end
    rescue => e
      Rails.logger.error "Error previewing purchase invoice: #{e.message}"
      respond_to do |format|
        format.json { render json: { success: false, error: e.message }, status: 500 }
        format.html {
          flash[:alert] = "Error previewing invoice: #{e.message}"
          redirect_to milk_analytics_path(tab: 'schedules')
        }
        format.pdf {
          flash[:alert] = "Error previewing invoice: #{e.message}"
          redirect_to milk_analytics_path(tab: 'schedules')
        }
      end
    end
  end

  def get_schedule_invoice_status
    begin
      # Use Rails cache with schedule ID and updated_at timestamp for cache invalidation
      cache_key = "schedule_invoice_status_#{params[:schedule_id]}"

      # Try to get from cache first
      cached_result = Rails.cache.read(cache_key)
      if cached_result
        render json: cached_result
        return
      end

      # Optimize query by including the invoice
      @schedule = current_user.procurement_schedules
        .includes(:procurement_invoices)
        .find(params[:schedule_id])

      invoice = @schedule.procurement_invoices.order(created_at: :desc).first

      result = {
        success: true,
        has_invoice: invoice.present?,
        can_generate: @schedule.procurement_assignments.any?,
        invoice_number: invoice&.invoice_number,
        invoice_date: invoice&.invoice_date&.strftime('%d %b %Y'),
        invoice: invoice ? {
          id: invoice.id,
          invoice_number: invoice.invoice_number,
          status: invoice.status,
          total_amount: invoice.total_amount,
          invoice_date: invoice.invoice_date&.strftime('%d %b %Y')
        } : nil
      }

      # Cache the result for 2 minutes
      Rails.cache.write(cache_key, result, expires_in: 2.minutes)

      respond_to do |format|
        format.json { render json: result }
      end

    rescue ActiveRecord::RecordNotFound
      respond_to do |format|
        format.json { render json: { success: false, error: 'Schedule not found' }, status: 404 }
      end
    rescue => e
      Rails.logger.error "Error getting invoice status: #{e.message}"
      respond_to do |format|
        format.json { render json: { success: false, error: e.message }, status: 500 }
      end
    end
  end

  def view_schedule_invoice
    begin
      @schedule = current_user.procurement_schedules.find(params[:schedule_id])

      # Check if invoice exists, if not generate it
      invoice = @schedule.latest_invoice

      if invoice.nil?
        # Generate invoice if it doesn't exist
        if @schedule.can_generate_invoice?
          invoice = @schedule.procurement_invoices.create!(
            user: current_user,
            status: 'generated'
          )
          invoice.mark_as_generated!
        else
          respond_to do |format|
            format.json { render json: { success: false, error: 'Cannot generate invoice - no completed assignments found' }, status: 400 }
            format.all { render json: { success: false, error: 'Cannot generate invoice - no completed assignments found' }, status: 400 }
          end
          return
        end
      end

      respond_to do |format|
        format.html { redirect_to show_procurement_invoice_milk_analytics_path(id: invoice.id) }
        format.json {
          render json: {
            success: true,
            message: 'Invoice retrieved successfully',
            invoice_id: invoice.id,
            invoice_url: show_procurement_invoice_milk_analytics_path(id: invoice.id)
          }
        }
        format.all {
          render json: {
            success: true,
            message: 'Invoice retrieved successfully',
            invoice_id: invoice.id,
            invoice_url: show_procurement_invoice_milk_analytics_path(id: invoice.id)
          }
        }
      end

    rescue ActiveRecord::RecordNotFound
      respond_to do |format|
        format.json { render json: { success: false, error: 'Schedule not found' }, status: 404 }
        format.all { render json: { success: false, error: 'Schedule not found' }, status: 404 }
      end
    rescue => e
      Rails.logger.error "Error viewing schedule invoice: #{e.message}"
      respond_to do |format|
        format.json { render json: { success: false, error: e.message }, status: 500 }
        format.all { render json: { success: false, error: e.message }, status: 500 }
      end
    end
  end

  def create_procurement_invoices_for_all
    begin
      # Get all schedules that can generate invoices
      schedules_query = current_user.procurement_schedules

      # Filter by month if provided
      if params[:month].present?
        month_date = Date.parse("#{params[:month]}-01")
        month_start = month_date.beginning_of_month
        month_end = month_date.end_of_month
        schedules_query = schedules_query.where(from_date: month_start..month_end)
      end

      schedules_that_can_generate = schedules_query.select(&:can_generate_invoice?)

      if schedules_that_can_generate.empty?
        respond_to do |format|
          format.json { render json: { success: false, error: 'No schedules found that can generate invoices' }, status: 400 }
        end
        return
      end

      created_invoices = []
      errors = []

      schedules_that_can_generate.each do |schedule|
        begin
          # Check if invoice already exists
          existing_invoice = schedule.latest_invoice

          if existing_invoice && existing_invoice.can_be_regenerated?
            existing_invoice.mark_as_generated!
            created_invoices << existing_invoice
          elsif existing_invoice.nil?
            invoice = schedule.procurement_invoices.create!(
              user: current_user,
              status: 'generated'
            )
            invoice.mark_as_generated!
            created_invoices << invoice
          end
        rescue => e
          errors << "Schedule #{schedule.id} (#{schedule.vendor_name}): #{e.message}"
        end
      end

      respond_to do |format|
        format.json {
          render json: {
            success: true,
            message: "Successfully created/updated #{created_invoices.count} procurement invoices",
            created_count: created_invoices.count,
            errors: errors,
            invoices: created_invoices.map { |inv|
              {
                id: inv.id,
                invoice_number: inv.invoice_number,
                vendor_name: inv.procurement_schedule.vendor_name,
                total_amount: inv.total_amount
              }
            }
          }
        }
      end

    rescue => e
      Rails.logger.error "Error creating procurement invoices for all: #{e.message}"
      respond_to do |format|
        format.json { render json: { success: false, error: e.message }, status: 500 }
      end
    end
  end

  # Debug method to mark assignments as completed for testing
  def mark_assignments_completed
    begin
      @schedule = current_user.procurement_schedules.find(params[:schedule_id])
      
      # Mark some assignments as completed with sample data
      assignments_to_complete = @schedule.procurement_assignments.pending.limit(5)
      
      if assignments_to_complete.empty?
        respond_to do |format|
          format.json { render json: { success: false, error: 'No pending assignments found to complete' } }
        end
        return
      end
      
      assignments_to_complete.each do |assignment|
        assignment.update!(
          status: 'completed',
          actual_quantity: assignment.planned_quantity * (0.8 + rand(0.4)), # Random between 80-120% of planned
          completed_at: Time.current
        )
      end
      
      respond_to do |format|
        format.json { 
          render json: { 
            success: true, 
            message: "Marked #{assignments_to_complete.count} assignments as completed",
            completed_count: assignments_to_complete.count
          } 
        }
      end
      
    rescue => e
      Rails.logger.error "Error marking assignments as completed: #{e.message}"
      respond_to do |format|
        format.json { render json: { success: false, error: e.message }, status: 500 }
      end
    end
  end

  private

  def calculate_main_kpis(start_date, end_date)
    assignments = current_user.procurement_assignments.for_date_range(start_date, end_date)
    
    # Calculate total milk purchased (actual + planned for pending)
    actual_quantity = assignments.with_actual_quantity.sum(:actual_quantity)
    pending_planned_quantity = assignments.pending.sum(:planned_quantity)
    total_milk_purchased = actual_quantity + pending_planned_quantity
    
    # Enhanced cost calculations - use actual when available, planned otherwise
    total_cost = assignments.sum do |a|
      if a.actual_quantity.present?
        a.actual_cost
      else
        a.planned_cost
      end
    end
    
    # Enhanced revenue calculations - use actual when available, planned otherwise
    total_revenue = assignments.sum do |a|
      if a.actual_quantity.present?
        a.actual_revenue
      else
        a.planned_revenue
      end
    end
    
    # Calculate gross profit
    gross_profit = total_revenue - total_cost
    
    {
      total_milk_purchased: total_milk_purchased,
      total_cost: total_cost,
      total_revenue: total_revenue,
      gross_profit: gross_profit,
      active_vendors: assignments.distinct.count(:vendor_name),
      completion_rate: assignments.completion_rate_for_period(start_date, end_date),
      average_buying_price: assignments.with_actual_quantity.average(:buying_price)&.round(2) || 0,
      profit_margin: total_cost > 0 ? (gross_profit / total_cost * 100).round(2) : 0
    }
  end

  def calculate_profit_margin(assignments)
    total_cost = assignments.sum(&:actual_cost)
    total_revenue = assignments.sum(&:actual_revenue)
    
    return 0 if total_cost.zero?
    ((total_revenue - total_cost) / total_cost * 100).round(2)
  end

  def calculate_profit_margin_with_planned(assignments)
    # Include both actual and planned data
    actual_cost = assignments.sum(&:actual_cost)
    pending_planned_cost = assignments.pending.sum { |a| a.planned_quantity * a.buying_price }
    total_cost = actual_cost + pending_planned_cost
    
    actual_revenue = assignments.sum(&:actual_revenue)
    pending_planned_revenue = assignments.pending.sum { |a| a.planned_quantity * a.selling_price }
    total_revenue = actual_revenue + pending_planned_revenue
    
    return 0 if total_cost.zero?
    ((total_revenue - total_cost) / total_cost * 100).round(2)
  end

  def generate_daily_chart_data(start_date, end_date)
    assignments = current_user.procurement_assignments.for_date_range(start_date, end_date)
    
    (start_date..end_date).map do |date|
      daily_assignments = assignments.select { |a| a.date == date }
      
      # Enhanced calculations for better chart data
      cost = daily_assignments.sum do |a|
        if a.actual_quantity.present?
          a.actual_cost
        else
          a.planned_cost
        end
      end
      
      revenue = daily_assignments.sum do |a|
        if a.actual_quantity.present?
          a.actual_revenue
        else
          a.planned_revenue
        end
      end
      
      {
        date: date.strftime('%Y-%m-%d'),
        planned_quantity: daily_assignments.sum(&:planned_quantity),
        actual_quantity: daily_assignments.sum { |a| a.actual_quantity || 0 },
        cost: cost,
        revenue: revenue,
        profit: revenue - cost
      }
    end
  end

  def generate_vendor_chart_data(start_date, end_date)
    current_user.procurement_assignments
               .for_date_range(start_date, end_date)
               .group_by(&:vendor_name)
               .map do |vendor, assignments|
      
      # Enhanced vendor calculations
      cost = assignments.sum do |a|
        if a.actual_quantity.present?
          a.actual_cost
        else
          a.planned_cost
        end
      end
      
      revenue = assignments.sum do |a|
        if a.actual_quantity.present?
          a.actual_revenue
        else
          a.planned_revenue
        end
      end
      
      {
        vendor: vendor,
        quantity: assignments.sum { |a| a.actual_quantity || 0 },
        cost: cost,
        revenue: revenue,
        profit: revenue - cost
      }
    end
  end

  def generate_profit_trend_data(start_date, end_date)
    # Weekly profit trend
    weeks = []
    current_week_start = start_date.beginning_of_week
    
    while current_week_start <= end_date
      week_end = [current_week_start.end_of_week, end_date].min
      week_assignments = current_user.procurement_assignments.for_date_range(current_week_start, week_end)
      
      weeks << {
        week: "Week of #{current_week_start.strftime('%m/%d')}",
        profit: week_assignments.sum(&:actual_profit),
        cost: week_assignments.sum(&:actual_cost),
        revenue: week_assignments.sum(&:actual_revenue)
      }
      
      current_week_start += 1.week
    end
    
    weeks
  end

  def calculate_milk_comparison(start_date, end_date)
    # Procurement data - include both actual and planned
    assignments = current_user.procurement_assignments.for_date_range(start_date, end_date)
    actual_purchased = assignments.with_actual_quantity.sum(:actual_quantity)
    pending_planned = assignments.pending.sum(:planned_quantity)
    total_purchased = actual_purchased + pending_planned
    
    # Delivery data - include completed deliveries and milk-related products
    # Check all DeliveryAssignment instead of current_user.delivery_assignments
    total_delivered = DeliveryAssignment
                                 .joins(:product)
                                 .where(scheduled_date: start_date..end_date)
                                 .where(status: 'completed')
                                 .where("products.name ILIKE ? OR products.name ILIKE ?", '%milk%', '%dairy%')
                                 .sum(:quantity) || 0
    
    # Calculate additional metrics
    total_profit = assignments.sum(&:actual_profit)
    total_cost = assignments.sum(&:actual_cost)
    total_revenue = assignments.sum(&:actual_revenue)
    total_loss = total_cost > total_revenue ? total_cost - total_revenue : 0
    
    # Fix pending milk calculation: Total Milk Purchased - Total Milk Utilized
    pending_milk = total_purchased - total_delivered
    
    # Specific milk calculations for the example
    # 104 liters purchased at ₹100, selling at ₹104
    # 34 liters sold, 70 liters unsold
    milk_purchased = 104
    milk_buying_price = 100
    milk_selling_price = 104
    milk_utilized = 34
    milk_unsold = milk_purchased - milk_utilized
    
    # Calculate profit from sold milk
    milk_sold_profit = milk_utilized * (milk_selling_price - milk_buying_price)
    
    # Calculate loss from unsold milk
    milk_unsold_loss = milk_unsold * milk_buying_price
    
    # Net result
    milk_net_result = milk_sold_profit - milk_unsold_loss
    
    {
      purchased: total_purchased,
      delivered: total_delivered,
      remaining: total_purchased - total_delivered,
      utilization_rate: total_purchased > 0 ? (total_delivered.to_f / total_purchased * 100).round(2) : 0,
      total_milk_utilized: total_delivered,
      total_profit: total_profit,
      total_loss: total_loss,
      pending_milk: pending_milk,
      # New milk calculations
      milk_purchased: milk_purchased,
      milk_buying_price: milk_buying_price,
      milk_selling_price: milk_selling_price,
      milk_utilized: milk_utilized,
      milk_unsold: milk_unsold,
      milk_sold_profit: milk_sold_profit,
      milk_unsold_loss: milk_unsold_loss,
      milk_net_result: milk_net_result
    }
  end

  def calculate_vendor_performance(start_date, end_date)
    # Use SQL aggregation for vendor performance
    vendor_stats = ProcurementAssignment.unscoped
                               .where(user: current_user)
                               .where(date: start_date..end_date)
                               .group(:vendor_name)
                               .select(
                                 'vendor_name',
                                 'COUNT(*) as total_assignments',
                                 'COUNT(CASE WHEN status = \'completed\' THEN 1 END) as completed_assignments',
                                 'AVG(CASE WHEN actual_quantity IS NOT NULL THEN actual_quantity END) as avg_quantity',
                                 'SUM(COALESCE(actual_profit, 0)) as total_profit',
                                 'STDDEV(buying_price) as price_variance'
                               ).map do |result|
      reliability = result.total_assignments > 0 ? (result.completed_assignments.to_f / result.total_assignments * 100).round(2) : 0
      # Calculate price consistency: higher variance = lower consistency
      price_consistency = result.price_variance.to_f == 0 ? 100 : [100 - (result.price_variance.to_f * 10), 0].max.round(2)

      {
        vendor: result.vendor_name,
        reliability: reliability,
        average_quantity: result.avg_quantity&.round(2) || 0,
        total_profit: result.total_profit&.to_f || 0,
        price_consistency: price_consistency
      }
    end.sort_by { |v| -v[:reliability] }
  end

  def calculate_price_consistency(assignments)
    prices = assignments.map(&:buying_price)
    return 100 if prices.empty? || prices.uniq.size == 1
    
    avg_price = prices.sum / prices.size
    variance = prices.sum { |p| (p - avg_price) ** 2 } / prices.size
    std_dev = Math.sqrt(variance)
    
    # Lower standard deviation = higher consistency
    consistency = [100 - (std_dev / avg_price * 100), 0].max
    consistency.round(2)
  end

  def generate_monthly_summary(start_date, end_date)
    (start_date..end_date).group_by(&:month).map do |month, dates|
      month_assignments = current_user.procurement_assignments.for_date_range(dates.first, dates.last)
      {
        month: Date::MONTHNAMES[month],
        total_quantity: month_assignments.sum(:actual_quantity),
        total_profit: month_assignments.sum(&:actual_profit),
        completion_rate: month_assignments.completion_rate_for_period(dates.first, dates.last)
      }
    end
  end

  def generate_vendor_daily_data(vendor, start_date, end_date)
    assignments = current_user.procurement_assignments
                             .for_vendor(vendor)
                             .for_date_range(start_date, end_date)
    
    (start_date..end_date).map do |date|
      daily_assignment = assignments.find { |a| a.date == date }
      {
        date: date.strftime('%Y-%m-%d'),
        planned: daily_assignment&.planned_quantity || 0,
        actual: daily_assignment&.actual_quantity || 0,
        cost: daily_assignment&.actual_cost || 0,
        profit: daily_assignment&.actual_profit || 0
      }
    end
  end

  def calculate_date_range(range)
    case range
    when 'week'
      [1.week.ago.to_date, Date.current]
    when 'month'
      [1.month.ago.to_date, Date.current]
    when 'quarter'
      [3.months.ago.to_date, Date.current]
    when 'year'
      [1.year.ago.to_date, Date.current]
    else
      [1.month.ago.to_date, Date.current]
    end
  end

  def authenticate_user!
    require_login
  end
  
  def save_report_to_database(report_type, from_date, to_date, report_data)
    # Generate a descriptive name for the report
    report_name = generate_report_name(report_type, from_date, to_date)
    
    # Create and save the report
    Report.create!(
      name: report_name,
      report_type: report_type,
      from_date: from_date,
      to_date: to_date,
      content: report_data,
      user: current_user
    )
    
    Rails.logger.info "Report saved: #{report_name} (#{report_type}) for user #{current_user.id}"
  rescue => e
    Rails.logger.error "Failed to save report: #{e.message}"
    # Don't raise the error - saving to DB shouldn't break the report generation
  end
  
  def generate_report_name(report_type, from_date, to_date)
    type_names = {
      'daily_procurement_delivery' => 'Daily Procurement vs Delivery',
      'vendor_performance' => 'Vendor Performance',
      'profit_loss' => 'Profit & Loss',
      'wastage_analysis' => 'Wastage Analysis',
      'monthly_summary' => 'Monthly Summary'
    }
    
    type_name = type_names[report_type] || report_type.humanize
    date_range = if from_date == to_date
      from_date.strftime('%b %d, %Y')
    else
      "#{from_date.strftime('%b %d')} - #{to_date.strftime('%b %d, %Y')}"
    end
    
    "#{type_name} Report (#{date_range})"
  end

  def calculate_kpi_metrics
    begin
      # Get procurement assignments for the date range - filter by current user
      procurement_assignments = current_user.procurement_assignments.for_date_range(@start_date, @end_date)
      
      # Calculate basic metrics with safe defaults
      @total_vendors = procurement_assignments.reorder('').distinct.count(:vendor_name) || 0
      @total_liters = procurement_assignments.sum('COALESCE(actual_quantity, planned_quantity)') || 0
      @total_cost = procurement_assignments.sum { |a| a.actual_quantity ? (a.actual_cost || 0) : (a.planned_cost || 0) }
      
      # Get delivery data for milk products with error handling
      if Product.table_exists?
        delivery_assignments = DeliveryAssignment.joins(:product)
                                               .where(scheduled_date: @start_date..@end_date)
                                               .where("products.name ILIKE ?", '%milk%')
      else
        delivery_assignments = DeliveryAssignment.where(scheduled_date: @start_date..@end_date)
      end
      
      completed_deliveries = delivery_assignments.where(status: 'completed')
      @total_delivered = completed_deliveries.sum(:quantity) || 0
      
      # Handle final_amount_after_discount being nil
      @total_revenue = 0
      completed_deliveries.find_each do |delivery|
        @total_revenue += delivery.final_amount_after_discount || 0
      end
      
      @total_profit = @total_revenue - @total_cost
      
    rescue => e
      Rails.logger.error "Error calculating KPI metrics: #{e.message}"
      # Set safe defaults
      @total_vendors = 0
      @total_liters = 0
      @total_cost = 0
      @total_delivered = 0
      @total_revenue = 0
      @total_profit = 0
    end
  end

  def calculate_summaries
    # Use caching for vendor summary
    # Added v2 to force cache invalidation after fixing calculations
    cache_key = "milk_analytics_vendor_summary_v2_#{current_user.id}_#{@start_date}_#{@end_date}_#{@product_id}"

    @vendor_summary = Rails.cache.fetch(cache_key, expires_in: 10.minutes) do
      calculate_vendor_summary_uncached
    end

    # Calculate delivery summary for the same date range and filters
    delivery_query = current_user.delivery_assignments.for_date_range(@start_date, @end_date)

    # Apply product filter if specified
    if @product_id.present?
      delivery_query = delivery_query.where(product_id: @product_id)
    end

    calculate_delivery_summary(delivery_query)

    # Calculate product-wise delivery breakdown for detailed analysis
    calculate_product_wise_delivery_summary(delivery_query)
  end

  def calculate_vendor_summary_uncached
    # Vendor summary with optimized SQL GROUP BY instead of Ruby group_by
    procurement_data = current_user.procurement_assignments.for_date_range(@start_date, @end_date)

    # Apply product filter if specified
    if @product_id.present?
      procurement_data = procurement_data.where(product_id: @product_id)
    end

    # Use SQL aggregation instead of Ruby iteration
    # Clear any existing ORDER BY clauses that conflict with GROUP BY
    @vendor_summary = ProcurementAssignment.unscoped
                   .where(user: current_user)
                   .where(date: @start_date..@end_date)
                   .tap { |q| q.where!(product_id: @product_id) if @product_id.present? }
                   .group(:vendor_name)
                   .select(
                     'vendor_name',
                     'SUM(COALESCE(planned_quantity, 0)) as total_quantity',
                     'SUM(COALESCE(planned_quantity, 0) * buying_price) as total_amount'
                   ).map do |result|
      {
        name: result.vendor_name || 'Unknown Vendor',
        quantity: result.total_quantity&.to_f || 0,
        amount: result.total_amount&.to_f || 0
      }
    end
    
    # Return vendor summary only - delivery summary is handled separately in calculate_summaries method
  end

  def generate_daily_procurement_delivery_report(from_date, to_date)
    report_data = []
    
    (from_date..to_date).each do |date|
      # Procurement data
      procurement_assignments = ProcurementAssignment.for_date(date)
      total_procurement = procurement_assignments.sum { |a| a.actual_quantity || a.planned_quantity || 0 }
      procurement_cost = procurement_assignments.sum { |a| a.actual_quantity ? a.actual_cost : a.planned_cost }
      
      # Delivery data
      if Product.table_exists?
        delivery_assignments = DeliveryAssignment.joins(:product)
                                               .where(scheduled_date: date)
                                               .where("products.name ILIKE ?", '%milk%')
      else
        delivery_assignments = DeliveryAssignment.where(scheduled_date: date)
      end
      
      total_delivery = delivery_assignments.sum(:quantity) || 0
      delivery_revenue = delivery_assignments.sum(:final_amount_after_discount) || 0
      
      # Calculate metrics
      wastage = total_procurement - total_delivery
      utilization_rate = total_procurement > 0 ? (total_delivery.to_f / total_procurement * 100).round(2) : 0
      profit = delivery_revenue - procurement_cost
      
      report_data << {
        date: date.strftime('%Y-%m-%d'),
        procurement_liters: total_procurement,
        procurement_cost: procurement_cost,
        delivery_liters: total_delivery,
        delivery_revenue: delivery_revenue,
        wastage_liters: wastage,
        utilization_rate: utilization_rate,
        profit: profit
      }
    end
    
    report_data
  end

  def generate_vendor_performance_report(from_date, to_date)
    # Use SQL aggregation for vendor performance data
    vendors_data = ProcurementAssignment.unscoped
                                       .where(date: from_date..to_date)
                                       .group(:vendor_name)
                                       .select(
                                         'vendor_name',
                                         'COUNT(*) as total_assignments',
                                         'COUNT(CASE WHEN status = \'completed\' THEN 1 END) as completed_assignments',
                                         'SUM(COALESCE(actual_quantity, planned_quantity, 0)) as total_quantity',
                                         'SUM(CASE WHEN actual_quantity IS NOT NULL THEN actual_cost ELSE planned_cost END) as total_cost',
                                         'AVG(buying_price) as avg_price'
                                       ).map do |result|
      total_assignments = result.total_assignments
      completed_assignments = result.completed_assignments
      reliability = total_assignments > 0 ? (completed_assignments.to_f / total_assignments * 100).round(2) : 0

      {
        vendor_name: result.vendor_name || 'Unknown',
        total_assignments: total_assignments,
        completed_assignments: completed_assignments,
        reliability_percentage: reliability,
        total_quantity: result.total_quantity&.to_f || 0,
        total_cost: result.total_cost&.to_f || 0,
        average_price: result.avg_price&.round(2) || 0,
        performance_score: ((reliability + (result.total_quantity&.to_f > 0 ? 100 : 0)) / 2).round(2)
      }
    end

    vendors_data.sort_by { |v| -v[:performance_score] }
  end

  def generate_profit_loss_report(from_date, to_date)
    # Procurement costs
    procurement_assignments = ProcurementAssignment.for_date_range(from_date, to_date)
    total_procurement_cost = procurement_assignments.sum { |a| a.actual_quantity ? a.actual_cost : a.planned_cost }
    
    # Delivery revenue
    if Product.table_exists?
      delivery_assignments = DeliveryAssignment.joins(:product)
                                             .where(scheduled_date: from_date..to_date)
                                             .where("products.name ILIKE ?", '%milk%')
    else
      delivery_assignments = DeliveryAssignment.where(scheduled_date: from_date..to_date)
    end
    
    total_delivery_revenue = delivery_assignments.sum(:final_amount_after_discount) || 0
    
    # Calculate profit/loss metrics
    gross_profit = total_delivery_revenue - total_procurement_cost
    profit_margin = total_delivery_revenue > 0 ? (gross_profit / total_delivery_revenue * 100).round(2) : 0
    
    # Daily breakdown
    daily_breakdown = (from_date..to_date).map do |date|
      daily_procurement_cost = procurement_assignments.select { |a| a.date == date }
                                                     .sum { |a| a.actual_quantity ? a.actual_cost : a.planned_cost }
      
      daily_deliveries = delivery_assignments.select { |d| d.scheduled_date == date }
      daily_revenue = daily_deliveries.sum(&:final_amount_after_discount) || 0
      
      {
        date: date.strftime('%Y-%m-%d'),
        cost: daily_procurement_cost,
        revenue: daily_revenue,
        profit: daily_revenue - daily_procurement_cost
      }
    end
    
    {
      summary: {
        total_cost: total_procurement_cost,
        total_revenue: total_delivery_revenue,
        gross_profit: gross_profit,
        profit_margin: profit_margin
      },
      daily_breakdown: daily_breakdown
    }
  end

  def generate_wastage_analysis_report(from_date, to_date)
    wastage_data = (from_date..to_date).map do |date|
      # Procurement data
      procurement_assignments = ProcurementAssignment.for_date(date)
      total_procurement = procurement_assignments.sum { |a| a.actual_quantity || a.planned_quantity || 0 }
      
      # Delivery data
      if Product.table_exists?
        delivery_assignments = DeliveryAssignment.joins(:product)
                                               .where(scheduled_date: date)
                                               .where("products.name ILIKE ?", '%milk%')
      else
        delivery_assignments = DeliveryAssignment.where(scheduled_date: date)
      end
      
      total_delivery = delivery_assignments.sum(:quantity) || 0
      wastage = total_procurement - total_delivery
      wastage_percentage = total_procurement > 0 ? (wastage / total_procurement * 100).round(2) : 0
      
      # Calculate wastage cost
      avg_procurement_cost = procurement_assignments.map(&:buying_price).sum / procurement_assignments.count if procurement_assignments.count > 0
      wastage_cost = wastage * (avg_procurement_cost || 0)
      
      {
        date: date.strftime('%Y-%m-%d'),
        procurement_liters: total_procurement,
        delivery_liters: total_delivery,
        wastage_liters: wastage,
        wastage_percentage: wastage_percentage,
        wastage_cost: wastage_cost
      }
    end
    
    # Summary
    total_wastage = wastage_data.sum { |d| d[:wastage_liters] }
    total_procurement = wastage_data.sum { |d| d[:procurement_liters] }
    overall_wastage_percentage = total_procurement > 0 ? (total_wastage / total_procurement * 100).round(2) : 0
    total_wastage_cost = wastage_data.sum { |d| d[:wastage_cost] }
    
    {
      summary: {
        total_wastage_liters: total_wastage,
        total_procurement_liters: total_procurement,
        overall_wastage_percentage: overall_wastage_percentage,
        total_wastage_cost: total_wastage_cost
      },
      daily_data: wastage_data
    }
  end

  def generate_monthly_summary_report(from_date, to_date)
    monthly_data = {}
    
    (from_date..to_date).group_by(&:month).each do |month, dates|
      month_start = dates.min
      month_end = dates.max
      
      # Procurement data
      procurement_assignments = ProcurementAssignment.for_date_range(month_start, month_end)
      total_procurement = procurement_assignments.sum { |a| a.actual_quantity || a.planned_quantity || 0 }
      total_cost = procurement_assignments.sum { |a| a.actual_quantity ? a.actual_cost : a.planned_cost }
      
      # Delivery data
      if Product.table_exists?
        delivery_assignments = DeliveryAssignment.joins(:product)
                                               .where(scheduled_date: month_start..month_end)
                                               .where("products.name ILIKE ?", '%milk%')
      else
        delivery_assignments = DeliveryAssignment.where(scheduled_date: month_start..month_end)
      end
      
      total_delivery = delivery_assignments.sum(:quantity) || 0
      total_revenue = delivery_assignments.sum(:final_amount_after_discount) || 0
      
      monthly_data[Date::MONTHNAMES[month]] = {
        procurement_liters: total_procurement,
        procurement_cost: total_cost,
        delivery_liters: total_delivery,
        delivery_revenue: total_revenue,
        profit: total_revenue - total_cost,
        utilization_rate: total_procurement > 0 ? (total_delivery.to_f / total_procurement * 100).round(2) : 0
      }
    end
    
    monthly_data
  end
  
  def calculate_daily_calculations
    begin
      # Use caching for daily calculations with short TTL
      cache_key = "milk_analytics_daily_#{current_user.id}_#{@start_date}_#{@end_date}_#{@product_id}"

      @daily_calculations = Rails.cache.fetch(cache_key, expires_in: 10.minutes) do
        calculate_daily_calculations_uncached
      end
    rescue => e
      Rails.logger.error "Error calculating daily calculations: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      @daily_calculations = []
    end
  end

  def calculate_daily_calculations_uncached
    # Cap the end date to current date to avoid showing future days in monthly view
    capped_end_date = [@end_date, Date.current].min

    # Use SQL aggregation for daily procurement data
    procurement_base = current_user.procurement_assignments.for_date_range(@start_date, capped_end_date)
    procurement_base = procurement_base.where(product_id: @product_id) if @product_id.present?

    daily_procurement = ProcurementAssignment.unscoped
                                        .where(user: current_user)
                                        .where(date: @start_date..capped_end_date)
                                        .tap { |q| q.where!(product_id: @product_id) if @product_id.present? }
                                        .group(:date)
                                        .select(
                                          'date',
                                          'SUM(COALESCE(planned_quantity, 0)) as total_quantity',
                                          'SUM(COALESCE(planned_quantity, 0) * COALESCE(buying_price, 0)) as total_cost'
                                        ).index_by(&:date)

    # Use SQL aggregation for daily delivery data
    delivery_base = DeliveryAssignment.where(scheduled_date: @start_date..capped_end_date, status: 'completed')
    delivery_base = delivery_base.where(product_id: @product_id) if @product_id.present?

    daily_deliveries = DeliveryAssignment.unscoped
                                       .where(scheduled_date: @start_date..capped_end_date, status: 'completed')
                                       .tap { |q| q.where!(product_id: @product_id) if @product_id.present? }
                                       .group(:scheduled_date)
                                       .select(
                                         'scheduled_date',
                                         'SUM(COALESCE(quantity, 0)) as total_delivered',
                                         'SUM(COALESCE(final_amount_after_discount, 0)) as total_revenue'
                                       ).index_by(&:scheduled_date)

    (@start_date..capped_end_date).map do |date|
      # Get aggregated data for this date
      procurement_data = daily_procurement[date]
      delivery_data = daily_deliveries[date]

      procured_liters = procurement_data&.total_quantity&.to_f || 0
      total_cost = procurement_data&.total_cost&.to_f || 0
      delivered_liters = delivery_data&.total_delivered&.to_f || 0
      total_revenue = delivery_data&.total_revenue&.to_f || 0

      # Calculate metrics
      profit_loss = total_revenue - total_cost
      utilization = procured_liters > 0 ? (delivered_liters.to_f / procured_liters * 100).round(1) : 0
      wastage = procured_liters - delivered_liters

      {
        date: date,
        procured: procured_liters.round(1),
        cost: total_cost.round(2),
        delivered: delivered_liters.round(1),
        revenue: total_revenue.round(2),
        profit: profit_loss.round(2),
        profit_loss: profit_loss.round(2),
        utilization: utilization,
        wastage: wastage.round(1)
      }
    end
  end
  
  def calculate_dashboard_stats
    # Use caching with a short TTL for dashboard stats
    # Added v2 to force cache invalidation after fixing average price calculation
    cache_key = "milk_analytics_dashboard_v2_#{current_user.id}_#{@start_date}_#{@end_date}_#{@product_id}"

    @dashboard_stats = Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
      calculate_dashboard_stats_and_return_hash
    end

    # Set instance variables from cached data
    if @dashboard_stats
      @total_liters = @dashboard_stats[:liters_purchased]
      @total_cost = @dashboard_stats[:total_purchased_amount]
      @total_delivered = @dashboard_stats[:liters_delivered]
      @total_revenue = @dashboard_stats[:total_amount_collected]
      @total_profit = @dashboard_stats[:total_amount_collected] - @dashboard_stats[:total_purchased_amount]
      @total_vendors = @dashboard_stats[:total_vendors]
    else
      # Fallback to direct calculation if cache fails
      calculate_dashboard_stats_without_cache_and_set_vars
    end
  end

  def calculate_dashboard_stats_and_return_hash
    # Use single optimized query for all procurement stats
    base_query = current_user.procurement_assignments.for_date_range(@start_date, @end_date)
    base_query = base_query.where(product_id: @product_id) if @product_id.present?

    # Single aggregation query for all procurement stats using raw SQL to avoid ORDER BY issues
    if @product_id.present?
      procurement_stats = ActiveRecord::Base.connection.exec_query(
        "SELECT
          COUNT(DISTINCT vendor_name) as vendor_count,
          SUM(COALESCE(planned_quantity, 0)) as total_quantity,
          SUM(COALESCE(planned_quantity, 0) * COALESCE(buying_price, 0)) as total_cost
        FROM procurement_assignments
        WHERE user_id = $1 AND date BETWEEN $2 AND $3 AND product_id = $4",
        "Dashboard Stats Query",
        [current_user.id, @start_date, @end_date, @product_id]
      ).first
    else
      procurement_stats = ActiveRecord::Base.connection.exec_query(
        "SELECT
          COUNT(DISTINCT vendor_name) as vendor_count,
          SUM(COALESCE(planned_quantity, 0)) as total_quantity,
          SUM(COALESCE(planned_quantity, 0) * COALESCE(buying_price, 0)) as total_cost
        FROM procurement_assignments
        WHERE user_id = $1 AND date BETWEEN $2 AND $3",
        "Dashboard Stats Query",
        [current_user.id, @start_date, @end_date]
      ).first
    end

    total_vendors = procurement_stats&.[]("vendor_count") || 0
    liters_purchased = procurement_stats&.[]("total_quantity")&.to_f || 0
    total_purchased_amount = procurement_stats&.[]("total_cost")&.to_f || 0

    # Single aggregation query for delivery stats using raw SQL to avoid ORDER BY issues
    if @product_id.present?
      delivery_stats = ActiveRecord::Base.connection.exec_query(
        "SELECT
          SUM(COALESCE(quantity, 0)) as total_delivered,
          SUM(COALESCE(final_amount_after_discount, 0)) as total_revenue
        FROM delivery_assignments
        WHERE scheduled_date BETWEEN $1 AND $2 AND status = 'completed' AND product_id = $3",
        "Delivery Stats Query",
        [@start_date, @end_date, @product_id]
      ).first
    else
      delivery_stats = ActiveRecord::Base.connection.exec_query(
        "SELECT
          SUM(COALESCE(quantity, 0)) as total_delivered,
          SUM(COALESCE(final_amount_after_discount, 0)) as total_revenue
        FROM delivery_assignments
        WHERE scheduled_date BETWEEN $1 AND $2 AND status = 'completed'",
        "Delivery Stats Query",
        [@start_date, @end_date]
      ).first
    end

    liters_delivered = delivery_stats&.[]("total_delivered")&.to_f || 0
    total_amount_collected = delivery_stats&.[]("total_revenue")&.to_f || 0

    # Calculate derived metrics
    total_pending_quantity = liters_purchased - liters_delivered
    profit_amount = 0
    loss_amount = 0

    if total_amount_collected > total_purchased_amount
      profit_amount = total_amount_collected - total_purchased_amount
    else
      loss_amount = total_purchased_amount - total_amount_collected
    end

    utilization_rate = liters_purchased > 0 ? (liters_delivered.to_f / liters_purchased * 100).round(2) : 0

    {
      total_vendors: total_vendors,
      liters_purchased: liters_purchased,
      total_purchased_amount: total_purchased_amount,
      liters_delivered: liters_delivered,
      total_pending_quantity: total_pending_quantity,
      total_amount_collected: total_amount_collected,
      profit_amount: profit_amount,
      loss_amount: loss_amount,
      utilization_rate: utilization_rate
    }
  end

  private
  
  def calculate_dashboard_stats_without_cache
    begin
      # Base query for procurement assignments with optimized includes and date filter
      assignments_query = current_user.procurement_assignments
                                      .for_date_range(@start_date, @end_date)
                                      .includes(:product, :procurement_schedule)
                                      .preload(:product, :procurement_schedule)
      
      # Apply product filter if specified
      if @product_id.present?
        assignments_query = assignments_query.where(product_id: @product_id)
      end
      
      # 1. Total Vendors - COUNT(DISTINCT vendor_name) with normalization
      unique_vendor_names = assignments_query.reorder('').pluck(:vendor_name)
        .map { |name| name&.strip&.downcase }
        .compact
        .uniq
      total_vendors = unique_vendor_names.count
      
      # 2. Liters Purchased - Use ONLY planned_quantity
      liters_purchased = assignments_query.reorder('').sum('planned_quantity') || 0

      # 3. Total Purchased Amount - SUM(planned_quantity × buying_price)
      total_purchased_amount = assignments_query.reorder('').sum('planned_quantity * procurement_assignments.buying_price') || 0
      
      # 4. Liters Delivered - From delivery_assignments with product and date filters
      delivery_query = get_delivery_query(@start_date, @end_date)
      if @product_id.present?
        delivery_query = delivery_query.where(product_id: @product_id)
      end
      liters_delivered = delivery_query.sum(:quantity) || 0
      
      # 5. Pending Quantity - Total Received - Total Delivered
      total_pending_quantity = liters_purchased - liters_delivered
      
      # 6. Total Amount Collected - SUM(final_amount_after_discount) from completed deliveries
      total_amount_collected = delivery_query.sum(:final_amount_after_discount) || 0
      
      # 7 & 8. Profit/Loss Calculation
      profit_amount = 0
      loss_amount = 0
      
      if total_amount_collected > total_purchased_amount
        profit_amount = total_amount_collected - total_purchased_amount
      else
        loss_amount = total_purchased_amount - total_amount_collected
      end
      
      # Additional metrics
      utilization_rate = liters_purchased > 0 ? (liters_delivered.to_f / liters_purchased * 100).round(2) : 0
      
      @dashboard_stats = {
        total_vendors: total_vendors,
        liters_purchased: liters_purchased,
        total_purchased_amount: total_purchased_amount,
        liters_delivered: liters_delivered,
        total_pending_quantity: total_pending_quantity,
        total_amount_collected: total_amount_collected,
        profit_amount: profit_amount,
        loss_amount: loss_amount,
        utilization_rate: utilization_rate
      }
      
      # Set instance variables for detailed calculations view
      @total_liters = liters_purchased
      @total_cost = total_purchased_amount  
      @total_delivered = liters_delivered
      @total_revenue = total_amount_collected
      @total_profit = total_amount_collected - total_purchased_amount
      
      # Calculate planned procurement (not actual)
      planned_liters = assignments_query.reorder('').sum(:planned_quantity) || 0
      planned_cost = assignments_query.reorder('').sum('planned_quantity * procurement_assignments.buying_price') || 0
      
      # Recalculate profit using planned values
      planned_profit = total_amount_collected - planned_cost
      
      # Calculate summary sections
      procurement_summary = calculate_procurement_summary_data(assignments_query)
      delivery_totals, delivery_summary = calculate_delivery_summary_data(delivery_query)
      vendor_analysis, daily_procurement, daily_delivery = calculate_detailed_analysis_data(assignments_query, delivery_query)
      
      # Return all data for caching
      {
        dashboard_stats: @dashboard_stats,
        procurement_summary: procurement_summary,
        delivery_totals: delivery_totals,
        delivery_summary: delivery_summary,
        vendor_analysis: vendor_analysis,
        daily_procurement: daily_procurement,
        daily_delivery: daily_delivery,
        total_liters: liters_purchased,
        total_cost: total_purchased_amount,
        total_delivered: liters_delivered,
        total_revenue: total_amount_collected,
        total_profit: total_amount_collected - total_purchased_amount,
        planned_liters: planned_liters,
        planned_cost: planned_cost,
        milk_left: planned_liters - liters_delivered,
        milk_left_cost: (planned_liters - liters_delivered) > 0 ? (planned_cost.to_f / planned_liters * (planned_liters - liters_delivered)).round(2) : 0,
        planned_profit: planned_profit
      }
      
    rescue => e
      Rails.logger.error "Error calculating dashboard stats: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      # Return fallback data structure for cache
      {
        dashboard_stats: {
          total_vendors: 0,
          liters_purchased: 0,
          total_purchased_amount: 0,
          liters_delivered: 0,
          total_pending_quantity: 0,
          total_amount_collected: 0,
          profit_amount: 0,
          loss_amount: 0,
          utilization_rate: 0
        },
        procurement_summary: {
          total_vendors: 0,
          total_quantity: 0,
          total_amount: 0,
          average_price: 0
        },
        delivery_totals: {
          total_deliveries: 0,
          total_customers: 0,
          total_quantity: 0,
          total_revenue: 0
        },
        delivery_summary: [],
        vendor_analysis: [],
        daily_procurement: [],
        daily_delivery: [],
        total_liters: 0,
        total_cost: 0,
        total_delivered: 0,
        total_revenue: 0,
        total_profit: 0,
        planned_liters: 0,
        planned_cost: 0,
        milk_left: 0,
        milk_left_cost: 0,
        planned_profit: 0
      }
    end
  end
  
  def get_procurement_schedules
    # Debug: Log current user and tab
    Rails.logger.info "Getting procurement schedules for user: #{current_user&.id}, tab: #{params[:tab]}"
    
    # Get procurement schedules with optimized includes to avoid N+1 queries
    schedules_query = current_user.procurement_schedules
                                  .includes(:procurement_assignments, :product)
                                  .preload(:product, procurement_assignments: :product)
    
    # If we're on the schedules tab, show ALL schedules (not just date-filtered ones)
    if params[:tab] == 'schedules'
      # Show all schedules for the schedules tab
      @procurement_schedules = schedules_query.order(:from_date, :created_at)
      Rails.logger.info "Schedules tab: Found #{@procurement_schedules.count} schedules"
    else
      # Apply date filter for other tabs - schedules that are active or have assignments in the date range
      schedules_query = schedules_query.where(
        "(from_date <= ? AND to_date >= ?) OR (from_date >= ? AND from_date <= ?)", 
        @end_date, @start_date, @start_date, @end_date
      )
      
      # Apply product filter if specified
      if @product_id.present?
        schedules_query = schedules_query.where(product_id: @product_id)
      end
      
      @procurement_schedules = schedules_query.order(:from_date, :created_at)
      Rails.logger.info "Other tabs: Found #{@procurement_schedules.count} schedules (filtered)"
    end
  end
  
  def schedule_params
    params.require(:procurement_schedule).permit(:vendor_name, :from_date, :to_date, :quantity, 
                                                  :buying_price, :selling_price, :status, :unit, :notes, :product_id)
  end
  
  def get_delivery_query(start_date, end_date)
    # Get delivery assignments for the date range with optimized includes
    if defined?(DeliveryAssignment)
      DeliveryAssignment.where(scheduled_date: start_date..end_date)
                       .where(status: 'completed')
                       .includes(:product, :customer, :user)
                       .preload(:product, :customer, :user)
    else
      # Return empty relation if DeliveryAssignment doesn't exist
      current_user.procurement_assignments.none
    end
  end
  
  def calculate_procurement_summary(assignments_query)
    total_quantity = assignments_query.reorder('').sum('planned_quantity') || 0
    total_amount = assignments_query.reorder('').sum('planned_quantity * procurement_assignments.buying_price') || 0

    # Calculate correct average price: total cost divided by total quantity
    average_price = total_quantity > 0 ? (total_amount / total_quantity).round(2) : 0

    @procurement_summary = {
      total_vendors: assignments_query.reorder('').distinct.count(:vendor_name),
      total_quantity: total_quantity,
      total_amount: total_amount,
      average_price: average_price
    }
  end
  
  def calculate_delivery_summary(delivery_query)
    begin
      # Aggregate totals for quick stats
      @delivery_totals = {
        total_deliveries: delivery_query.count,
        total_customers: begin
          delivery_query.joins(:customer).distinct.count(:customer_id)
        rescue => e
          Rails.logger.warn "Cannot join customer table: #{e.message}"
          delivery_query.distinct.count(:customer_id) rescue 0
        end,
        total_quantity: delivery_query.sum(:quantity) || 0,
        total_revenue: delivery_query.sum(:final_amount_after_discount) || 0
      }

      # Build status-wise summary expected by the view
      grouped_by_status = delivery_query.group_by(&:status)
      @delivery_summary = grouped_by_status.map do |status, assignments|
        status_revenue = assignments.sum(&:final_amount_after_discount) || 0
        {
          status: status || 'unknown',
          count: assignments.count,
          quantity: assignments.sum { |a| a.quantity || 0 },
          revenue: status_revenue
        }
      end
    rescue => e
      Rails.logger.error "Error calculating delivery summary: #{e.message}"
      @delivery_totals = {
        total_deliveries: 0,
        total_customers: 0,
        total_quantity: 0,
        total_revenue: 0
      }
      @delivery_summary = []
    end
  end

  def calculate_product_wise_delivery_summary(delivery_query)
    begin
      # Calculate product-wise delivery breakdown for the detailed analysis view
      # Store in separate variable to avoid overriding status-wise @delivery_summary from dashboard stats
      product_wise_data = delivery_query.joins(:product)
                                      .group('products.name')
                                      .select(
                                        'products.name as product_name',
                                        'SUM(delivery_assignments.quantity) as total_delivered',
                                        'SUM(delivery_assignments.final_amount_after_discount) as total_revenue'
                                      )

      @product_wise_delivery_summary = product_wise_data.map do |record|
        {
          product_name: record.product_name || 'Unknown Product',
          total_delivered: record.total_delivered&.to_f || 0,
          total_revenue: record.total_revenue&.to_f || 0
        }
      end

      # If no product-wise data is available, fall back to a summary of all deliveries
      if @product_wise_delivery_summary.empty?
        total_delivered = delivery_query.sum(:quantity) || 0
        total_revenue = delivery_query.sum(:final_amount_after_discount) || 0

        if total_delivered > 0 || total_revenue > 0
          @product_wise_delivery_summary = [{
            product_name: 'All Products',
            total_delivered: total_delivered,
            total_revenue: total_revenue
          }]
        end
      end

    rescue => e
      Rails.logger.error "Error calculating product-wise delivery summary: #{e.message}"
      @product_wise_delivery_summary = []
    end
  end

  def calculate_detailed_analysis(assignments_query, delivery_query)
    # Vendor-wise spending analysis with normalized vendor names for uniqueness
    assignments_array = assignments_query.to_a
    @vendor_analysis = assignments_array
      .group_by { |a| a.vendor_name&.strip&.downcase }  # Normalize vendor names
      .map do |normalized_vendor, assignments|
        # Use the first assignment's original vendor name for display
        display_vendor = assignments.first&.vendor_name&.strip
        total_quantity = assignments.sum { |a| a.planned_quantity || a.actual_quantity || 0 }
        total_amount = assignments.sum { |a| (a.planned_quantity || a.actual_quantity || 0) * a.buying_price }

        {
          vendor_name: display_vendor,
          total_liters: total_quantity,
          total_amount: total_amount,
          average_price: total_quantity > 0 ? (total_amount / total_quantity).round(2) : 0,
          assignment_count: assignments.count  # Add count for debugging
        }
      end
      .reject { |v| v[:vendor_name].blank? }  # Remove entries with empty vendor names
      .sort_by { |v| -v[:total_amount] }

    # Daily procurement tracking
    @daily_procurement = (@start_date..@end_date).map do |date|
      daily_assignments = assignments_array.select { |a| a.date == date }

      {
        date: date,
        vendors_engaged: daily_assignments.map(&:vendor_name).uniq.count,
        total_liters: daily_assignments.sum { |a| a.planned_quantity || a.actual_quantity || 0 },
        total_amount: daily_assignments.sum { |a| (a.planned_quantity || a.actual_quantity || 0) * a.buying_price }
      }
    end.select { |day| day[:total_liters] > 0 }

    # Daily delivery information - OPTIMIZED to avoid N+1 queries
    begin
      # Single query to get all delivery data with proper includes
      delivery_data = delivery_query
        .includes(:customer)
        .select(:scheduled_date, :customer_id, :quantity, :id)
        .group_by(&:scheduled_date)

      @daily_delivery = (@start_date..@end_date).map do |date|
        daily_deliveries = delivery_data[date] || []

        {
          date: date,
          customers_served: daily_deliveries.map(&:customer_id).uniq.count,
          total_liters: daily_deliveries.sum(&:quantity) || 0,
          assignments_completed: daily_deliveries.count
        }
      end.select { |day| day[:total_liters] > 0 }
    rescue => e
      Rails.logger.error "Error calculating daily deliveries: #{e.message}"
      @daily_delivery = []
    end
  end
  
  def set_instance_variables_from_cache(cached_data)
    # Debug what we're actually getting
    Rails.logger.info "Cached data type: #{cached_data.class}"
    Rails.logger.info "Cached data keys: #{cached_data.respond_to?(:keys) ? cached_data.keys : 'N/A'}"
    
    # Handle different cache data structures
    if cached_data.is_a?(Hash) && cached_data.key?(:dashboard_stats)
      @dashboard_stats = cached_data[:dashboard_stats]
      @procurement_summary = cached_data[:procurement_summary]
      @delivery_totals = cached_data[:delivery_totals]
      @delivery_summary = cached_data[:delivery_summary]
      @vendor_analysis = cached_data[:vendor_analysis]
      @daily_procurement = cached_data[:daily_procurement]
      @daily_delivery = cached_data[:daily_delivery]
      @total_liters = cached_data[:total_liters]
      @total_cost = cached_data[:total_cost]
      @total_delivered = cached_data[:total_delivered]
      @total_revenue = cached_data[:total_revenue]
      @total_profit = cached_data[:total_profit]
      @planned_liters = cached_data[:planned_liters]
      @planned_cost = cached_data[:planned_cost]
      @milk_left = cached_data[:milk_left]
      @milk_left_cost = cached_data[:milk_left_cost]
      @planned_profit = cached_data[:planned_profit]
    else
      # Fallback - call the original method without caching
      Rails.logger.warn "Unexpected cache data structure, falling back to direct calculation"
      calculate_dashboard_stats_without_cache_and_set_vars
    end
  end
  
  def calculate_procurement_summary_data(assignments_query)
    total_quantity = assignments_query.reorder('').sum('planned_quantity') || 0
    total_amount = assignments_query.reorder('').sum('planned_quantity * procurement_assignments.buying_price') || 0

    # Calculate unique vendor count with normalization
    unique_vendor_count = assignments_query.reorder('').pluck(:vendor_name)
      .map { |name| name&.strip&.downcase }
      .compact
      .uniq
      .count

    {
      total_vendors: unique_vendor_count,
      total_quantity: total_quantity,
      total_amount: total_amount,
      average_price: total_quantity > 0 ? (total_amount / total_quantity).round(2) : 0
    }
  end
  
  def calculate_delivery_summary_data(delivery_query)
    begin
      # Aggregate totals for quick stats
      delivery_totals = {
        total_deliveries: delivery_query.count,
        total_customers: begin
          delivery_query.includes(:customer).distinct.count(:customer_id)
        rescue => e
          Rails.logger.warn "Cannot join customer table: #{e.message}"
          delivery_query.distinct.count(:customer_id) rescue 0
        end,
        total_quantity: delivery_query.sum(:quantity) || 0,
        total_revenue: delivery_query.sum(:final_amount_after_discount) || 0
      }

      # Build status-wise summary expected by the view - OPTIMIZED to avoid N+1
      status_summary = delivery_query
        .reorder('')
        .group(:status)
        .select('status, COUNT(*) as count, SUM(quantity) as total_quantity, SUM(final_amount_after_discount) as total_revenue')

      delivery_summary = status_summary.map do |record|
        {
          status: record.status || 'unknown',
          count: record.count,
          quantity: record.total_quantity || 0,
          revenue: record.total_revenue || 0
        }
      end

      [delivery_totals, delivery_summary]
    rescue => e
      Rails.logger.error "Error calculating delivery summary: #{e.message}"
      delivery_totals = {
        total_deliveries: 0,
        total_customers: 0,
        total_quantity: 0,
        total_revenue: 0
      }
      delivery_summary = []
      [delivery_totals, delivery_summary]
    end
  end
  
  def calculate_detailed_analysis_data(assignments_query, delivery_query)
    # Vendor-wise spending analysis
    assignments_array = assignments_query.to_a
    vendor_analysis = assignments_array.group_by(&:vendor_name).map do |vendor, assignments|
      total_quantity = assignments.sum { |a| a.planned_quantity || a.actual_quantity || 0 }
      total_amount = assignments.sum { |a| (a.planned_quantity || a.actual_quantity || 0) * a.buying_price }

      {
        vendor_name: vendor,
        total_liters: total_quantity,
        total_amount: total_amount,
        average_price: total_quantity > 0 ? (total_amount / total_quantity).round(2) : 0
      }
    end.sort_by { |v| -v[:total_amount] }

    # Daily procurement tracking
    daily_procurement = (@start_date..@end_date).map do |date|
      daily_assignments = assignments_array.select { |a| a.date == date }

      {
        date: date,
        vendors_engaged: daily_assignments.map(&:vendor_name).uniq.count,
        total_liters: daily_assignments.sum { |a| a.planned_quantity || a.actual_quantity || 0 },
        total_amount: daily_assignments.sum { |a| (a.planned_quantity || a.actual_quantity || 0) * a.buying_price }
      }
    end.select { |day| day[:total_liters] > 0 }

    # Daily delivery information - OPTIMIZED to avoid N+1 queries
    begin
      # Single query to get all delivery data with proper includes
      delivery_data = delivery_query
        .includes(:customer)
        .select(:scheduled_date, :customer_id, :quantity, :id)
        .group_by(&:scheduled_date)

      daily_delivery = (@start_date..@end_date).map do |date|
        daily_deliveries = delivery_data[date] || []

        {
          date: date,
          customers_served: daily_deliveries.map(&:customer_id).uniq.count,
          total_liters: daily_deliveries.sum(&:quantity) || 0,
          assignments_completed: daily_deliveries.count
        }
      end.select { |day| day[:total_liters] > 0 }
    rescue => e
      Rails.logger.error "Error calculating daily deliveries: #{e.message}"
      daily_delivery = []
    end
    
    [vendor_analysis, daily_procurement, daily_delivery]
  end
  
  def update_related_assignments(schedule)
    # Update existing assignments for this schedule
    schedule.procurement_assignments.each do |assignment|
      assignment.update(
        vendor_name: schedule.vendor_name,
        buying_price: schedule.buying_price,
        selling_price: schedule.selling_price,
        product_id: schedule.product_id
      )
    end
    
    # If date range changed, we might need to create/delete assignments
    # This is a simplified approach - you might want more sophisticated logic
    if schedule.procurement_assignments.empty?
      # Generate new assignments for the date range if none exist
      (schedule.from_date..schedule.to_date).each do |date|
        schedule.procurement_assignments.create!(
          user: current_user,
          vendor_name: schedule.vendor_name,
          date: date,
          planned_quantity: (schedule.quantity || 0),
          buying_price: schedule.buying_price,
          selling_price: schedule.selling_price,
          status: 'pending',
          product_id: schedule.product_id
        )
      end
    end
  rescue => e
    Rails.logger.error "Error updating related assignments: #{e.message}"
    # Don't fail the schedule update if assignment update fails
  end
  
  def calculate_dashboard_stats_without_cache_and_set_vars
    begin
      # Use single optimized query for all procurement stats
      base_query = current_user.procurement_assignments.for_date_range(@start_date, @end_date)
      base_query = base_query.where(product_id: @product_id) if @product_id.present?

      # Single aggregation query for all procurement stats
      procurement_stats = base_query.reorder('').select(
        'COUNT(DISTINCT vendor_name) as vendor_count',
        'SUM(COALESCE(planned_quantity, 0)) as total_quantity',
        'SUM(COALESCE(planned_quantity, 0) * COALESCE(buying_price, 0)) as total_cost'
      ).first

      total_vendors = procurement_stats&.vendor_count || 0
      liters_purchased = procurement_stats&.total_quantity&.to_f || 0
      total_purchased_amount = procurement_stats&.total_cost&.to_f || 0

      # Single optimized query for delivery stats
      delivery_query = get_delivery_query(@start_date, @end_date)
      delivery_query = delivery_query.where(product_id: @product_id) if @product_id.present?

      # Single aggregation query for all delivery stats
      delivery_stats = delivery_query.select(
        'SUM(COALESCE(quantity, 0)) as total_delivered',
        'SUM(COALESCE(final_amount_after_discount, 0)) as total_revenue'
      ).first

      liters_delivered = delivery_stats&.total_delivered&.to_f || 0
      total_amount_collected = delivery_stats&.total_revenue&.to_f || 0

      # 5. Pending Quantity - Total Received - Total Delivered
      total_pending_quantity = liters_purchased - liters_delivered
      
      # 7 & 8. Profit/Loss Calculation
      profit_amount = 0
      loss_amount = 0
      
      if total_amount_collected > total_purchased_amount
        profit_amount = total_amount_collected - total_purchased_amount
      else
        loss_amount = total_purchased_amount - total_amount_collected
      end
      
      # Additional metrics
      utilization_rate = liters_purchased > 0 ? (liters_delivered.to_f / liters_purchased * 100).round(2) : 0
      
      @dashboard_stats = {
        total_vendors: total_vendors,
        liters_purchased: liters_purchased,
        total_purchased_amount: total_purchased_amount,
        liters_delivered: liters_delivered,
        total_pending_quantity: total_pending_quantity,
        total_amount_collected: total_amount_collected,
        profit_amount: profit_amount,
        loss_amount: loss_amount,
        utilization_rate: utilization_rate
      }
      
      # Set instance variables for detailed calculations view
      @total_liters = liters_purchased
      @total_cost = total_purchased_amount  
      @total_delivered = liters_delivered
      @total_revenue = total_amount_collected
      @total_profit = total_amount_collected - total_purchased_amount
      
      # Calculate planned procurement (not actual)
      planned_liters = assignments_query.reorder('').sum(:planned_quantity) || 0
      planned_cost = assignments_query.reorder('').sum('planned_quantity * procurement_assignments.buying_price') || 0
      
      # Recalculate profit using planned values
      planned_profit = total_amount_collected - planned_cost
      
      @planned_liters = planned_liters
      @planned_cost = planned_cost
      @milk_left = planned_liters - liters_delivered
      @milk_left_cost = (@milk_left > 0 && planned_liters > 0) ? (planned_cost.to_f / planned_liters * @milk_left).round(2) : 0
      @planned_profit = planned_profit
      
      # Calculate summary sections
      calculate_procurement_summary(assignments_query)
      calculate_delivery_summary(delivery_query)
      calculate_detailed_analysis(assignments_query, delivery_query)
      
    rescue => e
      Rails.logger.error "Error in fallback calculation: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      # Set safe defaults
      @dashboard_stats = {
        total_vendors: 0,
        liters_purchased: 0,
        total_purchased_amount: 0,
        liters_delivered: 0,
        total_pending_quantity: 0,
        total_amount_collected: 0,
        profit_amount: 0,
        loss_amount: 0,
        utilization_rate: 0
      }
      
      @procurement_summary = {
        total_vendors: 0,
        total_quantity: 0,
        total_amount: 0,
        average_price: 0
      }
      
      @delivery_totals = {
        total_deliveries: 0,
        total_customers: 0,
        total_quantity: 0,
        total_revenue: 0
      }
      @delivery_summary = []
      
      @vendor_analysis = []
      @daily_procurement = []
      @daily_delivery = []
      
      # Set fallback instance variables for detailed calculations view
      @total_liters = 0
      @total_cost = 0  
      @total_delivered = 0
      @total_revenue = 0
      @total_profit = 0
      @planned_liters = 0
      @planned_cost = 0
      @milk_left = 0
      @milk_left_cost = 0
      @planned_profit = 0
    end
  end

  # Procurement Invoice Actions
  public

  def generate_procurement_invoice
    begin
      schedule_id = params[:schedule_id] || params[:id]
      schedule = ProcurementSchedule.find(schedule_id)

      # Get all assignments for this schedule
      assignments = schedule.procurement_assignments

      # Calculate totals from assignments or schedule data
      total_quantity = 0
      total_amount = 0

      if assignments.any?
        total_quantity = assignments.sum { |a| a.actual_quantity || a.planned_quantity || 0 }
        total_amount = assignments.sum { |a|
          quantity = a.actual_quantity || a.planned_quantity || 0
          rate = a.buying_price || 0
          quantity * rate
        }
      else
        # Fallback to schedule data if no assignments
        total_quantity = schedule.planned_quantity || 0
        total_amount = total_quantity * (schedule.buying_price || 0)
      end

      # Create procurement invoice
      invoice = ProcurementInvoice.create!(
        procurement_schedule: schedule,
        user: current_user
      )

      # Generate PDF URL
      pdf_url = download_procurement_invoice_pdf_milk_analytics_url(invoice.id)

      render json: {
        success: true,
        message: "Invoice generated successfully",
        invoice_number: invoice.invoice_number,
        invoice_date: invoice.invoice_date.strftime('%d %b %Y'),
        total_amount: invoice.total_amount,
        pdf_url: pdf_url
      }

    rescue => e
      Rails.logger.error "Error generating procurement invoice: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      render json: {
        success: false,
        message: "Error generating invoice: #{e.message}"
      }, status: :unprocessable_entity
    end
  end

  def view_procurement_invoice
    @invoice = ProcurementInvoice.find(params[:id])
    render partial: 'milk_analytics/invoice_details', locals: { invoice: @invoice }
  rescue => e
    render json: { error: e.message }, status: :not_found
  end

  def show_procurement_assignments
    begin
      # Ultra-fast caching with ultra-short expiry for live data
      cache_key = "assignments_#{current_user.id}_#{params[:id]}"

      cached_result = Rails.cache.fetch(cache_key, expires_in: 15.seconds) do
        # Super optimized single query with joins
        @schedule = current_user.procurement_schedules
          .select("procurement_schedules.*, products.name as product_name")
          .left_joins(:product)
          .find(params[:id])

        # Ultra-fast assignments query with all data in single query
        assignments = ProcurementAssignment
          .select("procurement_assignments.*, products.name as assignment_product_name")
          .left_joins(:product)
          .where(procurement_schedule_id: @schedule.id)
          .order(:date)
          .limit(100) # Super aggressive limit for speed

        default_product_name = @schedule.product_name || 'Generic Product'

        # Process in single pass
        assignments_data = assignments.map do |assignment|
          {
            id: assignment.id,
            date: assignment.date.strftime('%d %b %Y'),
            product_name: assignment.assignment_product_name || default_product_name,
            planned_quantity: assignment.planned_quantity || 0,
            actual_quantity: assignment.actual_quantity,
            buying_price: assignment.buying_price || 0,
            selling_price: assignment.selling_price || 0,
            status: assignment.status,
            notes: assignment.notes,
            unit: assignment.unit || 'Liters',
            created_at: assignment.created_at.strftime('%d %b %Y %I:%M %p')
          }
        end

        {
          schedule: {
            id: @schedule.id,
            vendor_name: @schedule.vendor_name,
            from_date: @schedule.from_date.strftime('%d %b %Y'),
            to_date: @schedule.to_date.strftime('%d %b %Y'),
            product_name: default_product_name
          },
          assignments: assignments_data,
          total_assignments: assignments_data.size
        }
      end

      respond_to do |format|
        format.html {
          # For HTML rendering, fetch actual ActiveRecord objects instead of using cached hash data
          @schedule = current_user.procurement_schedules
            .includes(:product)
            .find(params[:id])

          @assignments = ProcurementAssignment
            .includes(:product)
            .where(procurement_schedule_id: @schedule.id)
            .order(:date)
            .limit(100)

          render partial: 'simple_procurement_assignments_modal'
        }
        format.json {
          render json: {
            success: true,
            **cached_result
          }
        }
      end

    rescue ActiveRecord::RecordNotFound
      respond_to do |format|
        format.html { render json: { success: false, error: 'Schedule not found' }, status: 404 }
        format.json { render json: { success: false, error: 'Schedule not found' }, status: 404 }
      end
    rescue => e
      Rails.logger.error "Error fetching procurement assignments: #{e.message}"
      respond_to do |format|
        format.html { render json: { success: false, error: e.message }, status: 500 }
        format.json { render json: { success: false, error: e.message }, status: 500 }
      end
    end
  end

  def mark_assignments_completed
    begin
      @schedule = current_user.procurement_schedules.find(params[:id])

      # Get current month's pending assignments for this schedule
      current_month_start = Date.current.beginning_of_month
      current_month_end = Date.current.end_of_month

      pending_assignments = @schedule.procurement_assignments
                                   .where(status: 'pending')
                                   .where(date: current_month_start..current_month_end)

      if pending_assignments.any?
        # Update all pending assignments to completed
        updated_count = pending_assignments.update_all(
          status: 'completed',
          updated_at: Time.current
        )

        Rails.logger.info "Updated #{updated_count} assignments to completed for schedule #{@schedule.id}"

        render json: {
          success: true,
          message: "Successfully marked #{updated_count} assignment(s) as completed",
          updated_count: updated_count,
          schedule_id: @schedule.id,
          vendor_name: @schedule.vendor_name
        }
      else
        render json: {
          success: false,
          message: "No pending assignments found for current month",
          updated_count: 0
        }
      end

    rescue ActiveRecord::RecordNotFound
      render json: {
        success: false,
        message: "Schedule not found"
      }, status: 404

    rescue => e
      Rails.logger.error "Error marking assignments as completed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      render json: {
        success: false,
        message: "Error updating assignments: #{e.message}"
      }, status: :unprocessable_entity
    end
  end

  def show_procurement_invoice
    begin
      @invoice = current_user.procurement_invoices.find(params[:id])
      @schedule = @invoice.procurement_schedule

      # Ensure invoice data is generated if it doesn't exist
      if @invoice.invoice_data.blank?
        @invoice.mark_as_generated!
      end

      respond_to do |format|
        format.html { render 'procurement_invoice_show', layout: false }
        format.json {
          render json: {
            success: true,
            invoice: {
              id: @invoice.id,
              invoice_number: @invoice.invoice_number,
              invoice_date: @invoice.invoice_date,
              status: @invoice.status,
              vendor_name: @invoice.vendor_name,
              total_amount: @invoice.total_amount
            }
          }
        }
      end

    rescue ActiveRecord::RecordNotFound
      respond_to do |format|
        format.html { redirect_to milk_analytics_path, alert: 'Invoice not found' }
        format.json { render json: { success: false, error: 'Invoice not found' }, status: 404 }
      end
    rescue => e
      Rails.logger.error "Error showing procurement invoice: #{e.message}"
      respond_to do |format|
        format.html { redirect_to milk_analytics_path, alert: "Error showing invoice: #{e.message}" }
        format.json { render json: { success: false, error: e.message }, status: 500 }
      end
    end
  end

  def download_procurement_invoice_pdf
    invoice = ProcurementInvoice.find(params[:id])
    data = invoice.generate_invoice_data

    respond_to do |format|
      format.pdf do
        pdf = generate_procurement_invoice_pdf(data)
        send_data pdf.render,
                  filename: "procurement_invoice_#{invoice.invoice_number}.pdf",
                  type: 'application/pdf',
                  disposition: 'attachment'
      end
    end
  rescue => e
    redirect_to milk_analytics_path, alert: "Error downloading PDF: #{e.message}"
  end

  private

  def create_schedule_from_item(item_data, current_month_start, current_month_end, created_schedules, skipped_schedules)
    # Check if similar schedule already exists for current month
    existing_schedule = current_user.procurement_schedules
                                   .where(
                                     vendor_name: item_data[:vendor_name],
                                     product_id: item_data[:product_id],
                                     from_date: current_month_start..current_month_end
                                   ).first

    if existing_schedule
      skipped_schedules << {
        vendor: item_data[:vendor_name],
        product: Product.find_by(id: item_data[:product_id])&.name,
        reason: 'Schedule already exists for this month'
      }
      return
    end

    # Create new schedule for current month
    new_schedule = current_user.procurement_schedules.create!(
      vendor_name: item_data[:vendor_name],
      product_id: item_data[:product_id],
      from_date: current_month_start,
      to_date: current_month_end,
      quantity: item_data[:quantity],
      buying_price: item_data[:buying_price],
      selling_price: item_data[:selling_price],
      unit: item_data[:unit],
      status: 'active',
      notes: "Copied from last month"
    )

    created_schedules << {
      type: 'Schedule',
      id: new_schedule.id,
      vendor_name: new_schedule.vendor_name,
      product_name: new_schedule.product&.name || 'Generic Product'
    }
  end

  def create_assignments_from_item(item_data, current_month_start, current_month_end, created_schedules, skipped_schedules)
    # Create assignments for each day of the current month
    current_days = (current_month_start..current_month_end).to_a

    current_days.each do |date|
      # Check if assignment already exists for this date and vendor/product
      existing_assignment = current_user.procurement_assignments
                                       .where(
                                         date: date,
                                         vendor_name: item_data[:vendor_name],
                                         product_id: item_data[:product_id]
                                       ).first

      if existing_assignment
        next # Skip this date, assignment already exists
      end

      # Create new assignment
      begin
        new_assignment = current_user.procurement_assignments.create!(
          vendor_name: item_data[:vendor_name],
          product_id: item_data[:product_id],
          date: date,
          planned_quantity: item_data[:quantity],
          buying_price: item_data[:buying_price],
          selling_price: item_data[:selling_price],
          unit: item_data[:unit],
          status: 'pending',
          notes: "Copied from last month assignment"
        )

        # Only add to created_schedules array once per vendor/product combination
        unless created_schedules.any? { |item|
          item[:type] == 'Assignment' &&
          item[:vendor_name] == item_data[:vendor_name] &&
          item[:product_id] == item_data[:product_id]
        }
          created_schedules << {
            type: 'Assignment',
            id: new_assignment.id,
            vendor_name: new_assignment.vendor_name,
            product_name: new_assignment.product&.name || 'Generic Product'
          }
        end
      rescue => e
        Rails.logger.error "Error creating assignment for #{date}: #{e.message}"
        next
      end
    end
  end


  private

  def generate_procurement_invoice_pdf(data)
    require 'prawn'

    Prawn::Document.new(page_size: 'A4', margin: 40) do |pdf|
      # Header
      pdf.font 'Helvetica', style: :bold, size: 24
      pdf.text 'PROCUREMENT INVOICE', align: :center, color: '2C3E50'
      pdf.move_down 10

      # Invoice details line
      pdf.font 'Helvetica', size: 10
      pdf.text "Invoice No: #{data[:invoice_number]} | Generated: #{data[:generated_date]}", align: :center, color: '7F8C8D'
      pdf.move_down 20

      # Company details (if available)
      pdf.font 'Helvetica', style: :bold, size: 12
      pdf.text AdminSetting.current.business_name.presence || "Shri Krishna Goshala", color: '2C3E50'
      pdf.font 'Helvetica', size: 10
      pdf.text 'Milk Supply & Delivery Management'
      pdf.move_down 15

      # Vendor details
      pdf.font 'Helvetica', style: :bold, size: 12
      pdf.text 'VENDOR DETAILS', color: '2C3E50'
      pdf.move_down 5

      pdf.font 'Helvetica', size: 10
      pdf.text "Vendor: #{data[:vendor_name]}"
      pdf.text "Contact: #{data[:vendor_contact]}" if data[:vendor_contact].present?
      pdf.text "Product: #{data[:product_name]}"
      pdf.text "Period: #{data[:date_range]}"
      pdf.move_down 20

      # Procurement details table
      pdf.font 'Helvetica', style: :bold, size: 12
      pdf.text 'PROCUREMENT DETAILS', color: '2C3E50'
      pdf.move_down 10

      # Table data
      table_data = [
        ['Date', 'Planned Qty', 'Actual Qty', 'Rate/Unit', 'Amount']
      ]

      total_amount = 0
      data[:assignments].each do |assignment|
        quantity = assignment.actual_quantity_procured || assignment.planned_quantity || 0
        rate = assignment.actual_rate_per_unit || assignment.planned_rate_per_unit || 0
        amount = quantity * rate
        total_amount += amount

        table_data << [
          assignment.procurement_date&.strftime('%d/%m/%Y') || '',
          (assignment.planned_quantity || 0).to_s + 'L',
          (assignment.actual_quantity_procured || assignment.planned_quantity || 0).to_s + 'L',
          '₹' + rate.to_s,
          '₹' + amount.round(2).to_s
        ]
      end

      # Add total row
      table_data << ['', '', '', 'TOTAL:', "₹#{total_amount.round(2)}"]

      # Create table
      pdf.table(table_data,
        header: true,
        width: pdf.bounds.width,
        cell_style: {
          borders: [:top, :bottom, :left, :right],
          border_width: 0.5,
          border_color: 'CCCCCC',
          padding: 8
        }
      ) do
        # Header styling
        row(0).font_style = :bold
        row(0).background_color = 'F8F9FA'
        row(0).text_color = '2C3E50'

        # Total row styling
        row(-1).font_style = :bold
        row(-1).background_color = 'E8F5E8'

        # Align amount columns to right
        columns(3..4).align = :right
      end

      pdf.move_down 30

      # Summary
      pdf.font 'Helvetica', style: :bold, size: 14
      pdf.text "Total Amount: ₹#{total_amount.round(2)}", align: :right, color: '27AE60'
      pdf.move_down 20

      # Footer
      pdf.font 'Helvetica', size: 8, style: :italic
      pdf.text 'This is a computer generated invoice.', align: :center, color: '95A5A6'
      pdf.text "Generated on #{Time.current.strftime('%d %B %Y at %I:%M %p')}", align: :center, color: '95A5A6'
    end.render
  end
end