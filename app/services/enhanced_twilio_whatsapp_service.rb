# app/services/enhanced_twilio_whatsapp_service.rb
class EnhancedTwilioWhatsappService
  include Rails.application.routes.url_helpers

  def initialize
    @client = Twilio::REST::Client.new(
      Rails.application.credentials.dig(:twilio, :account_sid) || ENV['TWILIO_ACCOUNT_SID'],
      Rails.application.credentials.dig(:twilio, :auth_token) || ENV['TWILIO_AUTH_TOKEN']
    )
    @from_number = Rails.application.credentials.dig(:twilio, :phone_number) || ENV['TWILIO_PHONE_NUMBER']
    @content_sid = Rails.application.credentials.dig(:twilio, :content_sid) || ENV['TWILIO_CONTENT_SID']
  end

  def send_invoice_notification(invoice, phone_number: nil, public_url: nil)
    if phone_number.nil?
      return false unless invoice.customer&.phone_number.present?
    end

    # Format phone number for WhatsApp
    phone_number = phone_number || invoice.customer.phone_number
    phone_number = format_phone_number(phone_number)

    # Calculate due date (10 days from now or use invoice due date)
    due_date = invoice.due_date.presence || (Date.current + 10.days)

    # Generate PDF URL using multiple fallback methods
    pdf_url = public_url || generate_invoice_pdf_url(invoice)

    if pdf_url.blank?
      Rails.logger.error "Could not generate PDF URL for invoice #{invoice.invoice_number}"
      return false
    end

    # Debug: Log the actual PDF URL being used
    Rails.logger.info "🔗 Using PDF URL for WhatsApp: #{pdf_url}"
    puts "🔗 DEBUG: PDF URL = #{pdf_url}"

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
        # Debug: Log what we're sending to Twilio
        Rails.logger.info "📱 Sending WhatsApp with media_url: #{[pdf_url]}"
        puts "📱 DEBUG: media_url array = #{[pdf_url].inspect}"

        # Use WhatsApp Business template (recommended)
        message = @client.messages.create(
          content_sid: @content_sid,
          to: "whatsapp:#{phone_number}",
          from: @from_number,
          content_variables: content_variables.to_json,
          media_url: [pdf_url]
        )
      else
        # Fallback to regular WhatsApp message
        message_body = build_fallback_message(invoice, due_date)

        message = @client.messages.create(
          to: "whatsapp:#{phone_number}",
          from: @from_number,
          body: message_body,
          media_url: [pdf_url]
        )
      end

      Rails.logger.info "WhatsApp message sent successfully. SID: #{message.sid}"

      # Update invoice tracking
      invoice.update!(
        shared_at: Time.current
      )

      true

    rescue Twilio::REST::RestError => e
      Rails.logger.error "Twilio WhatsApp error: #{e.message}"
      false
    rescue => e
      Rails.logger.error "WhatsApp service error: #{e.message}"
      false
    end
  end

  private

  def generate_invoice_pdf_url(invoice)
    # Use the new PublicPdfService with clean URLs
    result = PublicPdfService.generate_invoice_pdf(invoice)

    if result[:success]
      return result[:public_url]
    else
      Rails.logger.error "PDF generation failed: #{result[:error]}"
      return nil
    end
  rescue => e
    Rails.logger.error "PDF URL generation failed: #{e.message}"
    nil
  end

  def aws_configured?
    (Rails.application.credentials.dig(:aws, :access_key_id).present? || ENV['AWS_ACCESS_KEY_ID'].present?) &&
    (Rails.application.credentials.dig(:aws, :s3_bucket).present? || ENV['AWS_S3_BUCKET'].present?)
  end

  def upload_to_s3_and_get_url(invoice)
    # Initialize AWS S3 client
    s3_client = Aws::S3::Client.new(
      region: Rails.application.credentials.dig(:aws, :region) || ENV['AWS_REGION'] || 'ap-south-1',
      access_key_id: Rails.application.credentials.dig(:aws, :access_key_id) || ENV['AWS_ACCESS_KEY_ID'],
      secret_access_key: Rails.application.credentials.dig(:aws, :secret_access_key) || ENV['AWS_SECRET_ACCESS_KEY']
    )

    bucket_name = Rails.application.credentials.dig(:aws, :s3_bucket) || ENV['AWS_S3_BUCKET']

    # Generate PDF content
    pdf_content = generate_pdf_content(invoice)

    # Upload to S3
    file_key = "invoices/#{invoice.share_token || invoice.id}/invoice_#{invoice.invoice_number}_#{Time.current.to_i}.pdf"

    s3_client.put_object(
      bucket: bucket_name,
      key: file_key,
      body: pdf_content,
      content_type: 'application/pdf',
      cache_control: 'public, max-age=3600', # Cache for 1 hour
      metadata: {
        'invoice-id' => invoice.id.to_s,
        'generated-at' => Time.current.iso8601
      }
    )

    # Return public URL
    cloudfront_domain = Rails.application.credentials.dig(:aws, :cloudfront_domain) || ENV['AWS_CLOUDFRONT_DOMAIN']

    if cloudfront_domain.present?
      "https://#{cloudfront_domain}/#{file_key}"
    else
      "https://#{bucket_name}.s3.amazonaws.com/#{file_key}"
    end
  rescue => e
    Rails.logger.error "S3 upload failed: #{e.message}"
    # Fallback to local URL
    build_public_url(invoice)
  end

  def generate_pdf_content(invoice)
    # Generate PDF using your existing method
    controller = InvoicesController.new
    controller.instance_variable_set(:@invoice, invoice)
    controller.instance_variable_set(:@invoice_items, invoice.invoice_items.includes(:product))
    controller.instance_variable_set(:@customer, invoice.customer)

    # Load delivery assignments for the second page delivery report
    delivery_assignments = invoice.delivery_assignments.includes(:product).order(:completed_at, :scheduled_date)
    controller.instance_variable_set(:@delivery_assignments, delivery_assignments)

    # Call your existing PDF generation method
    controller.send(:generate_pdf_response)
  rescue => e
    Rails.logger.error "PDF generation failed: #{e.message}"
    nil
  end

  def build_public_url(invoice)
    public_invoice_download_url(
      invoice.share_token,
      format: :pdf,
      host: default_url_host,
      protocol: Rails.application.config.force_ssl ? 'https' : 'http'
    )
  end

  def default_url_host
    Rails.application.config.action_mailer.default_url_options[:host] ||
    ENV['APP_HOST'] ||
    'localhost:3000'
  end

  def generate_share_token
    SecureRandom.urlsafe_base64(32)
  end

  def format_phone_number(phone)
    # Clean phone number
    phone = phone.to_s.gsub(/\D/, '')

    # Add India country code if not present
    phone = "91#{phone}" unless phone.start_with?('91')

    # Add + prefix
    phone = "+#{phone}" unless phone.start_with?('+')

    phone
  end

  def build_fallback_message(invoice, due_date)
    <<~MESSAGE
      Hi #{invoice.customer.name}! 👋

      Your invoice for #{invoice.created_at.strftime('%B %Y')} is ready!

      📄 Invoice #: #{invoice.invoice_number}
      💰 Amount: ₹#{invoice.total_amount}
      📅 Due Date: #{due_date.strftime('%d/%m/%Y')}

      Please find your invoice attached. Thank you! 🙏

      - #{AdminSetting.current.business_name}
    MESSAGE
  end
end