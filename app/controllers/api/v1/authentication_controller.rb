module Api
  module V1
    class AuthenticationController < BaseController
      skip_before_action :authenticate_request, only: [:login, :signup, :customer_login, :refresh_token, :customer_signup]

      # POST /api/v1/login - Unified login endpoint
      def login
        identifier = params[:phone] || params[:phone_number] || params[:email]
        password = params[:password]

        return render json: { error: 'Phone/email and password are required' }, status: :bad_request if identifier.blank? || password.blank?

        # Try to authenticate as customer first (by phone)
        if identifier.match(/^\d+$/) # If identifier is numeric (phone)
          customer = Customer.find_by(phone_number: identifier)
          if customer&.authenticate(password) && customer.is_active?
            return render_customer_response(customer)
          end
        end

        # Try to authenticate as customer by email
        if identifier.include?('@') # If identifier is email
          customer = Customer.find_by(email: identifier)
          if customer&.authenticate(password) && customer.is_active?
            return render_customer_response(customer)
          end
        end

        # Try to authenticate as user (delivery person/admin) by phone
        user = User.find_by(phone: identifier)
        if user&.authenticate(password) && %w[admin delivery_person].include?(user.role)
          return render_user_response(user)
        end

        # Try to authenticate as user by email
        user = User.find_by(email: identifier)
        if user&.authenticate(password) && %w[admin delivery_person].include?(user.role)
          return render_user_response(user)
        end

        render json: { error: 'Invalid credentials or account inactive' }, status: :unauthorized
      end

      # POST /api/v1/customer_login
      def customer_login
        @customer = Customer.find_by(phone_number: params[:phone])

        if @customer&.authenticate(params[:password]) && @customer.is_active?
          token = JsonWebToken.encode(customer_id: @customer.id)
          refresh_token, refresh_record = issue_refresh_token(@customer)
          render json: {
            token: token,
            refresh_token: refresh_token,
            token_expires_in: 24.hours.to_i,
            refresh_token_expires_in: (refresh_record.expires_at - Time.current).to_i,
            customer: {
              id: @customer.id,
              name: @customer.name,
              address: @customer.address,
              phone_number: @customer.phone_number,
              email: @customer.email,
              preferred_language: @customer.preferred_language,
              delivery_time_preference: @customer.delivery_time_preference,
              notification_method: @customer.notification_method
            }
          }, status: :ok
        else
          render json: { error: 'Invalid credentials or account inactive' }, status: :unauthorized
        end
      end

      # POST /api/v1/signup - Unified signup endpoint
      def signup
        # Determine user type based on role parameter or defaults to customer
        user_type = params[:role].present? ? params[:role].downcase : 'customer'

        return render json: { error: 'Invalid role. Must be customer, delivery_person, or admin' }, status: :bad_request unless %w[customer delivery_person admin].include?(user_type)

        if user_type == 'customer'
          # Create customer account
          @customer = Customer.new(unified_customer_signup_params)
          @customer.user_id = User.where(id: 1).last.id
          if @customer.save
            # Send WhatsApp notification for successful signup
            send_signup_notification(@customer)
            render_customer_signup_response(@customer)
          else
            Rails.logger.error "Customer signup validation failed: #{@customer.errors.full_messages.join(', ')}"
            render json: { errors: @customer.errors.full_messages }, status: :unprocessable_content
          end
        else
          # Create user account (delivery_person or admin)
          @user = User.new(unified_user_signup_params.merge(role: user_type))

          if @user.save
            render_user_signup_response(@user)
          else
            Rails.logger.error "User signup validation failed: #{@user.errors.full_messages.join(', ')}"
            render json: { errors: @user.errors.full_messages }, status: :unprocessable_content
          end
        end
      end

      # POST /api/v1/customer_signup
      def customer_signup
        @customer = Customer.new(customer_signup_params)

        if @customer.save
          # Send WhatsApp notification for successful signup
          send_signup_notification(@customer)

          token = JsonWebToken.encode(customer_id: @customer.id)
          refresh_token, refresh_record = issue_refresh_token(@customer)
          render json: {
            token: token,
            refresh_token: refresh_token,
            token_expires_in: 24.hours.to_i,
            refresh_token_expires_in: (refresh_record.expires_at - Time.current).to_i,
            customer: {
              id: @customer.id,
              name: @customer.name,
              address: @customer.address,
              phone_number: @customer.phone_number,
              email: @customer.email,
              preferred_language: @customer.preferred_language,
              delivery_time_preference: @customer.delivery_time_preference,
              notification_method: @customer.notification_method,
              latitude: @customer.latitude,
              longitude: @customer.longitude
            }
          }, status: :created
        else
          Rails.logger.error "Customer signup validation failed: #{@customer.errors.full_messages.join(', ')}"
          Rails.logger.error "Customer signup params: #{customer_signup_params.inspect}"
          render json: { errors: @customer.errors.full_messages }, status: :unprocessable_content
        end
      end

      # POST /api/v1/regenerate_token
      # Re-issue a new access token for the currently authenticated principal
      def regenerate_token
        entity = current_entity_from_token
        return render json: { error: 'Authentication required' }, status: :unauthorized if entity.nil?

        token = if entity.is_a?(Customer)
          JsonWebToken.encode(customer_id: entity.id)
        else
          JsonWebToken.encode(user_id: entity.id)
        end

        render json: { token: token, message: 'Token regenerated successfully' }, status: :ok
      end

      # POST /api/v1/refresh_token
      # Exchange a valid refresh token for a new access token and a rotated refresh token
      def refresh_token
        raw_refresh = params[:refresh_token]
        return render json: { error: 'refresh_token is required' }, status: :bad_request if raw_refresh.blank?

        token_record = RefreshToken.find_valid_by_raw(raw_refresh)
        return render json: { error: 'Invalid or expired refresh token' }, status: :unauthorized if token_record.nil?

        entity = token_record.entity

        # Rotate refresh token
        new_raw, new_record = issue_refresh_token(entity)
        token_record.revoke!(replaced_by_token_hash: new_record.token_hash)

        # Issue access token
        access_token = if entity.is_a?(Customer)
          JsonWebToken.encode(customer_id: entity.id)
        else
          JsonWebToken.encode(user_id: entity.id)
        end

        payload = {
          token: access_token,
          refresh_token: new_raw,
          token_expires_in: 24.hours.to_i,
          refresh_token_expires_in: (new_record.expires_at - Time.current).to_i
        }

        if entity.is_a?(Customer)
          payload[:customer] = {
            id: entity.id,
            name: entity.name,
            address: entity.address,
            phone_number: entity.phone_number,
            email: entity.email,
            preferred_language: entity.preferred_language,
            delivery_time_preference: entity.delivery_time_preference,
            notification_method: entity.notification_method
          }
        else
          payload[:user] = {
            id: entity.id,
            name: entity.name,
            role: entity.role,
            email: entity.email,
            phone: entity.phone
          }
        end

        render json: payload, status: :ok
      end

      private

      def render_customer_response(customer)
        token = JsonWebToken.encode(customer_id: customer.id)
        refresh_token, refresh_record = issue_refresh_token(customer)
        render json: {
          token: token,
          refresh_token: refresh_token,
          token_expires_in: 24.hours.to_i,
          refresh_token_expires_in: (refresh_record.expires_at - Time.current).to_i,
          user_type: 'customer',
          customer: {
            id: customer.id,
            name: customer.name,
            address: customer.address,
            phone_number: customer.phone_number,
            email: customer.email,
            preferred_language: customer.preferred_language,
            delivery_time_preference: customer.delivery_time_preference,
            notification_method: customer.notification_method
          }
        }, status: :ok
      end

      def render_user_response(user)
        token = JsonWebToken.encode(user_id: user.id)
        refresh_token, refresh_record = issue_refresh_token(user)
        render json: {
          token: token,
          refresh_token: refresh_token,
          token_expires_in: 24.hours.to_i,
          refresh_token_expires_in: (refresh_record.expires_at - Time.current).to_i,
          user_type: user.role,
          user: {
            id: user.id,
            name: user.name,
            role: user.role,
            email: user.email,
            phone: user.phone
          }
        }, status: :ok
      end

      def render_customer_signup_response(customer)
        token = JsonWebToken.encode(customer_id: customer.id)
        refresh_token, refresh_record = issue_refresh_token(customer)
        render json: {
          token: token,
          refresh_token: refresh_token,
          token_expires_in: 24.hours.to_i,
          refresh_token_expires_in: (refresh_record.expires_at - Time.current).to_i,
          user_type: 'customer',
          customer: {
            id: customer.id,
            name: customer.name,
            address: customer.address,
            phone_number: customer.phone_number,
            email: customer.email,
            preferred_language: customer.preferred_language,
            delivery_time_preference: customer.delivery_time_preference,
            notification_method: customer.notification_method,
            latitude: customer.latitude,
            longitude: customer.longitude
          }
        }, status: :created
      end

      def render_user_signup_response(user)
        token = JsonWebToken.encode(user_id: user.id)
        refresh_token, refresh_record = issue_refresh_token(user)
        render json: {
          token: token,
          refresh_token: refresh_token,
          token_expires_in: 24.hours.to_i,
          refresh_token_expires_in: (refresh_record.expires_at - Time.current).to_i,
          user_type: user.role,
          user: {
            id: user.id,
            name: user.name,
            role: user.role,
            email: user.email,
            phone: user.phone
          }
        }, status: :created
      end

      def issue_refresh_token(entity)
        user_agent = request.user_agent
        ip_address = request.remote_ip
        RefreshToken.issue_for(entity, user_agent: user_agent, ip_address: ip_address)
      end

      def send_signup_notification(customer)
        begin
          # Send WhatsApp message to admin number
          admin_phone = "99728 08044"

          message = "New Customer Signup Alert, Name: #{customer.name}, Phone: #{customer.phone_number}, Email: #{customer.email || 'Not provided'}, Address: #{customer.address || 'Not provided'}, City: #{customer.city || 'Not provided'}, Registered: #{Time.current.strftime('%d/%m/%Y %I:%M %p')}"

          whatsapp_service = TwilioWhatsappService.new
          result = whatsapp_service.send_custom_message(admin_phone, message)

          Rails.logger.info "Signup notification sent to admin: #{result ? 'Success' : 'Failed'}"
        rescue => e
          Rails.logger.error "Failed to send signup notification: #{e.message}"
          # Don't fail the signup if notification fails
        end
      end

      def current_entity_from_token
        # BaseController#authenticate_request sets @current_user to User or Customer
        current_entity
      end

      def user_params
        params.permit(:name, :email, :phone, :password, :role)
      end

      def customer_params
        # Handle both nested and flat parameter structures
        auth_params = params[:authentication].present? ? params[:authentication] : params

        permitted_params = auth_params.permit(:name, :password, :address, :phone, :phone_number, :email, :latitude, :longitude,
                                            :preferred_language, :delivery_time_preference, :notification_method,
                                            :address_type, :address_landmark, :alt_phone_number, :city)

        # Map phone to phone_number if phone is provided but phone_number is not
        if permitted_params[:phone].present? && permitted_params[:phone_number].blank?
          permitted_params[:phone_number] = permitted_params[:phone]
        end

        # If address is missing but city is provided, use city as address
        if permitted_params[:address].blank? && permitted_params[:city].present?
          permitted_params[:address] = permitted_params[:city]
        end

        # If address is still blank, provide a default
        if permitted_params[:address].blank?
          permitted_params[:address] = "Address not provided"
        end

        permitted_params.except(:phone)
      end

      def unified_customer_signup_params
        # Handle both nested and flat parameter structures
        auth_params = params[:authentication].present? ? params[:authentication] : params

        permitted_params = auth_params.permit(:name, :email, :phone, :phone_number, :password, :password_confirmation, :address,
                                            :latitude, :longitude, :preferred_language, :delivery_time_preference,
                                            :notification_method, :address_type, :address_landmark, :alt_phone_number, :city)

        # Map phone to phone_number if phone is provided but phone_number is not
        if permitted_params[:phone].present? && permitted_params[:phone_number].blank?
          permitted_params[:phone_number] = permitted_params[:phone]
        end

        # If address is missing but city is provided, use city as address
        if permitted_params[:address].blank? && permitted_params[:city].present?
          permitted_params[:address] = permitted_params[:city]
        end

        # If address is still blank, provide a default
        if permitted_params[:address].blank?
          permitted_params[:address] = "Address not provided"
        end

        permitted_params.except(:phone)
      end

      def unified_user_signup_params
        # Handle both nested and flat parameter structures
        auth_params = params[:authentication].present? ? params[:authentication] : params

        permitted_params = auth_params.permit(:name, :email, :phone, :password, :password_confirmation)

        # Ensure required fields are present
        return permitted_params if permitted_params[:name].present? &&
                                  permitted_params[:password].present? &&
                                  (permitted_params[:email].present? || permitted_params[:phone].present?)

        permitted_params
      end

      def customer_signup_params
        # Handle both nested and flat parameter structures
        auth_params = params[:authentication].present? ? params[:authentication] : params

        permitted_params = auth_params.permit(:name, :email, :phone, :phone_number, :password, :password_confirmation, :address,
                                            :latitude, :longitude, :preferred_language, :delivery_time_preference,
                                            :notification_method, :address_type, :address_landmark, :alt_phone_number, :city)

        # Map phone to phone_number if phone is provided but phone_number is not
        if permitted_params[:phone].present? && permitted_params[:phone_number].blank?
          permitted_params[:phone_number] = permitted_params[:phone]
        end

        # If address is missing but city is provided, use city as address
        if permitted_params[:address].blank? && permitted_params[:city].present?
          permitted_params[:address] = permitted_params[:city]
        end

        # If address is still blank, provide a default
        if permitted_params[:address].blank?
          permitted_params[:address] = "Address not provided"
        end

        permitted_params.except(:phone)
      end
    end
  end
end