Rails.application.routes.draw do
  # Favicon route to prevent 404 errors
  get '/favicon.ico', to: proc { [204, {}, []] }

  # Admin interface
  namespace :admin do
    resources :affiliates do
      member do
        patch :approve
        patch :suspend
      end
    end
    resources :referrals, only: [:index, :show] do
      member do
        patch :approve
        patch :reject
      end
    end
  end

  # Affiliate Authentication and Management
  namespace :affiliate do
    get 'login', to: 'sessions#new'
    post 'login', to: 'sessions#create'
    delete 'logout', to: 'sessions#destroy'
    get 'dashboard', to: 'dashboard#index'

    resources :products, only: [:index, :show]

    # Shopping cart routes
    get 'cart', to: 'cart#index'
    post 'cart/add', to: 'cart#add'
    patch 'cart/update', to: 'cart#update'
    delete 'cart/remove', to: 'cart#remove'
    delete 'cart/clear', to: 'cart#clear'
    get 'cart/checkout', to: 'cart#checkout'
    post 'cart/place_order', to: 'cart#place_order'

    resources :bookings
    resources :referrals do
      member do
        patch :cancel
      end
    end
  end

  # Franchise Management (Admin)
  resources :franchises do
    member do
      patch :reset_password
      patch :toggle_status
    end
    resources :franchise_bookings, path: 'bookings'
  end

  # Franchise main interface (for logged-in franchises)
  resources :franchise_bookings_main, path: 'my-bookings', only: [:index, :show, :new, :create, :edit, :update, :destroy]

  # Franchise Authentication
  namespace :franchise do
    get 'login', to: 'sessions#new'
    post 'login', to: 'sessions#create'
    delete 'logout', to: 'sessions#destroy'
    get 'dashboard', to: 'dashboard#index'
    get 'profile', to: 'profile#show'
    patch 'profile', to: 'profile#update'
    resources :bookings, controller: 'franchise_bookings'
  end
  # Congratulations page
  get '/congratulations', to: 'congratulations#show'
  resources :ai_insights, path: 'ai-insights', only: [:index] do
    collection do
      get :reorder_suggestions
      get :churn_predictions
      post :send_reorder_notification
      post :send_churn_prevention
      get :demand_forecasting
      get :customer_lifetime_value
      get :smart_pricing
      get :seasonal_patterns
      get :product_recommendations
      get :route_optimization
      get :customer_segmentation
      get :revenue_anomalies
    end
  end
  resources :customer_points, path: 'customer-points', only: [:index, :show]

  # Customer Wallets Management
  resources :customer_wallets, path: 'customer-wallets' do
    member do
      patch :add_funds
      patch :deduct_funds
    end
  end

  # Payouts Management
  resources :payouts do
    collection do
      get :statistics
    end
  end
  # Handle Chrome DevTools requests with a simple 404 response
  get "/.well-known/appspecific/com.chrome.devtools.json", to: proc { [404, {}, ['']] }
  # Customer Patterns Analysis
  resources :customer_patterns, path: 'customer-patterns', only: [:index] do
    collection do
      get :customer_deliveries
      post :complete_till_today
      post :complete_all
      post :complete_all_pending
      post :complete_all_pending_till_today
      get :get_pending_count
      post :complete_all_till_today
      post :remove_all_assignments
      post :update_pattern
      get :get_products
      get :get_delivery_people
      get :get_assignment_summary
      get :search_customers
      post :bulk_edit_assignments
      delete :bulk_delete_assignments
      get :revenue_breakdown
    end

    member do
      get :edit_assignment
      patch :update_assignment
      delete :delete_assignment
    end
  end
  get "customer_details", to: "customer_details#index"
  post "customer_details/copy_from_last_month", to: "customer_details#copy_from_last_month"
  root 'dashboard#index'

  # Orders routes
  resources :orders, only: [:index]
  
  # Dashboard analytics endpoint
  get '/dashboard/delivery_analytics', to: 'dashboard#delivery_analytics'
  
  # Authentication routes
  get '/login', to: 'sessions#new'
  post '/login', to: 'sessions#create'
  delete '/logout', to: 'sessions#destroy'
  
  get '/signup', to: 'users#new'
  post '/signup', to: 'users#create'

  # Routes for modal dropdown data
  get '/users/delivery_people', to: 'users#delivery_people'

  # API routes for searchable dropdowns
  namespace :api do
    get 'customers/search', to: 'customers#search'
    get 'sales_customers/search', to: 'sales_customers#search'
    get 'products/search', to: 'products#search'
    get 'sales_products/search', to: 'sales_products#search'
    get 'users/search', to: 'users#search'
    get 'delivery_people/search', to: 'users#search_delivery_people'
    get 'categories/search', to: 'categories#search'
    get 'parties/search', to: 'parties#search'

    # Instagram Analytics API
    get 'instagram/posts/:id', to: 'instagram_analytics#post_details'

    # File Upload API
    post 'upload/:folder_name', to: 'upload#create'
    post 'upload', to: 'upload#create'  # Default route without folder
    
    # Settings API routes
    namespace :v1 do
      resources :settings, only: [:index] do
        collection do
          # FAQ endpoints
          get :faq
          post 'faq/ask', to: 'settings#ask_question'
          
          # CMS endpoints
          get 'cms/terms-of-service', to: 'settings#terms'
          get 'cms/privacy-policy', to: 'settings#privacy'
          
          # Contact/Support endpoints
          post :contact
          
          # Preferences endpoints
          get :referral
          get 'delivery-preferences', to: 'settings#delivery_preferences'
          put 'preferences', to: 'settings#update_preferences'
          put 'language', to: 'settings#update_language'
          
          # Address endpoints
          get :addresses
          post :addresses, to: 'settings#create_address'
          put 'addresses/:id', to: 'settings#update_address'
          delete 'addresses/:id', to: 'settings#delete_address'
          post 'addresses/:id/set_default', to: 'settings#set_default_address'
        end
      end
    end
  end
  
  # Main application routes with full CRUD
  resources :products do
    collection do
      get :assign_categories
      patch :update_categories
    end
  end
  resources :categories
  resources :coupons
  resources :customers do
    collection do
      get :search_suggestions
      get :bulk_import
      post :process_bulk_import
      post :validate_csv
      get :download_template
      get :enhanced_bulk_import
      post :process_enhanced_bulk_import
      post :validate_enhanced_csv
      get :download_enhanced_template
    end
    
    member do
      patch :reassign_delivery_person
    end
  end
  
  # Customer preferences nested routes for easy access from customer pages
  resources :customers do
    member do
      get 'preferences/edit', to: 'customer_preferences#edit_for_customer'
      get 'preferences/new', to: 'customer_preferences#new_for_customer'
    end
  end
  
  resources :advertisements
  
  resources :parties do
    collection do
      get :bulk_import
      post :process_bulk_import
      post :validate_csv
      get :download_template
    end
  end
  
  # Purchase Products System
  resources :purchase_products do
    collection do
      get :search
    end
    member do
      patch :mark_as_paid
    end
  end
  
  # Sales Products System (NEW)
  resources :sales_products do
    collection do
      get :search
    end
  end
  
  # Purchase Invoices
  resources :purchase_invoices do
    member do
      patch :mark_as_paid
      get :mark_as_paid
      patch :add_payment
      get :download_pdf
    end
    
    collection do
      post :bulk_upload
    end
  end
  
  # Purchase Customers
  resources :purchase_customers do
    collection do
      get :search
    end
  end
  
  # Sales Invoices (NEW)
  resources :sales_invoices do
    member do
      patch :mark_as_paid
      get :mark_as_paid
      get :download_pdf
      get :get_product_details
      get :get_customer_details
    end
    
    collection do
      get :profit_analysis
      get :sales_analysis
      get 'products/:id/details', to: 'sales_invoices#get_product_details', as: 'product_details'
      get 'customers/:id/details', to: 'sales_invoices#get_customer_details', as: 'customer_details'
    end
  end
  
  # Sales Customers
  resources :sales_customers do
    collection do
      get :search
    end
  end
  
  # Delivery People Management
  resources :delivery_people, path: 'delivery-person' do
    member do
      get :assign_customers
      patch :update_assignments
      patch :unassign_customers
      get :manage_customers
      patch :update_customer_assignments
      delete :unassign_customer
    end
    
    collection do
      post :bulk_assign
      get :statistics
    end
  end
  
  # JSON API for delivery people (for dropdowns)
  get '/delivery_people', to: 'delivery_people#index', defaults: { format: :json }
  
  # Delivery Assignments (consolidated - removed duplicate)
  resources :delivery_assignments, path: 'assign_deliveries' do
    member do
      patch :complete
      patch :cancel
      patch :update
      delete :destroy
    end

    collection do
      get :bulk, path: 'bulk-automate'
      post :process_bulk_assignments, path: 'bulk-process', as: 'process_bulk_assignments'
      post :bulk_complete, path: 'bulk-complete'
      get :search_suggestions
      get :filtered, path: 'filtered'
      post :unassign_customer
    end
  end
  
  # Delivery Schedules
  resources :delivery_schedules, path: 'schedules' do
    member do
      patch :generate_assignments
      patch :cancel_schedule
    end
    
    collection do
      post :create_bulk
    end
  end
  
  # Schedules Management
  resources :schedules, only: [:index] do
    collection do
      post :create_schedule
      post :import_last_month
      post :import_selected_month
    end
  end
  
  # Deliveries (for delivery person records)
  resources :deliveries do
    member do
      patch :update_status
    end
  end
  
  # Invoices with comprehensive functionality
  resources :invoices do
    member do
      patch :mark_as_paid
      patch :mark_as_completed
      patch :convert_to_completed
      post :share_whatsapp
      post :send_email
      get :download_pdf
      get :delivery_assignments
      patch :recalculate
    end

    collection do
      get :quick
      get :generate
      post :generate
      post :bulk_share_whatsapp
      get :monthly_preview
      get :generate_monthly_for_all
      post :generate_monthly_for_all
      post :process_invoice_batch
      get :customers_for_month
      get :search_suggestions
      get :export_for_whatsapp
      post :generate_and_send_whatsapp
      get :download_customer_list
      post :create_sidebar_invoice
      get :get_products
    end
  end

  # Pending Payments Management
  resources :pending_payments, path: 'pending-payments' do
    member do
      patch :mark_as_paid
      get :mark_as_paid
      patch :mark_as_pending
      get :mark_as_pending
    end

    collection do
      get :search_customers
      get :total_pending_amount
    end
  end

  # Public invoice view (no authentication required)
  get '/invoice/:token', to: 'invoices#public_view', as: 'public_invoice'
  get '/invoice/:token/download', to: 'invoices#public_download_pdf', as: 'public_invoice_download', defaults: { format: :pdf }

  # Public invoices list (no authentication required)
  get '/invoices_public', to: 'public_invoices#index', as: 'public_invoices'
  patch '/invoices_public/:id/complete', to: 'public_invoices#complete', as: 'public_invoice_complete'
  delete '/invoices_public/:id', to: 'public_invoices#destroy', as: 'public_invoice_delete'

  # Public PDF serving for WhatsApp (no authentication required)
  get '/invoices/pdf/:filename', to: 'invoices#serve_pdf', as: 'serve_invoice_pdf'

  # S3 Proxy routes (serve S3 files through your domain)
  get '/files/invoices/:token/:filename', to: 's3_proxy#serve_invoice_pdf', as: 'proxy_invoice_pdf'

  # Clean URL pattern for invoices: /invoices/123.pdf -> S3 proxy
  get '/invoices/:filename', to: 'invoice_files#show', constraints: { filename: /.*\.pdf/ }, as: 'invoice_file'
  
  # Admin Settings
  resources :admin_settings, path: 'admin-settings' do
    collection do
      post :cleanup_tokens
      get :export_data
    end
  end

  # Sidebar Configuration
  resources :sidebar_configurations, path: 'sidebar-config', only: [:index] do
    collection do
      patch :update
    end
  end
  
  # Reports
  resources :reports, only: [:index, :show] do
    collection do
      post :generate_gst_report
      post :generate_sales_report
      post :generate_enhanced_sales_report
      post :generate_delivery_report
      post :generate_customer_report
      post :generate_product_report
      post :generate_financial_report
    end
    member do
      get :download_pdf
    end
  end
  
  # Milk Supply & Analytics routes
  resources :procurement_schedules, path: 'milk-procurement' do
    member do
      patch :generate_assignments
    end
    collection do
      post :send_monthly_invoices
    end
    
    collection do
      get :analytics
    end
  end
  
  resources :procurement_assignments, path: 'milk-assignments' do
    member do
      patch :complete
      patch :cancel
    end

    collection do
      patch :bulk_update
      post :complete_till_today
      get :calendar
      get :daily_report
      get :analytics_data
    end
  end
  
  # Main Milk Analytics Dashboard
  resources :milk_analytics, path: 'milk-supply-analytics', only: [:index] do
    collection do
      get :calendar_view
      get :vendor_analysis
      get :profit_analysis
      get :inventory_analysis
      get :generate_reports
      get :saved_reports
      get :last_month_schedules
      post :generate_procurement_for_current_month
      get :procurement_invoice
      post :generate_purchase_invoice
      get :preview_purchase_invoice
      get :get_schedule_invoice_status
      post :generate_procurement_invoice
      get :view_schedule_invoice
      get :download_procurement_invoice_pdf
      get :show_procurement_invoice
      get :show_procurement_assignments
      post :create_procurement_invoices_for_all
      post :mark_assignments_completed
      post :create_schedule
      patch :update_schedule
      delete :destroy_schedule
      get :get_schedule
      get :filter_schedules_by_month
      post :procurement_schedules_data
      post :copy_schedules_from_last_month
      delete :delete_individual_schedule
    end
    
    member do
      get :show_report
    end
  end

  # File Upload API
  post '/api/upload', to: 'uploads#create'
  
  # API routes
  namespace :api do
    namespace :v1 do
      # Authentication routes
      post '/signup', to: 'authentication#signup'
      post '/login', to: 'authentication#login'
      post '/customer_login', to: 'authentication#customer_login'
      post '/customer_signup', to: 'authentication#customer_signup'
      post '/regenerate_token', to: 'authentication#regenerate_token'
      post '/refresh_token', to: 'authentication#refresh_token'

      # Categories routes
      resources :categories, only: [:index, :show, :create, :update, :destroy]

      # Customers routes
      resources :customers, only: [:index, :show, :create] do
        member do
          post :update_location
          put :settings, action: :update_settings
        end
      end

      # Customer Address routes
      post '/customer_address', to: 'customer_addresses#create'
      get '/customer_address/:id', to: 'customer_addresses#show'
      put '/customer_address/:id', to: 'customer_addresses#update'
      patch '/customer_address/:id', to: 'customer_addresses#update'
      delete '/customer_address/:id', to: 'customer_addresses#destroy'
      get '/customer_addresses', to: 'customer_addresses#index'

      # Products routes
      resources :products do
        collection do
          get :low_stock
        end
      end

      # Orders routes (single-day orders)
      post '/place_order', to: 'orders#place_order'
      get '/orders', to: 'orders#index'

      # Advertisements routes
      resources :advertisements, only: [:index]

      # Invoices routes
      resources :invoices, only: [:index]

      # Subscriptions routes (multi-day subscriptions)
      resources :subscriptions, only: [:index, :create, :update, :destroy]

      # Delivery assignments routes
      resources :delivery_assignments, only: [:index, :show] do
        collection do
          get :today
          post :start_nearest
          post :bulk_complete  # New bulk completion API
        end

        member do
          post :complete
          post :add_items
          post :mark_completed  # New simple API
        end

        # Nested delivery items
        resources :delivery_items, only: [:index, :create], shallow: true
      end

      # Delivery schedules routes (for admin/delivery person management)
      resources :delivery_schedules, only: [:index, :show, :create, :update, :destroy]

      # Delivery items routes (for individual item operations)
      resources :delivery_items, only: [:show, :update, :destroy]

      # Bank details route
      get '/bank_details', to: 'bank_details#show'

      # Settings routes (updated to include more endpoints)
      resources :settings, only: [:index] do
        collection do
          # FAQ endpoints
          get :faq
          post 'faq/ask', to: 'settings#ask_question'

          # CMS endpoints
          get 'cms/terms-of-service', to: 'settings#terms'
          get 'cms/privacy-policy', to: 'settings#privacy'

          # Contact/Support endpoints
          post :contact

          # Preferences endpoints
          get :referral
          get 'delivery-preferences', to: 'settings#delivery_preferences'
          put 'preferences', to: 'settings#update_preferences'
          put 'language', to: 'settings#update_language'

          # Address endpoints
          get :addresses
          post :addresses, to: 'settings#create_address'
          put 'addresses/:id', to: 'settings#update_address'
          delete 'addresses/:id', to: 'settings#delete_address'
          post 'addresses/:id/set_default', to: 'settings#set_default_address'
        end
      end

      # Vacation routes
      resources :vacations, only: [:index, :show, :create, :destroy] do
        member do
          patch :pause
          patch :unpause
        end
        collection do
          post :dry_run, to: 'vacations#dry_run'
          post :complete_ended, to: 'vacations#complete_ended'
        end
      end

      # Legacy delivery routes (keeping for backward compatibility)
      scope :deliveries do
        post '/start', to: 'deliveries#start'
        post '/:id/complete', to: 'deliveries#complete'
        get '/customers', to: 'deliveries#customers'
        get '/today_summary', to: 'deliveries#today_summary'

        # Catch-all for partial delivery URLs
        match '/:id/*path', to: 'deliveries#api_not_found', via: :all
        match '*path', to: 'deliveries#api_not_found', via: :all
      end
    end

    # Catch-all route for unmatched API v1 paths
    match 'v1/*path', to: 'application#api_not_found', via: :all
  end

  # Catch-all route for unmatched API paths
  match 'api/*path', to: 'application#api_not_found', via: :all
  
  # Delivery Review
  get '/delivery-review', to: 'delivery_review#index'
  get '/delivery-review/data', to: 'delivery_review#data'
  post '/delivery-review/export', to: 'delivery_review#export'
  post '/delivery-review/bulk-complete', to: 'delivery_review#bulk_complete'
  patch '/delivery-review/:id', to: 'delivery_review#update'
  delete '/delivery-review/:id', to: 'delivery_review#destroy'
  
  # Settings Management
  resources :faqs do
    member do
      patch :activate
      patch :deactivate
      patch :move_up
      patch :move_down
    end
    
    collection do
      patch :reorder
    end
  end
  
  resources :cms_pages, path: 'content-pages' do
    member do
      patch :publish
      patch :unpublish
      patch :schedule_publish
    end
  end
  
  resources :support_tickets, path: 'support' do
    member do
      patch :resolve
      patch :reopen
    end
  end
  
  resources :referral_codes, path: 'referrals', only: [:index, :show, :destroy] do
    collection do
      get :leaderboard
    end
  end
  
  # Customer preferences and addresses management
  resources :customer_preferences, path: 'customer-preferences' do
    collection do
      patch :bulk_update_notifications
    end
  end
  
  resources :customer_addresses, path: 'customer-addresses' do
    member do
      patch :set_default
    end
    
    collection do
      post :bulk_import
    end
  end
  
  # Nested customer addresses
  resources :customers do
    resources :customer_addresses, path: 'addresses', except: [:show]
  end

  # WhatsApp Messaging
  resources :whatsapp_messages, path: 'whatsapp-messages', only: [:index] do
    collection do
      get :search_customers
      post :send_individual_message
      get :unpaid_customers_data
      post :send_unpaid_customers_message
      get :total_customers_count
      get :total_customers_data
      post :send_wishes_to_all
    end
  end

  # Public invitation page for app integration
  get '/integration-invite', to: 'public#invitation', as: 'integration_invitation'

  # Public product launch page for chief guest
  get '/product-launch', to: 'public#launch', as: 'product_launch'

  # Public product showcase page
  get '/product-showcase', to: 'public#product', as: 'product_showcase'

  # Atma Nirbhar Farm launch page
  get '/atma-nirbhar-farm', to: 'public#atma_nirbhar', as: 'atma_nirbhar_farm'

  # App launch notification API
  post '/send-app-launch-notifications', to: 'public#send_app_launch_notifications', as: 'send_app_launch_notifications'

  # Welcome landing page
  get '/welcome', to: 'public#welcome', as: 'welcome_page'

  # Webhook endpoints - direct routes to WebhooksController
  post '/webhooks/twilio/whatsapp', to: 'webhooks#twilio_whatsapp'
  post '/webhooks/twilio/status', to: 'webhooks#twilio_status'
end