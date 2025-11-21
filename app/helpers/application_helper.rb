module ApplicationHelper
  # Business/App name helper
  def app_name
    @app_name ||= AdminSetting.current.business_name.presence || "Shri Krishna Goshala"
  end

  def app_business_name
    app_name
  end

  # Logo helper
  def app_logo_path
    "/Lord-Krishna-In-a-Forest-With-Cow-Natural-Image.jpg"
  end

  def app_logo_tag(options = {})
    default_options = {
      alt: "#{app_name} Logo",
      class: "logo"
    }
    options = default_options.merge(options)
    image_tag(app_logo_path, options)
  end

  # Existing helper methods...

  # Enhanced searchable select helper
  def searchable_select(form, attribute, options_collection, selected_value = nil, html_options = {})
    # Extract search configuration
    search_config = html_options.delete(:search) || {}
    search_type = search_config[:type] || 'local' # 'local' or 'ajax'
    ajax_url = search_config[:url]
    placeholder = search_config[:placeholder] || "Search #{attribute.to_s.humanize.downcase}..."
    allow_clear = search_config.fetch(:allow_clear, true)
    minimum_input_length = search_config[:minimum_input_length] || (search_type == 'ajax' ? 1 : 0)

    # Prepare HTML options
    html_options[:class] = "#{html_options[:class]} form-select".strip
    html_options[:data] ||= {}
    html_options[:data].merge!(
      controller: 'searchable-select',
      'searchable-select-search-type-value': search_type,
      'searchable-select-placeholder-value': placeholder,
      'searchable-select-allow-clear-value': allow_clear,
      'searchable-select-minimum-input-length-value': minimum_input_length,
      'searchable-select-target': 'select'
    )

    # Add AJAX URL if provided
    if search_type == 'ajax' && ajax_url
      html_options[:data]['searchable-select-url-value'] = ajax_url
    end

    # Generate the select field
    if form
      form.select(attribute, options_collection, { selected: selected_value }, html_options)
    else
      select_tag(attribute, options_from_collection_for_select(options_collection, :id, :name, selected_value), html_options)
    end
  end

  # Helper for customer dropdown with search
  def searchable_customer_select(form, attribute = :customer_id, selected_value = nil, html_options = {})
    customers = Customer.active.order(:name)
    options = options_from_collection_for_select(customers, :id, :name, selected_value)
    
    search_config = {
      type: 'local',
      placeholder: 'Search customers (e.g., "pr" for Pramod, Pradeep)...',
      allow_clear: true
    }
    
    html_options[:search] = search_config
    searchable_select(form, attribute, options, selected_value, html_options)
  end

  # Helper for product dropdown with search
  def searchable_product_select(form, attribute = :product_id, selected_value = nil, html_options = {})
    products = Product.active.order(:name)
    options = options_from_collection_for_select(products, :id, ->(p) { "#{p.name} - Rs#{p.price}" }, selected_value)
    
    search_config = {
      type: 'local',
      placeholder: 'Search products...',
      allow_clear: true
    }
    
    html_options[:search] = search_config
    searchable_select(form, attribute, options, selected_value, html_options)
  end

  # Helper for sales product dropdown with search
  def searchable_sales_product_select(form, attribute = :sales_product_id, selected_value = nil, html_options = {})
    sales_products = SalesProduct.active.order(:name)
    options = options_from_collection_for_select(sales_products, :id, ->(p) { "#{p.name} - Rs#{p.price}" }, selected_value)
    
    search_config = {
      type: 'local',
      placeholder: 'Search sales products...',
      allow_clear: true
    }
    
    html_options[:search] = search_config
    searchable_select(form, attribute, options, selected_value, html_options)
  end

  # Helper for user/delivery person dropdown with search
  def searchable_user_select(form, attribute = :user_id, role = nil, selected_value = nil, html_options = {})
    users = User.active
    users = users.where(role: role) if role
    users = users.order(:name)
    options = options_from_collection_for_select(users, :id, :name, selected_value)
    
    search_config = {
      type: 'local',
      placeholder: "Search #{role || 'users'}...",
      allow_clear: true
    }
    
    html_options[:search] = search_config
    searchable_select(form, attribute, options, selected_value, html_options)
  end

  # Helper for category dropdown with search
  def searchable_category_select(form, attribute = :category_id, selected_value = nil, html_options = {})
    categories = Category.active.order(:name)
    options = options_from_collection_for_select(categories, :id, :name, selected_value)
    
    search_config = {
      type: 'local',
      placeholder: 'Search categories...',
      allow_clear: true
    }
    
    html_options[:search] = search_config
    searchable_select(form, attribute, options, selected_value, html_options)
  end

  # Helper for any model dropdown with search
  def searchable_model_select(form, attribute, model_class, display_method = :name, selected_value = nil, html_options = {})
    records = model_class.respond_to?(:active) ? model_class.active.order(display_method) : model_class.order(display_method)
    options = options_from_collection_for_select(records, :id, display_method, selected_value)
    
    search_config = {
      type: 'local',
      placeholder: "Search #{model_class.name.downcase.pluralize}...",
      allow_clear: true
    }
    
    html_options[:search] = search_config
    searchable_select(form, attribute, options, selected_value, html_options)
  end

  def enhanced_date_picker(form, field, html_options = {})
    date_options = {
      mode: html_options.delete(:mode) || "single",
      min_date: html_options.delete(:min_date),
      max_date: html_options.delete(:max_date),
      enable_time: html_options.delete(:enable_time) || false,
      date_format: html_options.delete(:date_format),
      alt_format: html_options.delete(:alt_format),
      default_date: html_options.delete(:default_date),
      disable: html_options.delete(:disable),
      enable: html_options.delete(:enable),
      inline: html_options.delete(:inline) || false
    }

    # Remove nil values from date_options
    date_options.compact!

    # Build data attributes for Stimulus controller
    data_attributes = {
      controller: "date-picker"
    }

    date_options.each do |key, value|
      data_attributes["date-picker-#{key.to_s.gsub('_', '-')}-value"] = value
    end

    # Merge with existing data attributes
    html_options[:data] ||= {}
    html_options[:data].merge!("date-picker-target" => "input")

    content_tag :div, data: data_attributes do
      if html_options.delete(:type) == :datetime
        form.datetime_local_field(field, html_options)
      else
        form.date_field(field, html_options)
      end
    end
  end

  def enhanced_form_group(label_text, options = {}, &block)
    css_classes = ["form-group-enhanced"]
    css_classes << options[:class] if options[:class]

    content_tag :div, class: css_classes.join(" ") do
      content = ""
      if label_text
        content += content_tag(:label, label_text, class: "form-label")
      end
      content += capture(&block) if block_given?
      content.html_safe
    end
  end

  def status_badge(status, options = {})
    badge_classes = case status.to_s.downcase
    when 'pending'
      'badge bg-warning text-dark'
    when 'in_progress', 'active'
      'badge bg-info text-white'
    when 'completed', 'success'
      'badge bg-success text-white'
    when 'cancelled', 'failed'
      'badge bg-danger text-white'
    when 'draft'
      'badge bg-secondary text-white'
    else
      'badge bg-light text-dark'
    end

    badge_classes += " #{options[:class]}" if options[:class]

    content_tag :span, status.humanize, class: badge_classes
  end

  def loading_spinner(options = {})
    size = options[:size] || 'normal'
    text = options[:text] || 'Loading...'
    
    spinner_class = case size
    when 'small'
      'spinner-border spinner-border-sm'
    when 'large'
      'spinner-border spinner-border-lg'
    else
      'spinner-border'
    end

    content_tag :div, class: "d-flex align-items-center" do
      content = content_tag(:div, "", class: "#{spinner_class} text-primary me-2", role: "status")
      content += content_tag(:span, text) if text
      content
    end
  end

  def enhanced_card(title, options = {}, &block)
    card_classes = ["card"]
    card_classes << options[:class] if options[:class]
    
    content_tag :div, class: card_classes.join(" ") do
      content = ""
      
      if title || options[:header]
        content += content_tag(:div, class: "card-header") do
          if title
            content_tag(:h5, title, class: "card-title mb-0")
          else
            options[:header]
          end
        end
      end
      
      content += content_tag(:div, class: "card-body") do
        capture(&block) if block_given?
      end
      
      content.html_safe
    end
  end

  def quick_action_button(text, path, options = {})
    button_class = "btn btn-sm #{options[:variant] || 'btn-outline-primary'}"
    icon = options[:icon]
    method = options[:method] || :get
    confirm = options[:confirm]

    link_options = {
      class: button_class,
      method: method
    }
    link_options[:data] = { confirm: confirm } if confirm

    link_to path, link_options do
      content = ""
      content += content_tag(:i, "", class: "#{icon} me-1") if icon
      content += text
      content.html_safe
    end
  end
end
