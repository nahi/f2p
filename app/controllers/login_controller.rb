require 'httpclient'


class LoginController < ApplicationController
  after_filter :strip_heading_spaces
  after_filter :compress

  filter_parameter_logging :remote_key

  def index
    if ensure_login
      redirect_to :controller => 'entry'
    end
  end

  def clear
    if ensure_login
      logout
    end
    redirect_to :action => 'index'
  end

  def authenticate
    if request.method == :post
      name = param(:name)
      remote_key = param(:remote_key)
      if User.validate(name, remote_key)
        # TODO: protect it with transaction
        if user = User.find_by_name(name)
          user.remote_key = remote_key
        else
          user = User.new
          user.name = name
          user.remote_key = remote_key
        end
        unless user.save
          flash[:error] = 'illegal auth credentials given'
          render :action => 'index'
        end
        set_user(user)
        redirect_to :controller => 'entry'
        return
      end
    end
    redirect_to :action => 'index'
  end
end
