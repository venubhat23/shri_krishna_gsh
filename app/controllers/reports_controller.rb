# app/controllers/reports_controller.rb
class ReportsController < ApplicationController
  before_action :require_login
  
  def index
    @reports = Report.where(user: current_user).order(created_at: :desc) if defined?(Report)
    @reports ||= []
  end
  
  def generate_gst_report
    from_date = params[:from_date]
    to_date = params[:to_date]

    if from_date.blank? || to_date.blank?
      render json: {
        success: false,
        message: "Please select both from and to dates"
      }
      return
    end

    begin
      # Create a new report record
      report = create_report_record(from_date, to_date, 'gst')

      render json: {
        success: true,
        message: "GST Report generated successfully",
        report: {
          id: report.id,
          name: report.name,
          generated_at: report.created_at.strftime("%B %d, %Y at %I:%M %p"),
          from_date: from_date,
          to_date: to_date
        }
      }
    rescue => e
      render json: {
        success: false,
        message: "Failed to generate report: #{e.message}"
      }
    end
  end

  def generate_sales_report
    from_date = params[:from_date]
    to_date = params[:to_date]

    if from_date.blank? || to_date.blank?
      render json: {
        success: false,
        message: "Please select both from and to dates"
      }
      return
    end

    begin
      report = create_report_record(from_date, to_date, 'sales')

      render json: {
        success: true,
        message: "Sales Report generated successfully",
        report: {
          id: report.id,
          name: report.name,
          generated_at: report.created_at.strftime("%B %d, %Y at %I:%M %p"),
          from_date: from_date,
          to_date: to_date
        }
      }
    rescue => e
      render json: {
        success: false,
        message: "Failed to generate report: #{e.message}"
      }
    end
  end

  def generate_delivery_report
    from_date = params[:from_date]
    to_date = params[:to_date]

    if from_date.blank? || to_date.blank?
      render json: {
        success: false,
        message: "Please select both from and to dates"
      }
      return
    end

    begin
      report = create_report_record(from_date, to_date, 'delivery')

      render json: {
        success: true,
        message: "Delivery Report generated successfully",
        report: {
          id: report.id,
          name: report.name,
          generated_at: report.created_at.strftime("%B %d, %Y at %I:%M %p"),
          from_date: from_date,
          to_date: to_date
        }
      }
    rescue => e
      render json: {
        success: false,
        message: "Failed to generate report: #{e.message}"
      }
    end
  end

  def generate_customer_report
    from_date = params[:from_date]
    to_date = params[:to_date]

    if from_date.blank? || to_date.blank?
      render json: {
        success: false,
        message: "Please select both from and to dates"
      }
      return
    end

    begin
      report = create_report_record(from_date, to_date, 'customer')

      render json: {
        success: true,
        message: "Customer Report generated successfully",
        report: {
          id: report.id,
          name: report.name,
          generated_at: report.created_at.strftime("%B %d, %Y at %I:%M %p"),
          from_date: from_date,
          to_date: to_date
        }
      }
    rescue => e
      render json: {
        success: false,
        message: "Failed to generate report: #{e.message}"
      }
    end
  end

  def generate_product_report
    from_date = params[:from_date]
    to_date = params[:to_date]

    if from_date.blank? || to_date.blank?
      render json: {
        success: false,
        message: "Please select both from and to dates"
      }
      return
    end

    begin
      report = create_report_record(from_date, to_date, 'product')

      render json: {
        success: true,
        message: "Product Performance Report generated successfully",
        report: {
          id: report.id,
          name: report.name,
          generated_at: report.created_at.strftime("%B %d, %Y at %I:%M %p"),
          from_date: from_date,
          to_date: to_date
        }
      }
    rescue => e
      render json: {
        success: false,
        message: "Failed to generate report: #{e.message}"
      }
    end
  end

  def generate_financial_report
    from_date = params[:from_date]
    to_date = params[:to_date]

    if from_date.blank? || to_date.blank?
      render json: {
        success: false,
        message: "Please select both from and to dates"
      }
      return
    end

    begin
      report = create_report_record(from_date, to_date, 'financial')

      render json: {
        success: true,
        message: "Financial Summary Report generated successfully",
        report: {
          id: report.id,
          name: report.name,
          generated_at: report.created_at.strftime("%B %d, %Y at %I:%M %p"),
          from_date: from_date,
          to_date: to_date
        }
      }
    rescue => e
      render json: {
        success: false,
        message: "Failed to generate report: #{e.message}"
      }
    end
  end

  def generate_enhanced_sales_report
    from_date = params[:from_date]
    to_date = params[:to_date]

    if from_date.blank? || to_date.blank?
      render json: {
        success: false,
        message: "Please select both from and to dates"
      }
      return
    end

    begin
      report = create_report_record(from_date, to_date, 'enhanced_sales')

      render json: {
        success: true,
        message: "Enhanced Sales Report generated successfully",
        report: {
          id: report.id,
          name: report.name,
          generated_at: report.created_at.strftime("%B %d, %Y at %I:%M %p"),
          from_date: from_date,
          to_date: to_date
        }
      }
    rescue => e
      render json: {
        success: false,
        message: "Failed to generate report: #{e.message}"
      }
    end
  end
  
  def show
    @report = find_report

    if @report.nil?
      redirect_to reports_path, alert: "Report not found"
      return
    end

    from_date = @report.respond_to?(:from_date) ? @report.from_date : Date.parse(params[:from_date] || 1.month.ago.to_s)
    to_date = @report.respond_to?(:to_date) ? @report.to_date : Date.parse(params[:to_date] || Date.current.to_s)

    # Generate appropriate report data based on report type
    report_type = @report.respond_to?(:report_type) ? @report.report_type : 'gst'

    case report_type
    when 'gst'
      @report_data = get_gst_report_data(from_date, to_date)
    when 'sales'
      @report_data = get_sales_report_data(from_date, to_date)
    when 'enhanced_sales'
      @report_data = get_enhanced_sales_report_data(from_date, to_date)
    when 'delivery'
      @report_data = get_delivery_report_data(from_date, to_date)
    when 'customer'
      @report_data = get_customer_report_data(from_date, to_date)
    when 'product'
      @report_data = get_product_report_data(from_date, to_date)
    when 'financial'
      @report_data = get_financial_report_data(from_date, to_date)
    else
      @report_data = get_gst_report_data(from_date, to_date)
    end

    @from_date = from_date
    @to_date = to_date
    @report_type = report_type

    respond_to do |format|
      format.html
      format.json { render json: @report_data }
      format.csv { send_csv_report(@report_data, @report_type, @from_date, @to_date) }
    end
  end

  def download_pdf
    report = find_report

    if report.nil?
      redirect_to reports_path, alert: "Report not found"
      return
    end

    # Generate PDF content based on report type
    html_content = case report.report_type
                   when 'enhanced_sales'
                     generate_enhanced_sales_pdf_content(report)
                   when 'sales'
                     generate_sales_pdf_content(report)
                   when 'delivery'
                     generate_delivery_pdf_content(report)
                   when 'customer'
                     generate_customer_pdf_content(report)
                   when 'product'
                     generate_product_pdf_content(report)
                   when 'financial'
                     generate_financial_pdf_content(report)
                   else
                     generate_gst_pdf_content(report)
                   end

    respond_to do |format|
      format.pdf do
        render html: html_content.html_safe, layout: false
      end
      format.html do
        render html: html_content.html_safe, layout: false
      end
    end
  end
  
  private

  def send_csv_report(report_data, report_type, from_date, to_date)
    require 'csv'

    filename = "#{report_type}_report_#{from_date.strftime('%Y%m%d')}_to_#{to_date.strftime('%Y%m%d')}.csv"

    csv_data = case report_type
    when 'enhanced_sales'
      generate_enhanced_sales_csv(report_data)
    when 'gst'
      generate_gst_csv(report_data)
    when 'sales'
      generate_sales_csv(report_data)
    when 'delivery'
      generate_delivery_csv(report_data)
    when 'customer'
      generate_customer_csv(report_data)
    when 'product'
      generate_product_csv(report_data)
    when 'financial'
      generate_financial_csv(report_data)
    else
      generate_default_csv(report_data)
    end

    send_data csv_data, filename: filename, type: 'text/csv'
  end

  def generate_enhanced_sales_csv(report_data)
    CSV.generate(headers: true) do |csv|
      # Add header row with GST columns
      csv << ['Customer Name', 'Customer Number', 'Customer Address', 'Invoice Number', 'Invoice Date', 'Number of Assignments', 'Total Amount', 'Total GST', 'CGST', 'SGST', 'IGST']

      # Add data rows with GST information
      report_data[:detailed_sales].each do |sale|
        csv << [
          sale[:customer_name],
          sale[:customer_number],
          sale[:customer_address],
          sale[:invoice_number],
          sale[:invoice_date],
          sale[:assignment_count],
          sale[:total_amount],
          sale[:total_gst] || 0,
          sale[:cgst] || 0,
          sale[:sgst] || 0,
          sale[:igst] || 0
        ]
      end

      # Add summary row with GST totals
      csv << []
      csv << ['SUMMARY']
      csv << ['Report Period', report_data[:summary][:period]]
      csv << ['Report Month', "#{report_data[:summary][:report_month]} #{report_data[:summary][:report_year]}"]
      csv << ['Total Invoices', report_data[:summary][:total_invoices]]
      csv << ['Total Assignments', report_data[:summary][:total_assignments]]
      csv << ['Total Invoice Amount', report_data[:summary][:total_invoice_amount]]
      csv << ['Average Invoice Value', report_data[:summary][:average_invoice_value]]
      csv << ['Total GST Amount', report_data[:summary][:total_gst] || 0]
      csv << ['Total CGST', report_data[:summary][:total_cgst] || 0]
      csv << ['Total SGST', report_data[:summary][:total_sgst] || 0]
      csv << ['Total IGST', report_data[:summary][:total_igst] || 0]
    end
  end

  def generate_gst_csv(report_data)
    CSV.generate(headers: true) do |csv|
      csv << ['Customer Name', 'State Code', 'State Name', 'Invoice Number', 'Invoice Date', 'Invoice Value', 'Tax Rate %', 'Taxable Value', 'Central Tax', 'State Tax', 'Integrated Tax', 'CESS', 'Total Tax']

      report_data[:sales_transactions].each do |transaction|
        csv << [
          transaction[:customer_name],
          transaction[:state_code],
          transaction[:state_name],
          transaction[:invoice_no],
          transaction[:invoice_date],
          transaction[:invoice_value],
          transaction[:tax_rate],
          transaction[:taxable_value],
          transaction[:central_tax],
          transaction[:state_tax],
          transaction[:integrated_tax],
          transaction[:cess],
          transaction[:total_tax]
        ]
      end
    end
  end

  def generate_sales_csv(report_data)
    CSV.generate(headers: true) do |csv|
      csv << ['Invoice Number', 'Customer Name', 'Date', 'Amount', 'Status']

      report_data[:invoices].each do |invoice|
        csv << [
          invoice[:invoice_number],
          invoice[:customer_name],
          invoice[:date],
          invoice[:amount],
          invoice[:status]
        ]
      end
    end
  end

  def generate_delivery_csv(report_data)
    CSV.generate(headers: true) do |csv|
      csv << ['Delivery Person', 'Total Assignments', 'Completed', 'Completion Rate %']

      report_data[:delivery_people_performance].each do |person|
        csv << [
          person[:delivery_person],
          person[:total_assignments],
          person[:completed],
          person[:completion_rate]
        ]
      end
    end
  end

  def generate_customer_csv(report_data)
    CSV.generate(headers: true) do |csv|
      csv << ['Customer Name', 'Phone', 'Total Sales', 'Total Deliveries', 'Last Order Date']

      report_data[:top_customers].each do |customer|
        csv << [
          customer[:name],
          customer[:phone],
          customer[:total_sales],
          customer[:total_deliveries],
          customer[:last_order_date]
        ]
      end
    end
  end

  def generate_product_csv(report_data)
    CSV.generate(headers: true) do |csv|
      csv << ['Product Name', 'Quantity Sold', 'Total Revenue', 'Average Price']

      report_data[:products].each do |product|
        csv << [
          product[:name],
          product[:quantity_sold],
          product[:total_revenue],
          product[:average_price]
        ]
      end
    end
  end

  def generate_financial_csv(report_data)
    CSV.generate(headers: true) do |csv|
      csv << ['Month', 'Sales', 'Purchases', 'Profit']

      report_data[:monthly_breakdown].each do |month_data|
        csv << [
          month_data[:month],
          month_data[:sales],
          month_data[:purchases],
          month_data[:profit]
        ]
      end
    end
  end

  def generate_default_csv(report_data)
    CSV.generate(headers: true) do |csv|
      csv << ['Data']
      csv << ['No specific CSV format defined for this report type']
    end
  end

  def number_with_delimiter(number)
    # Simple number formatting helper
    return "0.0" if number.nil? || number == 0
    sprintf("%.2f", number).gsub(/(\d)(?=(\d{3})+(?!\d))/, '\1,')
  end
  
  def find_report
    if defined?(Report)
      Report.find_by(id: params[:id], user: current_user)
    else
      # Fallback for demo purposes
      OpenStruct.new(
        id: params[:id],
        name: "GST Report #{params[:id]}",
        from_date: 1.month.ago.to_date,
        to_date: Date.current,
        created_at: Time.current
      )
    end
  end
  
  def create_report_record(from_date, to_date, report_type = 'gst')
    report_names = {
      'gst' => 'GST Report',
      'sales' => 'Sales Report',
      'enhanced_sales' => 'Enhanced Sales Report',
      'delivery' => 'Delivery Report',
      'customer' => 'Customer Report',
      'product' => 'Product Performance Report',
      'financial' => 'Financial Summary Report'
    }

    name = "#{report_names[report_type] || 'Report'} - #{Date.parse(from_date).strftime('%b %d')} to #{Date.parse(to_date).strftime('%b %d, %Y')}"

    if defined?(Report)
      Report.create!(
        name: name,
        report_type: report_type,
        from_date: Date.parse(from_date),
        to_date: Date.parse(to_date),
        user: current_user
      )
    else
      # Fallback for demo purposes
      OpenStruct.new(
        id: rand(1000..9999),
        name: name,
        report_type: report_type,
        from_date: Date.parse(from_date),
        to_date: Date.parse(to_date),
        created_at: Time.current,
        user: current_user
      )
    end
  end
  
  def generate_enhanced_sales_pdf_content(report)
    # Generate Enhanced Sales report data
    from_date = report.respond_to?(:from_date) ? report.from_date : Date.parse(params[:from_date] || 1.month.ago.to_s)
    to_date = report.respond_to?(:to_date) ? report.to_date : Date.parse(params[:to_date] || Date.current.to_s)
    report_data = get_enhanced_sales_report_data(from_date, to_date)

    # Generate HTML content for Enhanced Sales PDF
    html_content = generate_enhanced_sales_pdf_html(report, report_data, from_date, to_date)

    # Return HTML content that can be converted to PDF by the browser
    html_content
  end

  def generate_gst_pdf_content(report)
    # Generate GST report data
    from_date = report.respond_to?(:from_date) ? report.from_date : Date.parse(params[:from_date] || 1.month.ago.to_s)
    to_date = report.respond_to?(:to_date) ? report.to_date : Date.parse(params[:to_date] || Date.current.to_s)
    gst_data = get_gst_report_data(from_date, to_date)

    # Generate HTML content for PDF with proper table formatting
    html_content = generate_pdf_html_table(report, gst_data, from_date, to_date)

    # Return HTML content that can be converted to PDF by the browser
    html_content
  end

  def generate_sales_pdf_content(report)
    # Generate Sales report data
    from_date = report.respond_to?(:from_date) ? report.from_date : Date.parse(params[:from_date] || 1.month.ago.to_s)
    to_date = report.respond_to?(:to_date) ? report.to_date : Date.parse(params[:to_date] || Date.current.to_s)
    report_data = get_sales_report_data(from_date, to_date)

    # For now, fallback to GST format - can be customized later
    generate_pdf_html_table(report, report_data, from_date, to_date)
  end

  def generate_delivery_pdf_content(report)
    # Generate Delivery report data
    from_date = report.respond_to?(:from_date) ? report.from_date : Date.parse(params[:from_date] || 1.month.ago.to_s)
    to_date = report.respond_to?(:to_date) ? report.to_date : Date.parse(params[:to_date] || Date.current.to_s)
    report_data = get_delivery_report_data(from_date, to_date)

    # For now, fallback to GST format - can be customized later
    generate_pdf_html_table(report, report_data, from_date, to_date)
  end

  def generate_customer_pdf_content(report)
    # Generate Customer report data
    from_date = report.respond_to?(:from_date) ? report.from_date : Date.parse(params[:from_date] || 1.month.ago.to_s)
    to_date = report.respond_to?(:to_date) ? report.to_date : Date.parse(params[:to_date] || Date.current.to_s)
    report_data = get_customer_report_data(from_date, to_date)

    # For now, fallback to GST format - can be customized later
    generate_pdf_html_table(report, report_data, from_date, to_date)
  end

  def generate_product_pdf_content(report)
    # Generate Product report data
    from_date = report.respond_to?(:from_date) ? report.from_date : Date.parse(params[:from_date] || 1.month.ago.to_s)
    to_date = report.respond_to?(:to_date) ? report.to_date : Date.parse(params[:to_date] || Date.current.to_s)
    report_data = get_product_report_data(from_date, to_date)

    # For now, fallback to GST format - can be customized later
    generate_pdf_html_table(report, report_data, from_date, to_date)
  end

  def generate_financial_pdf_content(report)
    # Generate Financial report data
    from_date = report.respond_to?(:from_date) ? report.from_date : Date.parse(params[:from_date] || 1.month.ago.to_s)
    to_date = report.respond_to?(:to_date) ? report.to_date : Date.parse(params[:to_date] || Date.current.to_s)
    report_data = get_financial_report_data(from_date, to_date)

    # For now, fallback to GST format - can be customized later
    generate_pdf_html_table(report, report_data, from_date, to_date)
  end

  def generate_enhanced_sales_pdf_html(report, report_data, from_date, to_date)
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <title>Enhanced Sales Report - #{AdminSetting.current.business_name}</title>
        <style>
          body { font-family: Arial, sans-serif; margin: 20px; }
          .header { text-align: center; margin-bottom: 30px; }
          .company-name { font-size: 24px; font-weight: bold; color: #333; }
          .report-title { font-size: 18px; color: #666; margin: 10px 0; }
          .report-details { font-size: 14px; color: #888; }
          .summary { margin: 20px 0; padding: 15px; background-color: #f5f5f5; border-radius: 5px; }
          .summary h3 { margin: 0 0 10px 0; color: #333; }
          .summary-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 10px; }
          .summary-item { text-align: center; }
          .summary-value { font-size: 18px; font-weight: bold; color: #007bff; }
          .summary-label { font-size: 12px; color: #666; }
          table { width: 100%; border-collapse: collapse; margin-top: 20px; }
          th { background-color: #343a40; color: white; padding: 12px 8px; text-align: left; font-size: 12px; }
          td { padding: 10px 8px; border-bottom: 1px solid #dee2e6; font-size: 11px; }
          .text-right { text-align: right; }
          .text-center { text-align: center; }
          .amount { font-weight: bold; color: #28a745; }
          .customer-name { font-weight: bold; }
          .address { color: #666; max-width: 150px; word-wrap: break-word; }
          .footer { margin-top: 30px; text-align: center; font-size: 12px; color: #666; }
          .total-row { background-color: #f8f9fa; font-weight: bold; }
        </style>
      </head>
      <body>
        <div class="header">
          <div class="company-name">Enhanced Sales Report - #{AdminSetting.current.business_name}</div>
          <div class="report-title">Mobile: 9972808044</div>
          <div class="report-details">
            Date Range: #{from_date.strftime('%d/%m/%Y')} to #{to_date.strftime('%d/%m/%Y')}<br>
            Report Month: #{report_data[:summary][:report_month]} #{report_data[:summary][:report_year]}<br>
            Generated On: #{Time.current.strftime('%d/%m/%Y at %I:%M %p')}
          </div>
        </div>

        <div class="summary">
          <h3>Summary</h3>
          <div class="summary-grid">
            <div class="summary-item">
              <div class="summary-value">#{report_data[:summary][:total_invoices]}</div>
              <div class="summary-label">Total Invoices</div>
            </div>
            <div class="summary-item">
              <div class="summary-value">#{report_data[:summary][:total_assignments]}</div>
              <div class="summary-label">Total Assignments</div>
            </div>
            <div class="summary-item">
              <div class="summary-value">₹#{number_with_delimiter(report_data[:summary][:total_invoice_amount])}</div>
              <div class="summary-label">Total Amount</div>
            </div>
            <div class="summary-item">
              <div class="summary-value">₹#{number_with_delimiter(report_data[:summary][:average_invoice_value])}</div>
              <div class="summary-label">Average Invoice</div>
            </div>
            <div class="summary-item">
              <div class="summary-value">₹#{number_with_delimiter(report_data[:summary][:total_gst] || 0)}</div>
              <div class="summary-label">Total GST</div>
            </div>
            <div class="summary-item">
              <div class="summary-value">₹#{number_with_delimiter(report_data[:summary][:total_cgst] || 0)}</div>
              <div class="summary-label">Total CGST</div>
            </div>
            <div class="summary-item">
              <div class="summary-value">₹#{number_with_delimiter(report_data[:summary][:total_sgst] || 0)}</div>
              <div class="summary-label">Total SGST</div>
            </div>
            <div class="summary-item">
              <div class="summary-value">₹#{number_with_delimiter(report_data[:summary][:total_igst] || 0)}</div>
              <div class="summary-label">Total IGST</div>
            </div>
          </div>
        </div>

        <table>
          <thead>
            <tr>
              <th>Customer Name</th>
              <th>Customer Number</th>
              <th>Address</th>
              <th>Invoice Number</th>
              <th>Invoice Date</th>
              <th class="text-center">Assignments</th>
              <th class="text-right">Total Amount</th>
              <th class="text-right">Total GST</th>
              <th class="text-right">CGST</th>
              <th class="text-right">SGST</th>
              <th class="text-right">IGST</th>
            </tr>
          </thead>
          <tbody>
            #{report_data[:detailed_sales].map do |sale|
              <<~ROW
                <tr>
                  <td class="customer-name">#{sale[:customer_name]}</td>
                  <td>#{sale[:customer_number]}</td>
                  <td class="address">#{sale[:customer_address]}</td>
                  <td>#{sale[:invoice_number]}</td>
                  <td>#{sale[:invoice_date]}</td>
                  <td class="text-center">#{sale[:assignment_count]}</td>
                  <td class="text-right amount">₹#{number_with_delimiter(sale[:total_amount])}</td>
                  <td class="text-right">₹#{number_with_delimiter(sale[:total_gst] || 0)}</td>
                  <td class="text-right">₹#{number_with_delimiter(sale[:cgst] || 0)}</td>
                  <td class="text-right">₹#{number_with_delimiter(sale[:sgst] || 0)}</td>
                  <td class="text-right">₹#{number_with_delimiter(sale[:igst] || 0)}</td>
                </tr>
              ROW
            end.join}
            <tr class="total-row">
              <td colspan="5"><strong>TOTAL</strong></td>
              <td class="text-center"><strong>#{report_data[:summary][:total_assignments]}</strong></td>
              <td class="text-right"><strong>₹#{number_with_delimiter(report_data[:summary][:total_invoice_amount])}</strong></td>
              <td class="text-right"><strong>₹#{number_with_delimiter(report_data[:summary][:total_gst] || 0)}</strong></td>
              <td class="text-right"><strong>₹#{number_with_delimiter(report_data[:summary][:total_cgst] || 0)}</strong></td>
              <td class="text-right"><strong>₹#{number_with_delimiter(report_data[:summary][:total_sgst] || 0)}</strong></td>
              <td class="text-right"><strong>₹#{number_with_delimiter(report_data[:summary][:total_igst] || 0)}</strong></td>
            </tr>
          </tbody>
        </table>

        <div class="footer">
          <p>Enhanced Sales Report | #{report_data[:summary][:report_month]} #{report_data[:summary][:report_year]} | Total of #{report_data[:summary][:total_invoices]} invoices</p>
        </div>
      </body>
      </html>
    HTML
  end
  
  def generate_pdf_html_table(report, gst_data, from_date, to_date)
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <title>GST Report - #{report.respond_to?(:name) ? report.name : "GST Report"}</title>
        <style>
          body { font-family: Arial, sans-serif; font-size: 12px; margin: 20px; }
          .header { text-align: center; margin-bottom: 30px; }
          .company-info { margin-bottom: 20px; }
          .report-title { font-size: 18px; font-weight: bold; margin-bottom: 10px; }
          .date-range { font-size: 14px; color: #666; margin-bottom: 20px; }
          table { width: 100%; border-collapse: collapse; margin-bottom: 20px; }
          th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
          th { background-color: #f2f2f2; font-weight: bold; text-align: center; }
          .text-right { text-align: right; }
          .text-center { text-align: center; }
          .total-row { background-color: #f9f9f9; font-weight: bold; }
          .summary { margin-top: 30px; }
          .summary-table { width: 50%; }
          .page-break { page-break-after: always; }
        </style>
      </head>
      <body>
        <div class="header">
          <div class="report-title">GSTR-1 - #{AdminSetting.current.business_name}</div>
          <div class="company-info">
            Mobile: 9972808044<br>
            GST No: 29AOIPT8113K1ZC
          </div>
          <div class="date-range">
            Date Range: #{from_date.strftime('%d/%m/%Y')} to #{to_date.strftime('%d/%m/%Y')}<br>
            Generated On: #{Time.current.strftime('%d/%m/%Y at %I:%M %p')}
          </div>
        </div>

        <h3>Sales Transactions</h3>
        <table>
          <thead>
            <tr>
              <th rowspan="2">GSTIN</th>
              <th rowspan="2">Customer Name</th>
              <th colspan="2">Place of Supply</th>
              <th colspan="3">Invoice Details</th>
              <th colspan="6">Amount of Tax</th>
              <th rowspan="2">Total Tax</th>
            </tr>
            <tr>
              <th>State Code</th>
              <th>State Name</th>
              <th>Invoice No.</th>
              <th>Invoice Date</th>
              <th>Invoice Value</th>
              <th>Tax %</th>
              <th>Taxable Value</th>
              <th>Central Tax</th>
              <th>State/UT Tax</th>
              <th>Integrated Tax</th>
              <th>CESS</th>
            </tr>
          </thead>
          <tbody>
            #{gst_data[:sales_transactions].map { |transaction|
              <<~ROW
                <tr>
                  <td class="text-center">-</td>
                  <td>#{transaction[:customer_name]}</td>
                  <td class="text-center">#{transaction[:state_code]}</td>
                  <td>#{transaction[:state_name]}</td>
                  <td>#{transaction[:invoice_no]}</td>
                  <td class="text-center">#{transaction[:invoice_date]}</td>
                  <td class="text-right">₹#{number_with_delimiter(transaction[:invoice_value])}</td>
                  <td class="text-right">#{transaction[:tax_rate]}%</td>
                  <td class="text-right">₹#{number_with_delimiter(transaction[:taxable_value])}</td>
                  <td class="text-right">₹#{number_with_delimiter(transaction[:central_tax])}</td>
                  <td class="text-right">₹#{number_with_delimiter(transaction[:state_tax])}</td>
                  <td class="text-right">₹#{number_with_delimiter(transaction[:integrated_tax])}</td>
                  <td class="text-right">₹#{number_with_delimiter(transaction[:cess])}</td>
                  <td class="text-right">₹#{number_with_delimiter(transaction[:total_tax])}</td>
                </tr>
              ROW
            }.join}
            <tr class="total-row">
              <td colspan="6"><strong>Total</strong></td>
              <td class="text-right"><strong>₹#{number_with_delimiter(gst_data[:summary][:total_sales])}</strong></td>
              <td></td>
              <td class="text-right"><strong>₹#{number_with_delimiter(gst_data[:summary][:total_sales] - gst_data[:summary][:total_tax])}</strong></td>
              <td class="text-right"><strong>₹#{number_with_delimiter(gst_data[:summary][:cgst])}</strong></td>
              <td class="text-right"><strong>₹#{number_with_delimiter(gst_data[:summary][:sgst])}</strong></td>
              <td class="text-right"><strong>₹#{number_with_delimiter(gst_data[:summary][:igst])}</strong></td>
              <td class="text-right"><strong>₹0.0</strong></td>
              <td class="text-right"><strong>₹#{number_with_delimiter(gst_data[:summary][:total_tax])}</strong></td>
            </tr>
          </tbody>
        </table>

        <div class="summary">
          <h3>Tax Summary</h3>
          <table class="summary-table">
            <tr>
              <td><strong>Total Sales:</strong></td>
              <td class="text-right"><strong>₹#{number_with_delimiter(gst_data[:summary][:total_sales])}</strong></td>
            </tr>
            <tr>
              <td><strong>Total Tax Collected:</strong></td>
              <td class="text-right"><strong>₹#{number_with_delimiter(gst_data[:summary][:total_tax])}</strong></td>
            </tr>
            <tr>
              <td>CGST:</td>
              <td class="text-right">₹#{number_with_delimiter(gst_data[:summary][:cgst])}</td>
            </tr>
            <tr>
              <td>SGST:</td>
              <td class="text-right">₹#{number_with_delimiter(gst_data[:summary][:sgst])}</td>
            </tr>
            <tr>
              <td>IGST:</td>
              <td class="text-right">₹#{number_with_delimiter(gst_data[:summary][:igst])}</td>
            </tr>
          </table>
        </div>

        <div style="margin-top: 50px; text-align: center; font-size: 10px; color: #666;">
          Report generated by Atmanirbhar Farm Bangalore<br>
          #{Time.current.strftime('%B %d, %Y at %I:%M %p')}
        </div>
      </body>
      </html>
    HTML
  end
  
  def generate_gst_report_html(report)
    # Generate GST report content based on the date range
    from_date = report.respond_to?(:from_date) ? report.from_date : Date.parse(params[:from_date] || 1.month.ago.to_s)
    to_date = report.respond_to?(:to_date) ? report.to_date : Date.parse(params[:to_date] || Date.current.to_s)
    
    # Get actual GST data from sales invoices
    gst_data = get_gst_report_data(from_date, to_date)
    
    <<~HTML
      GST REPORT
      ==========
      
      Report Name: #{report.respond_to?(:name) ? report.name : "GST Report"}
      Date Range: #{from_date.strftime('%B %d, %Y')} to #{to_date.strftime('%B %d, %Y')}
      Generated On: #{Time.current.strftime('%B %d, %Y at %I:%M %p')}
      Generated By: #{current_user.name}
      
      SUMMARY
      -------
      Total Sales: ₹#{gst_data[:summary][:total_sales]}
      Total Tax Collected: ₹#{gst_data[:summary][:total_tax]}
      CGST: ₹#{gst_data[:summary][:cgst]}
      SGST: ₹#{gst_data[:summary][:sgst]}
      IGST: ₹#{gst_data[:summary][:igst]}
      
      SALES TRANSACTIONS
      ------------------
      #{gst_data[:sales_transactions].map { |t| 
        "#{t[:customer_name]} | #{t[:invoice_no]} | #{t[:invoice_date]} | ₹#{t[:invoice_value]} | #{t[:tax_rate]}% | ₹#{t[:tax_amount]}"
      }.join("\n")}
      
      ---
      Report generated by Atmanirbhar Farm Bangalore
      #{Time.current.strftime('%B %d, %Y at %I:%M %p')}
    HTML
  end

  def get_gst_report_data(from_date, to_date)
    # Get sales invoices for the date range
    sales_invoices = SalesInvoice.includes(:sales_invoice_items, :customer, :sales_customer)
                                 .where(invoice_date: from_date..to_date)
                                 .where.not(status: 'cancelled')

    # Get delivery assignments for the date range (if they have invoice data)
    delivery_assignments = DeliveryAssignment.includes(:customer, :product, :invoice)
                                           .where(scheduled_date: from_date..to_date, status: 'completed')

    sales_transactions = []
    total_sales = 0
    total_tax = 0
    cgst_total = 0
    sgst_total = 0
    igst_total = 0

    # Process sales invoices
    sales_invoices.each do |invoice|
      customer_name = invoice.customer_name || invoice.get_customer&.name || "Unknown"
      customer_state = get_customer_state(invoice)
      
      invoice.sales_invoice_items.each do |item|
        tax_amount = item.tax_amount || 0
        invoice_value = item.total_with_tax || 0
        
        # Calculate GST breakdown based on state
        if customer_state == "Karnataka" # Same state as business
          cgst_amount = tax_amount / 2
          sgst_amount = tax_amount / 2
          igst_amount = 0
        else # Different state
          cgst_amount = 0
          sgst_amount = 0
          igst_amount = tax_amount
        end

        sales_transactions << {
          customer_name: customer_name,
          state_code: get_state_code(customer_state),
          state_name: customer_state,
          invoice_no: invoice.invoice_number,
          invoice_date: invoice.invoice_date.strftime('%d/%m/%Y'),
          invoice_value: invoice_value.round(2),
          tax_rate: item.tax_rate || 0,
          taxable_value: (invoice_value - tax_amount).round(2),
          central_tax: cgst_amount.round(2),
          state_tax: sgst_amount.round(2),
          integrated_tax: igst_amount.round(2),
          cess: 0.0,
          total_tax: tax_amount.round(2)
        }

        total_sales += invoice_value
        total_tax += tax_amount
        cgst_total += cgst_amount
        sgst_total += sgst_amount
        igst_total += igst_amount
      end
    end

    # Process delivery assignments that don't have invoices yet
    delivery_assignments.where(invoice_generated: false).each do |assignment|
      customer_name = assignment.customer_name
      customer_state = assignment.customer&.state || "Karnataka"
      
      # Calculate tax based on product price and standard tax rate (assuming 5% for milk products)
      tax_rate = 5.0
      invoice_value = assignment.total_amount || 0
      tax_amount = (invoice_value * tax_rate / (100 + tax_rate)).round(2)
      taxable_value = invoice_value - tax_amount

      # Calculate GST breakdown based on state
      if customer_state == "Karnataka"
        cgst_amount = tax_amount / 2
        sgst_amount = tax_amount / 2
        igst_amount = 0
      else
        cgst_amount = 0
        sgst_amount = 0
        igst_amount = tax_amount
      end

      sales_transactions << {
        customer_name: customer_name,
        state_code: get_state_code(customer_state),
        state_name: customer_state,
        invoice_no: "DA-#{assignment.id}",
        invoice_date: assignment.scheduled_date.strftime('%d/%m/%Y'),
        invoice_value: invoice_value.round(2),
        tax_rate: tax_rate,
        taxable_value: taxable_value.round(2),
        central_tax: cgst_amount.round(2),
        state_tax: sgst_amount.round(2),
        integrated_tax: igst_amount.round(2),
        cess: 0.0,
        total_tax: tax_amount.round(2)
      }

      total_sales += invoice_value
      total_tax += tax_amount
      cgst_total += cgst_amount
      sgst_total += sgst_amount
      igst_total += igst_amount
    end

    {
      sales_transactions: sales_transactions,
      summary: {
        total_sales: total_sales.round(2),
        total_tax: total_tax.round(2),
        cgst: cgst_total.round(2),
        sgst: sgst_total.round(2),
        igst: igst_total.round(2)
      }
    }
  end

  def get_customer_state(invoice)
    customer = invoice.get_customer
    return customer.state if customer&.state.present?
    
    # Default to Karnataka if no state is specified
    "Karnataka"
  end

  def get_state_code(state_name)
    state_codes = {
      "Karnataka" => "29",
      "Tamil Nadu" => "33",
      "Kerala" => "32",
      "Andhra Pradesh" => "37",
      "Telangana" => "36",
      "Maharashtra" => "27",
      "Gujarat" => "24",
      "Rajasthan" => "08",
      "Uttar Pradesh" => "09",
      "West Bengal" => "19",
      "Bihar" => "10",
      "Madhya Pradesh" => "23",
      "Odisha" => "21",
      "Punjab" => "03",
      "Haryana" => "06",
      "Himachal Pradesh" => "02",
      "Uttarakhand" => "05",
      "Jharkhand" => "20",
      "Chhattisgarh" => "22",
      "Assam" => "18",
      "Tripura" => "16",
      "Meghalaya" => "17",
      "Manipur" => "14",
      "Nagaland" => "13",
      "Mizoram" => "15",
      "Arunachal Pradesh" => "12",
      "Sikkim" => "11",
      "Goa" => "30",
      "Delhi" => "07",
      "Puducherry" => "34",
      "Chandigarh" => "04",
      "Andaman and Nicobar Islands" => "35",
      "Dadra and Nagar Haveli and Daman and Diu" => "26",
      "Lakshadweep" => "31",
      "Ladakh" => "38",
      "Jammu and Kashmir" => "01"
    }

    state_codes[state_name] || "29" # Default to Karnataka
  end

  # Sales Report Data
  def get_sales_report_data(from_date, to_date)
    sales_invoices = SalesInvoice.includes(:sales_invoice_items, :customer, :sales_customer)
                                 .where(invoice_date: from_date..to_date)
                                 .where.not(status: 'cancelled')

    total_sales = 0
    total_invoices = sales_invoices.count
    invoice_data = []

    sales_invoices.each do |invoice|
      invoice_total = invoice.sales_invoice_items.sum(&:total_with_tax) || 0
      total_sales += invoice_total

      invoice_data << {
        invoice_number: invoice.invoice_number,
        customer_name: invoice.customer_name || invoice.get_customer&.name || "Unknown",
        date: invoice.invoice_date.strftime('%d/%m/%Y'),
        amount: invoice_total.round(2),
        status: invoice.status&.humanize || 'Pending'
      }
    end

    average_order_value = total_invoices > 0 ? (total_sales / total_invoices).round(2) : 0

    {
      summary: {
        total_sales: total_sales.round(2),
        total_invoices: total_invoices,
        average_order_value: average_order_value,
        period: "#{from_date.strftime('%d/%m/%Y')} to #{to_date.strftime('%d/%m/%Y')}"
      },
      invoices: invoice_data.sort_by { |i| i[:date] }.reverse
    }
  end

  # Delivery Report Data
  def get_delivery_report_data(from_date, to_date)
    delivery_assignments = DeliveryAssignment.includes(:customer, :product, :user)
                                           .where(scheduled_date: from_date..to_date)

    total_assignments = delivery_assignments.count
    completed_assignments = delivery_assignments.where(status: 'completed').count
    pending_assignments = delivery_assignments.where(status: 'pending').count
    cancelled_assignments = delivery_assignments.where(status: 'cancelled').count

    completion_rate = total_assignments > 0 ? ((completed_assignments.to_f / total_assignments) * 100).round(2) : 0

    delivery_people_performance = delivery_assignments.joins(:user)
                                                     .group('users.name')
                                                     .group(:status)
                                                     .count

    performance_data = []
    delivery_assignments.joins(:user).group('users.name').each do |name, assignments|
      user_assignments = delivery_assignments.joins(:user).where('users.name = ?', name)
      completed = user_assignments.where(status: 'completed').count
      total = user_assignments.count
      rate = total > 0 ? ((completed.to_f / total) * 100).round(2) : 0

      performance_data << {
        delivery_person: name,
        total_assignments: total,
        completed: completed,
        completion_rate: rate
      }
    end

    {
      summary: {
        total_assignments: total_assignments,
        completed_assignments: completed_assignments,
        pending_assignments: pending_assignments,
        cancelled_assignments: cancelled_assignments,
        completion_rate: completion_rate,
        period: "#{from_date.strftime('%d/%m/%Y')} to #{to_date.strftime('%d/%m/%Y')}"
      },
      delivery_people_performance: performance_data.sort_by { |d| d[:completion_rate] }.reverse
    }
  end

  # Customer Report Data
  def get_customer_report_data(from_date, to_date)
    # Get customers with activity in the date range
    customer_sales = SalesInvoice.includes(:customer, :sales_customer)
                                .where(invoice_date: from_date..to_date)
                                .where.not(status: 'cancelled')
                                .group(:customer_id)
                                .group(:sales_customer_id)
                                .sum('COALESCE((SELECT SUM(total_with_tax) FROM sales_invoice_items WHERE sales_invoice_id = sales_invoices.id), 0)')

    customer_deliveries = DeliveryAssignment.includes(:customer)
                                          .where(scheduled_date: from_date..to_date, status: 'completed')
                                          .group(:customer_id)
                                          .count

    total_customers = Customer.count
    active_customers = customer_sales.keys.count + customer_deliveries.keys.count

    top_customers = []
    customer_sales.each do |customer_id, sales_amount|
      next if customer_id.blank?

      customer = Customer.find_by(id: customer_id)
      next unless customer

      deliveries = customer_deliveries[customer_id] || 0

      top_customers << {
        name: customer.name,
        phone: customer.phone,
        total_sales: sales_amount.round(2),
        total_deliveries: deliveries,
        last_order_date: SalesInvoice.where(customer_id: customer_id)
                                   .where(invoice_date: from_date..to_date)
                                   .maximum(:invoice_date)&.strftime('%d/%m/%Y') || 'N/A'
      }
    end

    {
      summary: {
        total_customers: total_customers,
        active_customers: active_customers,
        new_customers: Customer.where(created_at: from_date..to_date).count,
        period: "#{from_date.strftime('%d/%m/%Y')} to #{to_date.strftime('%d/%m/%Y')}"
      },
      top_customers: top_customers.sort_by { |c| c[:total_sales] }.reverse.first(20)
    }
  end

  # Product Report Data
  def get_product_report_data(from_date, to_date)
    # Get product sales from invoice items
    product_sales = SalesInvoiceItem.joins(:sales_invoice)
                                   .where(sales_invoices: { invoice_date: from_date..to_date })
                                   .where.not(sales_invoices: { status: 'cancelled' })
                                   .group(:product_name)
                                   .group(:sales_product_id)
                                   .sum(:quantity)

    product_revenue = SalesInvoiceItem.joins(:sales_invoice)
                                     .where(sales_invoices: { invoice_date: from_date..to_date })
                                     .where.not(sales_invoices: { status: 'cancelled' })
                                     .group(:product_name)
                                     .group(:sales_product_id)
                                     .sum(:total_with_tax)

    product_data = []
    product_sales.each do |key, quantity|
      product_name = key.is_a?(Array) ? key[0] : 'Unknown Product'
      revenue = product_revenue[key] || 0

      product_data << {
        name: product_name,
        quantity_sold: quantity,
        total_revenue: revenue.round(2),
        average_price: quantity > 0 ? (revenue / quantity).round(2) : 0
      }
    end

    total_products_sold = product_sales.values.sum
    total_revenue = product_revenue.values.sum

    {
      summary: {
        total_products_sold: total_products_sold,
        total_revenue: total_revenue.round(2),
        unique_products: product_data.count,
        period: "#{from_date.strftime('%d/%m/%Y')} to #{to_date.strftime('%d/%m/%Y')}"
      },
      products: product_data.sort_by { |p| p[:total_revenue] }.reverse
    }
  end

  # Enhanced Sales Report Data
  def get_enhanced_sales_report_data(from_date, to_date)
    # Determine month and year from the date range
    report_month = from_date.month
    report_year = from_date.year

    # Get all invoices with preloaded associations including invoice items and products for tax calculation
    invoices = Invoice.includes(:customer, :delivery_assignments, invoice_items: :product)
                     .where(month: report_month, year: report_year)
                     .order(:invoice_date)

    # Preload assignment counts in memory to avoid N+1 queries
    assignment_counts = {}
    invoices.each do |invoice|
      assignment_counts[invoice.id] = invoice.delivery_assignments.size
    end

    detailed_sales = []
    total_invoice_amount = 0
    total_assignment_count = 0
    total_gst_amount = 0
    total_cgst_amount = 0
    total_sgst_amount = 0
    total_igst_amount = 0

    invoices.each do |invoice|
      # Skip if no customer
      next unless invoice.customer

      # Get customer details
      customer_name = invoice.customer.name || "Unknown Customer"
      customer_number = invoice.customer.phone_number || invoice.customer.alt_phone_number || "N/A"
      customer_address = build_customer_address(invoice.customer)

      # Get assignment count from preloaded data
      assignment_count = assignment_counts[invoice.id] || 0

      # If no assignments linked, consider it as 1 manual invoice
      assignment_count = 1 if assignment_count == 0

      # Get invoice total amount
      invoice_total_amount = invoice.total_amount || 0

      # Calculate tax amounts for this invoice
      tax_amounts = calculate_invoice_tax_amounts(invoice)

      # Add to detailed sales array with all requested fields including tax details
      detailed_sales << {
        customer_name: customer_name,
        invoice_number: invoice.invoice_number,
        invoice_id: invoice.id,
        total_amount: invoice_total_amount.round(2),
        assignment_count: assignment_count,
        invoice_date: invoice.invoice_date.strftime('%d/%m/%Y'),
        customer_number: customer_number,
        customer_address: customer_address,
        total_gst: tax_amounts[:total_gst].round(2),
        cgst: tax_amounts[:cgst].round(2),
        sgst: tax_amounts[:sgst].round(2),
        igst: tax_amounts[:igst].round(2)
      }

      # Add to totals
      total_invoice_amount += invoice_total_amount
      total_assignment_count += assignment_count
      total_gst_amount += tax_amounts[:total_gst]
      total_cgst_amount += tax_amounts[:cgst]
      total_sgst_amount += tax_amounts[:sgst]
      total_igst_amount += tax_amounts[:igst]
    end

    # Sort by invoice date (newest first)
    detailed_sales.sort! { |a, b| Date.parse(b[:invoice_date]) <=> Date.parse(a[:invoice_date]) }

    {
      detailed_sales: detailed_sales,
      summary: {
        total_invoices: detailed_sales.count,
        total_assignments: total_assignment_count,
        total_invoice_amount: total_invoice_amount.round(2),
        average_invoice_value: detailed_sales.count > 0 ? (total_invoice_amount / detailed_sales.count).round(2) : 0,
        period: "#{from_date.strftime('%d/%m/%Y')} to #{to_date.strftime('%d/%m/%Y')}",
        report_month: Date::MONTHNAMES[report_month],
        report_year: report_year,
        total_gst: total_gst_amount.round(2),
        total_cgst: total_cgst_amount.round(2),
        total_sgst: total_sgst_amount.round(2),
        total_igst: total_igst_amount.round(2)
      }
    }
  end

  def build_customer_address(customer)
    address_parts = []
    address_parts << customer.address if customer.address.present?
    address_parts << customer.city if customer.respond_to?(:city) && customer.city.present?
    address_parts << customer.state if customer.respond_to?(:state) && customer.state.present?
    address_parts << customer.pincode if customer.respond_to?(:pincode) && customer.pincode.present?

    address_parts.any? ? address_parts.join(', ') : "Address not available"
  end

  def calculate_invoice_tax_amounts(invoice)
    total_gst = 0
    cgst = 0
    sgst = 0
    igst = 0

    # Go through each invoice item to calculate tax based on the associated product
    invoice.invoice_items.each do |item|
      product = item.product
      next unless product && product.is_gst_applicable

      # Calculate the base amount for this item (quantity * unit_price)
      item_base_amount = (item.quantity || 0) * (item.unit_price || 0)

      # Calculate tax amounts based on product's GST settings
      if product.total_cgst_percentage.present? && product.total_sgst_percentage.present?
        # Domestic transaction (CGST + SGST)
        item_cgst = item_base_amount * (product.total_cgst_percentage / 100.0)
        item_sgst = item_base_amount * (product.total_sgst_percentage / 100.0)

        cgst += item_cgst
        sgst += item_sgst
        total_gst += item_cgst + item_sgst
      elsif product.total_igst_percentage.present?
        # Interstate transaction (IGST)
        item_igst = item_base_amount * (product.total_igst_percentage / 100.0)

        igst += item_igst
        total_gst += item_igst
      elsif product.total_gst_percentage.present?
        # Fallback: use total GST percentage (assume it's split equally between CGST and SGST)
        total_item_gst = item_base_amount * (product.total_gst_percentage / 100.0)
        item_cgst = total_item_gst / 2
        item_sgst = total_item_gst / 2

        cgst += item_cgst
        sgst += item_sgst
        total_gst += total_item_gst
      end
    end

    {
      total_gst: total_gst,
      cgst: cgst,
      sgst: sgst,
      igst: igst
    }
  end

  # Financial Report Data
  def get_financial_report_data(from_date, to_date)
    # Sales Revenue
    sales_revenue = SalesInvoice.includes(:sales_invoice_items)
                               .where(invoice_date: from_date..to_date)
                               .where.not(status: 'cancelled')
                               .sum('COALESCE((SELECT SUM(total_with_tax) FROM sales_invoice_items WHERE sales_invoice_id = sales_invoices.id), 0)')

    # Purchase Costs
    purchase_costs = PurchaseInvoice.where(invoice_date: from_date..to_date)
                                   .where.not(status: 'cancelled')
                                   .sum(:total_amount)

    # Tax collected
    tax_collected = SalesInvoiceItem.joins(:sales_invoice)
                                   .where(sales_invoices: { invoice_date: from_date..to_date })
                                   .where.not(sales_invoices: { status: 'cancelled' })
                                   .sum(:tax_amount)

    # Basic calculations
    gross_profit = sales_revenue - purchase_costs
    profit_margin = sales_revenue > 0 ? ((gross_profit / sales_revenue) * 100).round(2) : 0

    # Monthly breakdown
    monthly_data = []
    current_date = from_date.beginning_of_month
    while current_date <= to_date.end_of_month
      month_start = current_date.beginning_of_month
      month_end = current_date.end_of_month

      month_sales = SalesInvoice.includes(:sales_invoice_items)
                               .where(invoice_date: month_start..month_end)
                               .where.not(status: 'cancelled')
                               .sum('COALESCE((SELECT SUM(total_with_tax) FROM sales_invoice_items WHERE sales_invoice_id = sales_invoices.id), 0)')

      month_purchases = PurchaseInvoice.where(invoice_date: month_start..month_end)
                                      .where.not(status: 'cancelled')
                                      .sum(:total_amount)

      monthly_data << {
        month: current_date.strftime('%B %Y'),
        sales: month_sales.round(2),
        purchases: month_purchases.round(2),
        profit: (month_sales - month_purchases).round(2)
      }

      current_date = current_date.next_month
    end

    {
      summary: {
        total_sales: sales_revenue.round(2),
        total_purchases: purchase_costs.round(2),
        gross_profit: gross_profit.round(2),
        profit_margin: profit_margin,
        tax_collected: tax_collected.round(2),
        period: "#{from_date.strftime('%d/%m/%Y')} to #{to_date.strftime('%d/%m/%Y')}"
      },
      monthly_breakdown: monthly_data
    }
  end
end