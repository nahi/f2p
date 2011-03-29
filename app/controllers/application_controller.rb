# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

require 'ff'
require 'stringio'
require 'zlib'
require 'ext'


class ApplicationController < ActionController::Base
  # See ActionController::RequestForgeryProtection for details
  # Uncomment the :secret if you're not using the cookie session store
  protect_from_forgery
  
  # See ActionController::Base for details 
  # Uncomment this to filter the contents of submitted sensitive data parameters
  # from your application log (in this case, all fields with names like "password"). 
  # filter_parameter_logging :password

  before_filter :timezone_required

  GEO = GeoCity.new

  # use URL rewriting feature if jpmobile plugin exists.
  if self.respond_to?(:trans_sid)
    trans_sid
  end

  class << self
    def ff_client
      @@ff ||= create_ff_client(ActiveRecord::Base.logger)
    end

    def ff_client=(ff_client)
      @@ff = ff_client
    end

    def http_client
      @@http ||= HTTPClient.new(F2P::Config.http_proxy)
    end

    def http_client=(http_client)
      @@http = http_client
    end

    def param(params, key)
      v = params[key]
      (v and v.respond_to?(:empty?) and v.empty?) ? nil : v
    end

    def intparam(params, key)
      v = param(params, key)
      if v
        v.to_i
      end
    end

  private

    def create_ff_client(logger)
      client = FriendFeed::APIV2Client.new(logger)
      client.http_proxy = F2P::Config.http_proxy
      client.oauth_consumer_key = F2P::Config.friendfeed_api_oauth_consumer_key
      client.oauth_consumer_secret = F2P::Config.friendfeed_api_oauth_consumer_secret
      client.oauth_site = F2P::Config.friendfeed_api_oauth_site
      client.oauth_scheme = F2P::Config.friendfeed_api_oauth_scheme
      client.oauth_signature_method = F2P::Config.friendfeed_api_oauth_signature_method
      client.json_parse_size_limit = F2P::Config.json_parse_size_limit
      client
    end
  end

  def jpmobile?
    request.respond_to?(:mobile)
  end

  def cell_phone?
    jpmobile? and request.mobile?
  end

  def i_mode?
    jpmobile? and request.mobile.is_a?(Jpmobile::Mobile::Docomo)
  end

  def iphone?
    /(iPhone|iPod|iPad)/ =~ request.user_agent
  end

  def android?
    /Android/ =~ request.user_agent
  end

private

  def timezone_from_request_ip
    if addr = request.remote_ip
      if tz = GEO.ip2tz(addr)
        ActiveSupport::TimeZone::MAPPING.key(tz)
      end
    end
  end

  def http_client
    self.class.http_client
  end

  def auth
    @auth
  end

  def timezone_required
    if setting = session[:setting]
      @timezone = setting.timezone
    end
    @timezone ||= timezone_from_request_ip || F2P::Config.timezone
  end

  def login_required
    unless ensure_login
      if request.method == :get
        session[:redirect_to_after_authenticate] = request.parameters
      end
      redirect_to :controller => 'login', :action => 'index'
    end
  end

  def strip_heading_spaces
    response.body.gsub!(/^\s*/, '')
  end

  class ContentCoding
    attr_reader :q
    attr_reader :coding

    def initialize(str)
      @coding, rest = str.split(/;\s*/, 2)
      @q = 1.0
      if /q=(.*)/ =~ rest
        @q = $1.to_f # fallbacks to 0.0
      end
    end
  end

  def compress
    return if response.headers['content-encoding']
    accepts = request.env['HTTP_ACCEPT_ENCODING'] || ''
    codings = accepts.split(/,\s*/).map { |e| ContentCoding.new(e) }
    codings.sort_by { |coding| coding.q }.each do |coding|
      next unless coding.q > 0.0
      case coding.coding
      when 'gzip', 'x-gzip'
        ostream = StringIO.new
        begin
          gz = Zlib::GzipWriter.new(ostream)
          gz.write(response.body)
          response.body = ostream.string
          response.headers['content-encoding'] = coding.coding
          return
        ensure
          gz.close
        end
      end
    end
  end

  def ensure_login
    @user_id ||= session[:user_id]
    @setting = session[:setting] ||= new_setting
    @setting.timezone ||= timezone_from_request_ip || F2P::Config.timezone
    if @user_id
      @auth = User.find(@user_id) rescue nil
    end
    if @setting.timezone
      @timezone = @setting.timezone
    end
    if @auth
      logger.info('Processing for user ' + @auth.name)
    end
    @auth
  end

  def set_user(user)
    @user_id = session[:user_id] = user.id
    @auth = user
  end

  def set_timezone(tz)
    @setting = session[:setting] ||= new_setting
    @setting.timezone = tz
  end

  def new_setting
    s = Setting.new
    if iphone? or android?
      s.entries_in_page = 20
      s.list_view_profile_picture = true
      s.link_open_new_window = true
      s.link_type = nil
      s.use_ajax = true
    end
    s
  end

  def logout
    @user_id = session[:user_id] = nil
    @auth = nil
    reset_session
  end

  def param(key)
    self.class.param(params, key)
  end

  def intparam(key)
    self.class.intparam(params, key)
  end

  def redirect_to_entry_list(clear_eid = false)
    if ctx = @ctx || session[:ctx]
      ctx.eid = nil if clear_eid
      flash[:keep_ctx] = true
      redirect_to ctx.link_opt(:controller => 'entry')
    else
      redirect_to :controller => 'entry', :action => 'inbox'
    end
  end

  def fetch_feedinfo(id = nil)
    return unless auth
    id ||= 'me'
    tasks = []
    tasks << Task.run {
      @feedinfo = User.ff_feedinfo(auth, id)
    }
    tasks << Task.run {
      @feedlist = User.ff_feedlist(auth)
    }
    tasks.each do |task|
      task.result
    end
  end

  def session_cache(key, force = false, &block)
    ss = session[key] ||= {}
    if !force and updated_at = ss[:updated_at]
      if ss[:entries] and (Time.now.to_i - updated_at < F2P::Config.twitter_api_cache)
        return ss[:entries]
      end
    end
    if new_value = yield
      ss[:entries] = new_value
    end
    ss[:updated_at] = Time.now.to_i
    ss[:entries]
  end
end
