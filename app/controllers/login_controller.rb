require 'httpclient'


class LoginController < ApplicationController
  filter_parameter_logging :remote_key

  def index
    if ensure_login
      redirect_to :controller => 'entry'
    end
  end

  def clear
    logout
    redirect_to :action => 'index'
  end

  def authenticate
    if request.method == :post
      name = param(:name)
      remote_key = param(:remote_key)
      if User.validate(name, remote_key)
        user = User.new
        user.name = name
        user.remote_key = remote_key
        unless user.save
          flash[:error] = 'illegal auth credentials given'
          redirect_to :action => 'index'
        end
        set_user(user)
        redirect_to :controller => 'entry'
        return
      end
    end
    redirect_to :action => 'index'
  end
end
