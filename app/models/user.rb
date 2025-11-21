class User < ApplicationRecord
  has_secure_password
  
  # Existing associations
  has_many :delivery_assignments, dependent: :destroy
  has_many :delivery_schedules, dependent: :destroy
  has_many :parties, dependent: :destroy
  has_many :advertisements, dependent: :destroy
  
  # Procurement associations
  has_many :procurement_schedules, dependent: :destroy
  has_many :procurement_assignments, dependent: :destroy
  has_many :procurement_invoices, dependent: :destroy
  
  # Reports association
  has_many :reports, dependent: :destroy
  
  # New associations for delivery person functionality
  has_many :assigned_customers, class_name: 'Customer', foreign_key: 'delivery_person_id', dependent: :nullify
  has_many :deliveries, foreign_key: 'delivery_person_id', dependent: :destroy

  # User's own customers and pending payments
  has_many :customers, dependent: :destroy
  has_many :pending_payments, dependent: :destroy
  
  # Enum for roles
  enum :role, {
    user: 0,
    admin: 1,
    delivery_person: 2,
    customer: 3
  }

  # Validations
  validates :name, presence: true
  validates :email, presence: true, uniqueness: true
  validates :role, presence: true
  validates :phone, presence: true
  validates :employee_id, uniqueness: true, allow_blank: true
  
  # Scopes
  scope :delivery_people, -> { where(role: 'delivery_person') }
  scope :admins, -> { where(role: 'admin') }
  scope :regular_users, -> { where(role: 'user') }

  # Performance optimized scopes
  scope :delivery_people_with_customer_counts, -> {
    delivery_people.left_joins(:assigned_customers)
                   .select('users.*, COUNT(customers.id) as customers_count')
                   .group('users.id')
  }
  scope :with_assignments_for_date, ->(date) {
    joins(:delivery_assignments).where(delivery_assignments: { scheduled_date: date })
  }
  
  # Instance methods
  def delivery_person?
    role == 'delivery_person'
  end
  
  def admin?
    role == 'admin'
  end
  
  def customer?
    role == 'customer'
  end
  
  
  
  def customer_count
    if delivery_person?
      # Use cached count if available from scope, otherwise query
      try(:customers_count) || assigned_customers.count
    else
      0
    end
  end

  def available_customer_slots
    return 0 unless delivery_person?
    [200 - customer_count, 0].max
  end

  def can_take_customers?
    return false unless delivery_person?
    customer_count < 200
  end
  
  # Get unassigned customers for assignment
  def self.unassigned_customers
    Customer.where(delivery_person_id: nil)
  end
  
  # Get available delivery people (those with less than 200 customers)
  def self.available_delivery_people
    delivery_people.joins("LEFT JOIN customers ON customers.delivery_person_id = users.id")
                   .group("users.id")
                   .having("COUNT(customers.id) < 200")
  end
  
  # Add image_url method for delivery people
  def image_url
    # Return nil or a default image URL since users table doesn't have image_url column
    # You can customize this to return a default avatar or implement image upload later
    nil
  end
end
