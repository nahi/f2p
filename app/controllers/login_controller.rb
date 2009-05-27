require 'httpclient'


class LoginController < ApplicationController
  after_filter :strip_heading_spaces
  after_filter :compress

  filter_parameter_logging :remote_key

  def index
    @tz = F2P::Config.timezone
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
      tz = param(:tz)
      if user = User.validate(name, remote_key)
        set_user(user)
        set_timezone(tz)
        flash[:message] = "You can change font size and other settings. Follow the 3rd 'gear' icon above."
        if params = session[:redirect_to_after_authenticate]
          session[:redirect_to_after_authenticate] = nil
          redirect_to url_for(params)
        else
          redirect_to :controller => 'entry'
        end
        return
      end
    end
    redirect_to :action => 'index'
  end
end
