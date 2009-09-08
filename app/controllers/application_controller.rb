# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

require 'ff_daemon'
require 'stringio'
require 'zlib'


class ApplicationController < ActionController::Base
  # See ActionController::RequestForgeryProtection for details
  # Uncomment the :secret if you're not using the cookie session store
  protect_from_forgery
  
  # See ActionController::Base for details 
  # Uncomment this to filter the contents of submitted sensitive data parameters
  # from your application log (in this case, all fields with names like "password"). 
  # filter_parameter_logging :password

  GEO = GeoCity.new

  # use URL rewriting feature if jpmobile plugin exists.
  if self.respond_to?(:trans_sid)
    trans_sid
  end

  class << self
    def ff_client
      @@ff ||= create_ff_client(logger)
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
      FriendFeed::APIV2ClientProxy.new
    end
  end

  def timezone_from_request_ip
    if addr = request.remote_ip
      if tz = GEO.ip2tz(addr)
        ActiveSupport::TimeZone::MAPPING.key(tz)
      end
    end
  end

private

  def jpmobile?
    request.respond_to?(:mobile)
  end

  def http_client
    self.class.http_client
  end

  def auth
    @auth
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
    @setting = session[:setting] ||= Setting.new
    @auth = User.find(@user_id) if @user_id
    auth
  end

  def set_user(user)
    @user_id = session[:user_id] = user.id
    @auth = user
  end

  def set_timezone(tz)
    @setting = session[:setting] ||= Setting.new
    @setting.timezone = tz
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

  def update_checked_modified
    store = session[:checked]
    if auth and store
      Feed.update_checked_modified(auth, store)
      session[:checked] = {}
    end
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

  def initialize_checked_modified
    session[:checked] = {}
  end

  def commit_checked_modified(eid)
    if store = session[:checked]
      if e = store.find { |k, v| k == eid }
        only = Hash[*e]
        Feed.update_checked_modified(auth, only)
        store.delete(eid)
      end
    end
  end

  def fetch_feedinfo(id = nil)
    return unless auth
    id ||= auth.name
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
end
