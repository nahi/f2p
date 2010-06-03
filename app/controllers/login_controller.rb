require 'httpclient'


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
    token = friendfeed_request_token()
    redirect_to F2P::Config.friendfeed_api_oauth_authorize_url + "?oauth_token=#{token}"
  end

  def initiate_twitter_oauth_login
    token = twitter_request_token()
    redirect_to F2P::Config.twitter_api_oauth_authorize_url + "?oauth_token=#{token}"
  end

  def initiate_buzz_oauth_login
    token = buzz_request_token()
    redirect_to F2P::Config.buzz_api_oauth_authorize_url + "?oauth_token=#{token}&domain=#{F2P::Config.buzz_api_oauth_consumer_key}&scope=#{F2P::Config.buzz_api_oauth_scope}&btmpl=mobile"
  end

  def oauth_callback
    auth = ensure_login
    oauth_token = params[:oauth_token]
    session_token = session[:request_token]
    if oauth_token == session_token
      res = create_friendfeed_oauth_consumer.get_access_token(F2P::Config.friendfeed_api_oauth_access_token_url, oauth_token, session[:request_token_secret])
      if res.status == 200
        token = res.oauth_params["oauth_token"]
        secret = res.oauth_params["oauth_token_secret"]
        if auth
          auth.store_access_token(token, secret)
          auth.save!
        elsif user = User.oauth_validate(token, secret)
          login_successful(user)
          return
        end
      end
    end
    if back_to = session[:back_to]
      session[:back_to] = nil
      redirect_to back_to
    else
      redirect_to :controller => 'entry', :action => 'inbox'
    end
  end

  def twitter_oauth_callback
    auth = ensure_login
    oauth_token = params[:oauth_token]
    oauth_verifier = params[:oauth_verifier]
    session_token = session[:request_token]
    if oauth_token == session_token
      res = create_twitter_oauth_consumer.get_access_token(F2P::Config.twitter_api_oauth_access_token_url, oauth_token, session[:request_token_secret], oauth_verifier)
      if res.status == 200
        token = res.oauth_params["oauth_token"]
        secret = res.oauth_params["oauth_token_secret"]
        user_id = res.oauth_params["user_id"]
        screen_name = res.oauth_params["screen_name"]
        if auth
          auth.set_token('twitter', user_id, token, secret, screen_name)
        elsif user = User.token_validate('twitter', user_id, token, secret, screen_name)
          set_user(user)
        end
      end
    end
    if back_to = session[:back_to]
      session[:back_to] = nil
      redirect_to back_to
    else
      redirect_to :controller => 'entry', :action => 'tweets'
    end
  end

  def buzz_oauth_callback
    auth = ensure_login
    oauth_token = params[:oauth_token]
    oauth_verifier = params[:oauth_verifier]
    session_token = session[:request_token]
    if oauth_token == session_token
      res = create_buzz_oauth_consumer.get_access_token(F2P::Config.buzz_api_oauth_access_token_url, oauth_token, session[:request_token_secret], oauth_verifier)
      if res.status == 200
        token = res.oauth_params["oauth_token"]
        secret = res.oauth_params["oauth_token_secret"]
        t = Token.new
        t.token = token
        t.secret = secret
        profile = Buzz.profile(t)
        if profile.id and profile.display_name
          user_id = profile.id
          screen_name = profile.display_name
          if auth
            auth.set_token('buzz', user_id, token, secret, screen_name)
          elsif user = User.token_validate('buzz', user_id, token, secret, screen_name)
            set_user(user)
          end
        end
      end
    end
    if back_to = session[:back_to]
      session[:back_to] = nil
      redirect_to back_to
    else
      redirect_to :controller => 'entry', :action => 'buzz'
    end
  end

  def unlink_friendfeed
    if auth = ensure_login
      auth.clear_token('friendfeed')
    end
    redirect_to :controller => 'setting'
  end

  def unlink_twitter
    id = params[:id]
    if auth = ensure_login
      auth.clear_token('twitter', id)
    end
    redirect_to :controller => 'setting'
  end

  def unlink_buzz
    id = params[:id]
    if auth = ensure_login
      auth.clear_token('buzz', id)
    end
    redirect_to :controller => 'setting'
  end

private

  def friendfeed_request_token
    consumer = create_friendfeed_oauth_consumer()
    url = F2P::Config.friendfeed_api_oauth_request_token_url
    get_request_token(consumer, url)
  end

  def twitter_request_token
    consumer = create_twitter_oauth_consumer()
    url = F2P::Config.twitter_api_oauth_request_token_url
    callback = 'twitter_oauth_callback'
    get_request_token(consumer, url, callback)
  end

  def buzz_request_token
    consumer = create_buzz_oauth_consumer()
    url = F2P::Config.buzz_api_oauth_request_token_url
    callback = 'buzz_oauth_callback'
    get_request_token(consumer, url, callback, :scope => F2P::Config.buzz_api_oauth_scope)
  end

  def get_request_token(consumer, url, callback = nil, args = {})
    callback = url_for(:action => callback) if callback
    res = consumer.get_request_token(url, callback, args)
    token = res.oauth_params['oauth_token']
    secret = res.oauth_params['oauth_token_secret']
    session[:request_token] = token
    session[:request_token_secret] = secret
    token
  end

  def create_friendfeed_oauth_consumer
    client = OAuthClient.new
    client.oauth_config.consumer_key = F2P::Config.friendfeed_api_oauth_consumer_key
    client.oauth_config.consumer_secret = F2P::Config.friendfeed_api_oauth_consumer_secret
    client.oauth_config.signature_method = F2P::Config.friendfeed_api_oauth_signature_method
    client.oauth_config.http_method = F2P::Config.friendfeed_api_oauth_http_method
    client
  end

  def create_twitter_oauth_consumer
    client = OAuthClient.new
    client.oauth_config.consumer_key = F2P::Config.twitter_api_oauth_consumer_key
    client.oauth_config.consumer_secret = F2P::Config.twitter_api_oauth_consumer_secret
    client.oauth_config.signature_method = F2P::Config.twitter_api_oauth_signature_method
    client.oauth_config.http_method = F2P::Config.twitter_api_oauth_http_method
    client
  end

  def create_buzz_oauth_consumer
    client = OAuthClient.new
    client.oauth_config.consumer_key = F2P::Config.buzz_api_oauth_consumer_key
    client.oauth_config.consumer_secret = F2P::Config.buzz_api_oauth_consumer_secret
    client.oauth_config.signature_method = F2P::Config.buzz_api_oauth_signature_method
    client.oauth_config.http_method = F2P::Config.buzz_api_oauth_http_method
    client
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
