class ProductsController < ApplicationController
  before_action :require_login
  before_action :set_product, only: [:show, :edit, :update, :destroy]

  def index
    @products = Product.includes(:category).all.order(:name)
    @products = @products.by_category(params[:category]) if params[:category].present?
    @products = @products.search(params[:search]) if params[:search].present?
    @total_products = @products.count
    @categories = Category.all.order(:name)

    respond_to do |format|
      format.html
      format.json {
        render json: @products.map { |product|
          {
            id: product.id,
            name: product.name,
            price: product.price
          }
        }
      }
    end
  end

  def show
  end

  def new
    @product = Product.new
  end

  def create
    @product = Product.new(product_params)

    if @product.save
      redirect_to product_path(@product), notice: 'Product was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @product.update(product_params)
      redirect_to product_path(@product), notice: 'Product was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @product.destroy
    redirect_to products_url, notice: 'Product was successfully deleted.'
  end

  def assign_categories
    @products = Product.includes(:category).all.order(:name)
    @categories = Category.all.order(:name)
    @selected_category = params[:category_id] if params[:category_id].present?
    @filtered_products = @products.where(category_id: @selected_category) if @selected_category.present?
  end

  def update_categories
    product_ids = params[:product_ids] || []
    category_id = params[:category_id]
    
    if product_ids.any?
      products = Product.where(id: product_ids)
      
      if category_id.present?
        products.update_all(category_id: category_id)
        category_name = Category.find(category_id).name
        flash[:notice] = "Successfully assigned #{products.count} products to #{category_name} category."
      else
        products.update_all(category_id: nil)
        flash[:notice] = "Successfully removed category from #{products.count} products."
      end
    else
      flash[:alert] = "Please select at least one product to assign."
    end
    
    redirect_to assign_categories_products_path
  end

  private

  def set_product
    @product = Product.find(params[:id])
  end

  def product_params
    params.require(:product).permit(
      :name, :description, :unit_type, :price_without_discount, :discount,
      :category_id, :image_url, :hsn_sac, :cgst, :sgst, :igst, :gst_rate,
      :available_quantity, :is_active, :is_subscription_eligible
    )
  end
end