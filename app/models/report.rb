class Report < ApplicationRecord
  belongs_to :user

  validates :name, presence: true
  validates :report_type, presence: true
  validates :from_date, presence: true
  validates :to_date, presence: true

  REPORT_TYPES = %w[gst sales enhanced_sales delivery customer product financial].freeze

  validates :report_type, inclusion: { in: REPORT_TYPES }

  scope :by_user, ->(user) { where(user: user) }
  scope :by_type, ->(type) { where(report_type: type) }
  scope :recent, -> { order(created_at: :desc) }

  def display_name
    "#{name} (#{from_date.strftime('%b %d')} - #{to_date.strftime('%b %d, %Y')})"
  end

  def date_range
    "#{from_date.strftime('%B %d, %Y')} to #{to_date.strftime('%B %d, %Y')}"
  end

  def type_display_name
    case report_type
    when 'gst'
      'GST Report'
    when 'sales'
      'Sales Report'
    when 'enhanced_sales'
      'Enhanced Sales Report'
    when 'delivery'
      'Delivery Report'
    when 'customer'
      'Customer Report'
    when 'product'
      'Product Performance Report'
    when 'financial'
      'Financial Summary Report'
    else
      report_type.humanize
    end
  end
end