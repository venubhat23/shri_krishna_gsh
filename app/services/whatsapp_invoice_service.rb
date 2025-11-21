# app/services/whatsapp_invoice_service.rb
class WhatsappInvoiceService
  include Rails.application.routes.url_helpers

  def initialize
    @client = Twilio::REST::Client.new(
      ENV['TWILIO_ACCOUNT_SID'],
      ENV['TWILIO_AUTH_TOKEN']
    )
    @from_number = 'whatsapp:+917619444966'
    @content_sid = 'HX6d6a076f9410bfa567222bbb68fb71b2'
  end

  def send_invoice_notification(invoice, phone_number: nil, public_url: nil)
    if phone_number.nil?
      return { success: false, error: 'Phone number required' } unless invoice.customer&.phone_number.present?
    end

    # Format phone number for WhatsApp
    phone_number = phone_number || invoice.customer.phone_number
    phone_number = format_phone_number(phone_number)

    # Calculate due date (10 days from now or use invoice due date)
    due_date = invoice.due_date.presence || (Date.current + 10.days)

    # Generate PDF URL - try multiple methods
    pdf_url = public_url || generate_invoice_pdf_url(invoice)

    if pdf_url.blank?
      return { success: false, error: 'Could not generate PDF URL' }
    end

    # Prepare content variables
    content_variables = {
      '1' => invoice.customer.name,
      '2' => invoice.created_at.strftime('%B %Y'),  # Month year
      '3' => invoice.invoice_number,
      '4' => invoice.total_amount.to_s,
      '5' => due_date.strftime('%d/%m/%Y'),
      '6' => pdf_url
    }

    begin
      if @content_sid.present?
        # Use WhatsApp template message (recommended for business)
        message = @client.messages.create(
          content_sid: @content_sid,
          to: "whatsapp:#{phone_number}",
          from: @from_number,
          content_variables: content_variables.to_json,
          media_url: [pdf_url]
        )
      else
        # Fallback to simple message with media
        message_body = build_invoice_message(invoice, due_date, pdf_url)

        message = @client.messages.create(
          to: "whatsapp:#{phone_number}",
          from: @from_number,
          body: message_body,
          media_url: [pdf_url]
        )
      end

      Rails.logger.info "WhatsApp invoice sent successfully. SID: #{message.sid}, Invoice: #{invoice.invoice_number}"

      # Update invoice with WhatsApp tracking info
      invoice.update(
        shared_at: Time.current
      )

      { success: true, message_sid: message.sid, pdf_url: pdf_url }

    rescue Twilio::REST::RestError => e
      Rails.logger.error "Twilio WhatsApp error: #{e.message}"
      { success: false, error: "WhatsApp delivery failed: #{e.message}" }
    rescue => e
      Rails.logger.error "WhatsApp invoice error: #{e.message}"
      { success: false, error: "Failed to send invoice: #{e.message}" }
    end
  end

  private

  def generate_invoice_pdf_url(invoice)
    # Try multiple approaches to get a PDF URL

    # Option 1: Use AWS S3 service (recommended for production)
    if use_aws_s3?
      pdf_service = InvoicePdfService.new
      return pdf_service.generate_and_upload_pdf(invoice)
    end

    # Option 2: Use public share URL (local/temporary)
    if invoice.share_token.present?
      return public_invoice_download_url(
        invoice.share_token,
        format: :pdf,
        host: default_url_options[:host],
        protocol: Rails.application.config.force_ssl ? 'https' : 'http'
      )
    end

    # Option 3: Generate share token and return URL
    invoice.generate_share_token! if invoice.share_token.blank?
    invoice.save!

    public_invoice_download_url(
      invoice.share_token,
      format: :pdf,
      host: default_url_options[:host],
      protocol: Rails.application.config.force_ssl ? 'https' : 'http'
    )
  end

  def use_aws_s3?
    # Check if AWS credentials are configured
    (Rails.application.credentials.dig(:aws, :access_key_id).present? || ENV['AWS_ACCESS_KEY_ID'].present?) &&
    (Rails.application.credentials.dig(:aws, :s3_bucket).present? || ENV['AWS_S3_BUCKET'].present?)
  end

  def default_url_options
    Rails.application.config.action_mailer.default_url_options || {
      host: 'localhost:3000',
      protocol: 'http'
    }
  end

  def format_phone_number(phone)
    # Remove any non-digit characters
    phone = phone.to_s.gsub(/\D/, '')

    # Add country code if not present (assuming India +91)
    phone = "91#{phone}" unless phone.start_with?('91')

    # Ensure it starts with +
    phone = "+#{phone}" unless phone.start_with?('+')

    phone
  end

  def build_invoice_message(invoice, due_date, pdf_url)
    <<~MESSAGE
      Hi #{invoice.customer.name}! 👋

      Your invoice for #{invoice.created_at.strftime('%B %Y')} is ready!

      📄 Invoice #: #{invoice.invoice_number}
      💰 Amount: ₹#{invoice.total_amount}
      📅 Due Date: #{due_date.strftime('%d/%m/%Y')}

      📎 Download your invoice: #{pdf_url}

      Thank you for choosing #{AdminSetting.current.business_name}! 🙏
    MESSAGE
  end
end