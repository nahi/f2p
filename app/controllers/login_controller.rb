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
      # We MUST NOT rely on this name; attacker can edit it freely.
      # We should use API instead. See User#oauth_validate how to do that.
      # -> Not too bad:
      #    getting an access token from a request token is a direct request
      #    over SSL. So it should be relyable when a SSL is properly
      #    configured. (requires trust anchor CA cert setting for OAuth gem)
      # name = access_token.params[:username]
      token = access_token.params[:oauth_token]
      secret = access_token.params[:oauth_token_secret]
      if user = User.oauth_validate(token, secret)
        login_successful(user)
        return
      end
    end
    redirect_to :action => 'index'
  end

  def initiate_twitter_oauth_login
    return if login_required
    redirect_to twitter_request_token.authorize_url
  end

  def twitter_oauth_callback
    if auth = ensure_login
      oauth_token = params[:oauth_token]
      oauth_verifier = params[:oauth_verifier]
      session_token = session[:request_token]
      if oauth_token == session_token
        request_token = OAuth::RequestToken.new(create_twitter_oauth_consumer, oauth_token, session[:request_token_secret])
        access_token = request_token.get_access_token(:oauth_verifier => oauth_verifier)
        token = access_token.params[:oauth_token]
        secret = access_token.params[:oauth_token_secret]
        screen_name = access_token.params[:screen_name]
        user_id = access_token.params[:user_id]
        auth.set_token('twitter', user_id, token, secret, screen_name)
        flash[:twitter_auth] = true
      end
    end
    if back_to = session[:back_to]
      session[:back_to] = nil
      redirect_to back_to
    else
      redirect_to :action => 'index'
    end
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

  def twitter_request_token
    request_token = create_twitter_oauth_consumer.get_request_token(:oauth_callback => url_for(:action => 'twitter_oauth_callback'))
    session[:request_token] = request_token.token
    session[:request_token_secret] = request_token.secret
    request_token
  end

  def create_twitter_oauth_consumer
    key = F2P::Config.twitter_api_oauth_consumer_key
    secret = F2P::Config.twitter_api_oauth_consumer_secret
    opt = {
      :site              => F2P::Config.twitter_api_oauth_site,
      :request_token_url => F2P::Config.twitter_api_oauth_request_token_url,
      :authorize_url     => F2P::Config.twitter_api_oauth_authorize_url,
      :access_token_url  => F2P::Config.twitter_api_oauth_access_token_url,
      :scheme            => F2P::Config.twitter_api_oauth_scheme,
      :signature_method  => F2P::Config.twitter_api_oauth_signature_method,
      :http_method       => F2P::Config.twitter_api_oauth_http_method,
      :proxy             => F2P::Config.http_proxy || ENV['http_proxy']
    }
    OAuth::Consumer.new(key, secret, opt)
  end

  def login_successful(user)
    set_user(user)
    flash[:login] = true
    if params = session[:redirect_to_after_authenticate]
      session[:redirect_to_after_authenticate] = nil
      redirect_to url_for(params)
    else
      redirect_to :controller => :entry, :action => :inbox
    end
  end
end
