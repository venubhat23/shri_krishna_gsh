class UsersController < ApplicationController
  skip_before_action :require_login, only: [:new, :create]
  before_action :require_login, only: [:delivery_people]

  def new
    @user = User.new
    render layout: false
  end

  def create
    @user = User.new(user_params)

    if @user.save
      session[:user_id] = @user.id
      flash[:notice] = "Account created successfully!"
      redirect_to root_path
    else
      render :new
    end
  end

  def delivery_people
    delivery_people = User.delivery_people.order(:name)

    respond_to do |format|
      format.json {
        render json: delivery_people.map { |person|
          {
            id: person.id,
            name: person.name
          }
        }
      }
    end
  end
  
  private
  
  def user_params
    params.require(:user).permit(:name, :email, :phone, :password, :password_confirmation, :role)
  end
end
