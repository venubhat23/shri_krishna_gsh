# app/services/twilio_whatsapp_service.rb
require 'twilio-ruby'
require 'json'

class TwilioWhatsappService
  def initialize
    @account_sid = ENV['TWILIO_ACCOUNT_SID']
    @auth_token = ENV['TWILIO_AUTH_TOKEN']
    @content_sid = 'HX6fc19923cd8eed844fc3092b42b4a522'
    @from_number = 'whatsapp:+917619444966'
    @client = Twilio::REST::Client.new(@account_sid, @auth_token)
  end

  def send_bulk_invoice_notifications(invoices)
    success_count = 0
    failure_count = 0
    invoices.each do |invoice|
      begin
        host = Rails.application.config.action_controller.default_url_options[:host] || 'atmanirbharfarmbangalore.com'
        public_url = invoice.public_url(host: host).gsub(':3000', '')
        if send_invoice_notification(invoice, public_url: public_url)
          success_count += 1
        else
          failure_count += 1
        end
      rescue => e
        Rails.logger.error "Failed to send WhatsApp message for invoice #{invoice.id}: #{e.message}"
        failure_count += 1
      end
    end

    { success_count: success_count, failure_count: failure_count }
  end

  def send_invoice_notification(invoice, phone_number: nil, public_url: nil)
    if phone_number.nil?
      return false unless invoice.customer&.phone_number.present?
    end

    # Format phone number for WhatsApp
    phone_number = phone_number || invoice.customer.phone_number
    phone_number = format_phone_number(phone_number)

    # Generate public URL if not provided
    if public_url.present?
      public_url = public_url
    else
      public_url = generate_invoice_pdf_url(invoice)
    end

    # Build enhanced message using the same format as the controller
    message_body = build_enhanced_whatsapp_message(invoice, public_url)

    # Send direct WhatsApp message instead of using template

    content_variables = {
      '1' => invoice.customer.name,
      '2' => invoice.created_at.strftime('%B %Y'),  # Month year
      '3' => invoice.invoice_number,
      '4' => invoice.total_amount.to_s,
      '5' => invoice.due_date.strftime('%d/%m/%Y'),
      '6' => public_url
    }

    # Send WhatsApp message
    message = @client.messages.create(
      to: "whatsapp:#{phone_number}",
      from: @from_number,
      content_variables: content_variables.to_json,
      media_url: [public_url],
      content_sid: "HX6d6a076f9410bfa567222bbb68fb71b2"
    )


    Rails.logger.info "WhatsApp message sent successfully. SID: #{message.sid}"

    # Mark customer as invoice sent
    invoice.customer.update_column(:invoice_sent_at, Time.current) if invoice.customer

    true
  rescue => e
    Rails.logger.error "Twilio WhatsApp error: #{e.message}"
    false
  end

  def send_custom_message(phone_number, message_body)
    # Format phone number for WhatsApp
    phone_number = format_phone_number(phone_number)
    content_variables = {
      '1' => message_body
    }
    # Send WhatsApp message
    message = @client.messages.create(
      content_sid: @content_sid,
      to: "whatsapp:#{phone_number}",
      from: @from_number,
      content_variables: content_variables.to_json
    )

    Rails.logger.info "Custom WhatsApp message sent successfully. SID: #{message.sid}"
    true
  rescue => e
    Rails.logger.error "Twilio WhatsApp error: #{e.message}"
    false
  end

  def send_customer_signup_notification(customer)
    owner_phone = "+919972808044"

    message_body = build_customer_signup_message(customer)

    send_custom_message(owner_phone, message_body)
  end

  def send_order_booking_notification(customer, order_details)
    owner_phone = "+9199728 08044"

    message_body = build_order_booking_message(customer, order_details)

    send_custom_message(owner_phone, message_body)
  end

  private

  def build_enhanced_whatsapp_message(invoice, public_url)
    # Get current month and year or use invoice creation date
    month_year = invoice.invoice_date&.strftime('%B %Y') || invoice.created_at&.strftime('%B %Y') || Date.current.strftime('%B %Y')

    # Format amount with delimiter
    formatted_amount = invoice.total_amount.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse

    # Calculate due date (use invoice due_date or 10 days from creation)
    due_date = invoice.due_date&.strftime('%d/%m/%Y') || (invoice.created_at + 10.days).strftime('%d/%m/%Y')

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

  def format_phone_number(phone)
    # Remove any non-digit characters and ensure it starts with +91
    cleaned = phone.gsub(/\D/, '')

    # Add country code if not present
    if cleaned.length == 10
      "+91#{cleaned}"
    elsif cleaned.length == 12 && cleaned.start_with?('91')
      "+#{cleaned}"
    elsif cleaned.length == 13 && cleaned.start_with?('+91')
      cleaned
    else
      "+91#{cleaned}"
    end
  end

  def generate_invoice_pdf_url(invoice)
    # Generate secure public URL for PDF using the invoice's public_pdf_url method
    host = Rails.application.config.action_controller.default_url_options[:host] || 'atmanirbharfarmbangalore.com'
    protocol = Rails.env.production? ? 'https' : 'http'

    # Ensure invoice has a share token
    invoice.generate_share_token if invoice.share_token.blank?
    invoice.save! if invoice.changed?

    # Generate the public PDF URL with HTTPS
    invoice.public_pdf_url(host: host, protocol: protocol)
  rescue => e
    Rails.logger.error "Error generating PDF URL for invoice #{invoice.id}: #{e.message}"
    # Fallback URL using public route with token
    token = invoice.share_token || SecureRandom.urlsafe_base64(32)
    "#{protocol}://#{host}/invoice/#{token}/download"
  end

def build_customer_signup_message(customer)
  "NEW CUSTOMER SIGNUP! Name: #{customer.name}, Phone: #{customer.phone_number}, Email: #{customer.email || 'Not provided'}, Address: #{customer.address || 'Not provided'}, Member ID: #{customer.member_id || 'Auto-generated'}, Signup Time: #{Time.current.strftime('%d/%m/%Y %I:%M %p')}, Signed up via Mobile App, #{AdminSetting.current.business_name}, +91 9972808044 | +91 9008860329"
end

def build_order_booking_message(customer, order_details)
  "NEW ORDER BOOKED, Customer: #{customer.name}, Phone: #{customer.phone_number}, Product: #{order_details[:product_name]}, Quantity: #{order_details[:quantity]} #{order_details[:unit]}, Period: #{order_details[:start_date]} to #{order_details[:end_date]}, Delivery Days: #{order_details[:delivery_days]}, Estimated Amount: ₹#{order_details[:estimated_amount]}, Payment: #{order_details[:cod] ? 'COD' : 'Prepaid'}, Delivery Person: #{order_details[:delivery_person]}, Booking Time: #{Time.current.strftime('%d/%m/%Y %I:%M %p')}, Booked via Mobile App"
end


end