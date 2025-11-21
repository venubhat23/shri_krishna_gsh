# app/services/whatsapp_service.rb
require 'twilio-ruby'

class WhatsappService
  # Configuration
  # ACCOUNT_SID = 'ACc88b1a0b859971f4c033598e67967411'
  # AUTH_TOKEN  = '93ebd7621541cebb9ccb65cc01ef9316'
  FROM_NUMBER = 'whatsapp:+14155238886' # Twilio Sandbox WhatsApp number
  
  def initialize
    @client = Twilio::REST::Client.new(ACCOUNT_SID, AUTH_TOKEN)
  end
  
  # Send a plain text WhatsApp message
  def send_text(to_number, message)
    formatted_number = format_phone_number(to_number)
    
    # Return false if number is invalid
    return false unless formatted_number
    
    @client.messages.create(
      from: FROM_NUMBER,
      to: "whatsapp:#{formatted_number}",
      body: message
    )
    
    true
  rescue Twilio::REST::RestError => e
    Rails.logger.error "WhatsApp text sending failed to #{to_number}: #{e.message}"
    false
  end
  
  # Send a PDF (or other media) via WhatsApp
  def send_pdf(to_number, pdf_url, message = 'Please find the attached PDF')
    formatted_number = format_phone_number(to_number)
    @client.messages.create(from: FROM_NUMBER,to: "whatsapp:#{formatted_number}",body: message,media_url: [pdf_url])
  rescue Twilio::REST::RestError => e
    Rails.logger.error "WhatsApp PDF sending failed: #{e.message}"
    raise e
  end
  
  # Send invoice notification with PDF
  def send_invoice_notification(invoice)
    # return false unless invoice&.customer&.phone_number.present?
    
    begin
      message = build_invoice_message(invoice)
      pdf_url = "https://conasems-ava-prod.s3.sa-east-1.amazonaws.com/aulas/ava/dummy-1641923583.pdf"
      binding.pry
      send_text(invoice.customer.phone_number, pdf_url, message)
      
      # Log successful send
      Rails.logger.info "Invoice WhatsApp sent successfully to #{invoice.customer.name} (#{invoice.customer.phone_number})"
      true
    rescue => e
      Rails.logger.error "Failed to send invoice WhatsApp to #{invoice.customer.name}: #{e.message}"
      false
    end
  end
  
  # Check if phone number is valid for WhatsApp
  def valid_whatsapp_number?(number)
    formatted = format_phone_number(number)
    !formatted.nil?
  end
  
  private
  
  # Format phone number to ensure it has country code
  def format_phone_number(number)
    return nil if number.blank?
    
    # Remove any existing 'whatsapp:' prefix and non-numeric characters except +
    clean_number = number.to_s.gsub(/^whatsapp:/, '').gsub(/[^\d+]/, '')
    
    # Return nil if number is too short or invalid
    return nil if clean_number.length < 10
    
    # Add +91 if it doesn't start with + (assuming Indian numbers)
    unless clean_number.start_with?('+')
      # Handle Indian numbers (remove leading 0 if present)
      clean_number = clean_number.sub(/^0/, '')
      
      # Add country code for Indian numbers
      clean_number = "+91#{clean_number}"
    end
    
    # Validate final number format (should be 13 characters for Indian numbers: +91xxxxxxxxxx)
    return nil unless clean_number.match(/^\+91\d{10}$/)
    
    clean_number
  end
  
  # Build personalized invoice message
  def build_invoice_message(invoice)
    formatted_amount = "₹#{ActionController::Base.helpers.number_with_delimiter(invoice.total_amount, delimiter: ',')}"
    
    <<~MESSAGE.strip
      🧾 *Invoice Ready - #{invoice.formatted_number}*

      Dear #{invoice.customer.name},
      Your invoice for #{formatted_amount} from *Atmanirbhar Farm* has been prepared.

      Thank you for your business! 🙏
      🌾 *Atmanirbhar Farm*
    MESSAGE
  end
end