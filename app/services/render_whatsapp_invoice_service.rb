class RenderWhatsappInvoiceService
  require 'twilio-ruby'

  def initialize
    @account_sid = Rails.application.credentials.twilio_account_sid || ENV['TWILIO_ACCOUNT_SID']
    @auth_token = Rails.application.credentials.twilio_auth_token || ENV['TWILIO_AUTH_TOKEN']
    @from_number = Rails.application.credentials.twilio_phone_number || ENV['TWILIO_PHONE_NUMBER']

    unless @account_sid && @auth_token && @from_number
      raise "Missing Twilio credentials. Please set TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, and TWILIO_PHONE_NUMBER environment variables."
    end

    @client = Twilio::REST::Client.new(@account_sid, @auth_token)
    @pdf_service = RenderInvoicePdfService.new
  end

  def send_invoice_notification(invoice, phone_number: nil, custom_message: nil)
    begin
      # Use provided phone number or get from customer
      phone = phone_number || invoice.customer.phone_number
      unless phone
        return { success: false, error: "No phone number available for customer" }
      end

      # Sanitize phone number
      phone = sanitize_phone_number(phone)
      unless valid_phone_number?(phone)
        return { success: false, error: "Invalid phone number format: #{phone}" }
      end

      # Generate and store PDF
      pdf_result = @pdf_service.generate_and_store_pdf(invoice)
      unless pdf_result[:success]
        return { success: false, error: "PDF generation failed: #{pdf_result[:error]}" }
      end

      pdf_url = pdf_result[:pdf_url]

      # Send WhatsApp message with PDF
      message_result = send_whatsapp_message(invoice, phone, pdf_url, custom_message)

      if message_result[:success]
        # Schedule cleanup of old PDFs (async)
        cleanup_old_pdfs_async

        {
          success: true,
          message_sid: message_result[:message_sid],
          pdf_url: pdf_url,
          phone_number: phone,
          message: "Invoice sent successfully to #{phone}"
        }
      else
        # Clean up PDF if message failed
        @pdf_service.delete_pdf(pdf_result[:filename])
        message_result
      end

    rescue => e
      Rails.logger.error "WhatsApp invoice sending failed: #{e.message}"
      {
        success: false,
        error: "Failed to send invoice: #{e.message}"
      }
    end
  end

  def send_bulk_invoices(invoices_data)
    results = []

    invoices_data.each do |data|
      invoice = data[:invoice]
      phone = data[:phone_number]
      custom_message = data[:custom_message]

      result = send_invoice_notification(invoice, phone_number: phone, custom_message: custom_message)
      results << {
        invoice_id: invoice.id,
        customer_name: invoice.customer.name,
        phone_number: phone,
        result: result
      }

      # Add delay to avoid rate limiting
      sleep(1) if invoices_data.size > 1
    end

    {
      success: true,
      total_sent: results.count { |r| r[:result][:success] },
      total_failed: results.count { |r| !r[:result][:success] },
      results: results
    }
  end

  private

  def send_whatsapp_message(invoice, phone, pdf_url, custom_message = nil)
    message_body = custom_message || generate_invoice_message(invoice, pdf_url)

    begin
      message = @client.messages.create(
        from: "whatsapp:#{@from_number}",
        to: "whatsapp:#{phone}",
        body: message_body,
        media_url: [pdf_url]  # Attach PDF as media
      )

      Rails.logger.info "WhatsApp message sent successfully. SID: #{message.sid}, To: #{phone}"

      {
        success: true,
        message_sid: message.sid,
        status: message.status
      }

    rescue Twilio::REST::RestError => e
      Rails.logger.error "Twilio API error: #{e.message}"
      {
        success: false,
        error: "WhatsApp delivery failed: #{e.message}"
      }
    rescue => e
      Rails.logger.error "Unexpected error sending WhatsApp: #{e.message}"
      {
        success: false,
        error: "Failed to send WhatsApp message: #{e.message}"
      }
    end
  end

  def generate_invoice_message(invoice, pdf_url)
    customer_name = invoice.customer.name
    invoice_number = invoice.formatted_number
    total_amount = "₹#{invoice.total_amount}"
    due_date = invoice.due_date.strftime("%d %b %Y")

    <<~MESSAGE
      🏪 *#{AdminSetting.current.business_name}*

      Hello #{customer_name}! 👋

      Your invoice is ready:

      📋 *Invoice ##{invoice_number}*
      💰 Amount: #{total_amount}
      📅 Due Date: #{due_date}

      📎 Please find your invoice attached as PDF.

      💻 You can also view it online: #{pdf_url}

      Thank you for your continued business! 🙏

      For any queries, please contact us.
      - #{AdminSetting.current.business_name}
    MESSAGE
  end

  def sanitize_phone_number(phone)
    # Remove all non-digit characters
    cleaned = phone.gsub(/\D/, '')

    # Add country code if missing (assuming India +91)
    if cleaned.length == 10 && cleaned.start_with?(/[6-9]/)
      cleaned = "91#{cleaned}"
    elsif cleaned.length == 11 && cleaned.start_with?('0')
      cleaned = "91#{cleaned[1..-1]}"
    end

    # Ensure it starts with +
    cleaned.start_with?('+') ? cleaned : "+#{cleaned}"
  end

  def valid_phone_number?(phone)
    # Check if it's a valid format for WhatsApp
    # Should be +[country_code][number] with total length 10-15 digits after +
    phone.match?(/\A\+\d{10,15}\z/)
  end

  def cleanup_old_pdfs_async
    # Schedule cleanup in background (you can use ActiveJob if available)
    Thread.new do
      begin
        @pdf_service.cleanup_old_pdfs(7) # Clean PDFs older than 7 days
      rescue => e
        Rails.logger.error "PDF cleanup failed: #{e.message}"
      end
    end
  end

  # Class method for easy access
  def self.send_invoice(invoice, phone_number: nil, custom_message: nil)
    service = new
    service.send_invoice_notification(invoice, phone_number: phone_number, custom_message: custom_message)
  end

  # Test method
  def self.test_connection
    begin
      service = new
      {
        success: true,
        message: "Twilio connection successful",
        account_sid: service.instance_variable_get(:@account_sid),
        from_number: service.instance_variable_get(:@from_number)
      }
    rescue => e
      {
        success: false,
        error: e.message
      }
    end
  end
end