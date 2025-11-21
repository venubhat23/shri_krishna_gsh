class PublicController < ApplicationController
  skip_before_action :require_login

  def invitation
    # This is a public page, no authentication required
    # The view is rendered automatically from app/views/public/invitation.html.erb
  end

  def launch
    # This is the product launch page for chief guest activation
    # The view is rendered automatically from app/views/public/launch.html.erb
  end

  def product
    # This is the farm-themed product showcase page
    # The view is rendered automatically from app/views/public/product.html.erb
  end

  def atma_nirbhar
    # This is the business launch page with ribbon cutting
    # The view is rendered automatically from app/views/public/atma_nirbhar.html.erb
  end

  def welcome
    # This is the welcome landing page for the business
    # The view is rendered automatically from app/views/public/welcome.html.erb
  end

  def send_app_launch_notifications
    begin
      # Send app launch notifications to all customers asynchronously
      result = AppLaunchNotificationService.send_to_all_customers

      render json: {
        success: result[:success],
        message: result[:message],
        total_customers: result[:total_customers],
        success_count: result[:success_count],
        failure_count: result[:failure_count]
      }

    rescue => e
    end
  end
end