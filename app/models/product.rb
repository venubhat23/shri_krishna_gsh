class Product < ApplicationRecord
  # Validations
  validates :name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :unit_type, presence: true, inclusion: { 
    in: %w[liters kg pieces bottles packets],
    message: "%{value} is not a valid unit type" 
  }
  validates :price, presence: true, numericality: {
    greater_than: 0,
    message: "must be greater than 0"
  }
  validates :price_without_discount, presence: true, numericality: {
    greater_than: 0,
    message: "must be greater than 0"
  }
  validates :discount, numericality: {
    greater_than_or_equal_to: 0,
    less_than: 100,
    message: "must be between 0 and 100"
  }
  validates :description, length: { maximum: 5000 }

  # Set defaults and calculate price
  before_validation :set_pricing_defaults
  before_validation :calculate_discounted_price

  # Associations
  belongs_to :category
  has_many :delivery_items, dependent: :destroy
  has_many :deliveries, through: :delivery_items
  has_many :delivery_assignments, dependent: :destroy
  has_many :invoice_items, dependent: :destroy
  has_many :invoices, through: :invoice_items
  has_many :procurement_schedules, dependent: :destroy
  has_many :procurement_assignments, dependent: :destroy

  # Scopes
  scope :active, -> { where(is_active: true) }
  scope :available, -> { where('available_quantity > ?', 0) }
  scope :subscription_eligible, -> { where(is_subscription_eligible: true) }
  scope :low_stock, -> { where('available_quantity < ?', 10) }
  scope :in_stock, -> { where('available_quantity > ?', 0) }
  scope :by_unit_type, ->(unit) { where(unit_type: unit) }
  scope :by_category, ->(category_id) { where(category_id: category_id) }
  scope :search, ->(term) { where("name ILIKE ? OR description ILIKE ?", "%#{term}%", "%#{term}%") }

  # Performance optimized scopes
  scope :with_delivery_count, -> {
    left_joins(:delivery_assignments)
    .select('products.*, COUNT(delivery_assignments.id) as delivery_assignments_count')
    .group('products.id')
  }
  scope :popular, -> { joins(:delivery_assignments).group('products.id').order('COUNT(delivery_assignments.id) DESC') }

  # Instance methods
  def low_stock?
    available_quantity.to_f < 10
  end

  def out_of_stock?
    available_quantity.to_f <= 0
  end

  def stock_status
    if out_of_stock?
      'Out of Stock'
    elsif low_stock?
      'Low Stock'
    else
      'In Stock'
    end
  end

  def stock_status_class
    if out_of_stock?
      'danger'
    elsif low_stock?
      'warning'
    else
      'success'
    end
  end

  def total_value
    (available_quantity.to_f * price.to_f).round(2)
  end

  # Backward compatibility method
  def unit
    unit_type
  end

  def formatted_price
    "₹#{price.to_f.round(2)}"
  end

  def formatted_price_without_discount
    "₹#{price_without_discount.to_f.round(2)}"
  end

  def discount_amount
    return 0 unless price_without_discount.present? && discount.present?
    (price_without_discount.to_f * discount.to_f / 100).round(2)
  end

  def discount_percentage
    discount.to_f.round(2)
  end

  def has_discount?
    discount.present? && discount.to_f > 0
  end

  def display_name
    "#{name} (#{unit_type})"
  end

  def price_display
    if has_discount?
      "₹#{price} (#{discount}% off from ₹#{price_without_discount})"
    else
      "₹#{price}"
    end
  end

  def category_name
    category&.name || 'Uncategorized'
  end

  def category_color
    category&.color || '#6c757d'
  end

  # GST applicability check
  def is_gst_applicable?
    gst_rate.present? && gst_rate.to_f > 0
  end

  # GST calculation methods
  def total_gst_percentage
    return 0 unless is_gst_applicable?
    (cgst || 0) + (sgst || 0) + (igst || 0)
  end

  def total_cgst_percentage
    return 0 unless is_gst_applicable?
    cgst || 0
  end

  def total_sgst_percentage
    return 0 unless is_gst_applicable?
    sgst || 0
  end

  def total_igst_percentage
    return 0 unless is_gst_applicable?
    igst || 0
  end

  def cgst_amount_for(base_amount)
    return 0 unless is_gst_applicable?
    (base_amount * (cgst || 0) / 100).round(2)
  end

  def sgst_amount_for(base_amount)
    return 0 unless is_gst_applicable?
    (base_amount * (sgst || 0) / 100).round(2)
  end

  def igst_amount_for(base_amount)
    return 0 unless is_gst_applicable?
    (base_amount * (igst || 0) / 100).round(2)
  end

  def total_tax_amount_for(base_amount)
    return 0 unless is_gst_applicable?
    cgst_amount_for(base_amount) + sgst_amount_for(base_amount) + igst_amount_for(base_amount)
  end

  def amount_with_tax_for(base_amount)
    base_amount + total_tax_amount_for(base_amount)
  end

  # Class methods
  def self.total_value
    sum { |product| product.total_value }
  end

  def self.total_quantity
    sum(:available_quantity)
  end

  def self.unit_types_for_select
    [
      ['Liters', 'liters'],
      ['Kilograms', 'kg'],
      ['Pieces', 'pieces'],
      ['Bottles', 'bottles'],
      ['Packets', 'packets']
    ]
  end

  # Override as_json to exclude available_quantity from API responses but include discount info
  def as_json(options = {})
    super(options.merge(except: [:available_quantity])).merge({
      'discount_amount' => discount_amount,
      'has_discount' => has_discount?,
      'price_display' => price_display
    })
  end

  private

  def set_pricing_defaults
    # If price_without_discount is not set but price is, use price as the base
    if price_without_discount.blank? && price.present?
      self.price_without_discount = price
    end

    # Set default discount to 0 if not provided
    self.discount = 0 if discount.blank?
  end

  def calculate_discounted_price
    return unless price_without_discount.present?

    if discount.present? && discount.to_f > 0
      discount_amt = price_without_discount.to_f * discount.to_f / 100
      self.price = (price_without_discount.to_f - discount_amt).round(2)
    else
      self.price = price_without_discount.to_f
    end
  end
end