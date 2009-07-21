require 'httpclient'
require 'oauth'


class LoginController < ApplicationController
  before_filter :verify_authenticity_token
  after_filter :strip_heading_spaces
  after_filter :compress

  filter_parameter_logging :remote_key

  def index
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
      if user = User.validate(name, remote_key)
        login_successful(user)
        return
      end
    end
    redirect_to :controller => :entry, :action => :inbox
  end

  def initiate_oauth_login
    redirect_to request_token.authorize_url
  end

  def oauth_callback
    oauth_token = params[:oauth_token]
    session_token = session[:request_token]
    if oauth_token == session_token
      request_token = OAuth::RequestToken.new(create_oauth_consumer, oauth_token, session[:request_token_secret])
      access_token = request_token.get_access_token
      name = access_token.params[:username]
      token = access_token.params[:oauth_token]
      secret = access_token.params[:oauth_token_secret]
      if user = User.oauth_validate(name, token, secret)
        login_successful(user)
        return
      end
    end
    redirect_to :action => 'index'
  end

private

  def request_token
    request_token = create_oauth_consumer.get_request_token({})
    session[:request_token] = request_token.token
    session[:request_token_secret] = request_token.secret
    request_token
  end

  def create_oauth_consumer
    key = F2P::Config.friendfeed_api_oauth_consumer_key
    secret = F2P::Config.friendfeed_api_oauth_consumer_secret
    opt = {
      :site              => F2P::Config.friendfeed_api_oauth_site,
      :request_token_url => F2P::Config.friendfeed_api_oauth_request_token_url,
      :authorize_url     => F2P::Config.friendfeed_api_oauth_authorize_url,
      :access_token_url  => F2P::Config.friendfeed_api_oauth_access_token_url,
      :scheme            => F2P::Config.friendfeed_api_oauth_scheme,
      :signature_method  => F2P::Config.friendfeed_api_oauth_signature_method,
      :http_method       => F2P::Config.friendfeed_api_oauth_http_method,
      :proxy             => F2P::Config.http_proxy || ENV['http_proxy']
    }
    OAuth::Consumer.new(key, secret, opt)
  end

  def login_successful(user)
    set_user(user)
    flash[:message] = "You can change TimeZone, font size and other settings. Follow the 3rd 'gear' icon above."
    if params = session[:redirect_to_after_authenticate]
      session[:redirect_to_after_authenticate] = nil
      redirect_to url_for(params)
    else
      redirect_to :controller => :entry, :action => :inbox
    end
  end
end
