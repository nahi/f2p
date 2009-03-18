# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

require 'ff'
require 'stringio'
require 'zlib'


class ApplicationController < ActionController::Base
  # See ActionController::RequestForgeryProtection for details
  # Uncomment the :secret if you're not using the cookie session store
  protect_from_forgery :secret => 'b2dff3fcf9a2f9a3980713aebb79677f'
  
  # See ActionController::Base for details 
  # Uncomment this to filter the contents of submitted sensitive data parameters
  # from your application log (in this case, all fields with names like "password"). 
  # filter_parameter_logging :password
  session_options[:session_expires] = Time.mktime(2030, 12, 31)

  def self.ff_client
    @@ff ||= FriendFeed::APIClient.new(logger)
  end

  def self.ff_client=(ff_client)
    @@ff = ff_client
  end

  def self.http_client
    @@http ||= HTTPClient.new
  end

  def self.http_client=(http_client)
    @@http = http_client
  end

  def http_client
    self.class.http_client
  end

  def auth
    @auth
  end

private

  def login_required
    unless ensure_login
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
    if @user_id
      begin
        @auth = User.find(@user_id)
      rescue Exception
        logger.warn($!)
        @auth = nil
      end
    end
    auth
  end

  def set_user(user)
    @user_id = session[:user_id] = user.id
    @auth = user
  end

  def logout
    @user_id = session[:user_id] = nil
    @auth = nil
    reset_session
  end

  def param(key)
    v = params[key]
    (v and v.respond_to?(:empty?) and v.empty?) ? nil : v
  end

  def v(hash, *keywords)
    keywords.inject(hash) { |r, k|
      r[k] if r
    }
  end

  def update_checked_modified
    store = session[:checked]
    if auth and store
      EntryThread.update_checked_modified(auth, store)
      session[:checked] = {}
    end
  end

  def commit_checked_modified(eid)
    if store = session[:checked]
      if e = store.find { |k, v| k == eid }
        only = Hash[*e]
        EntryThread.update_checked_modified(auth, only)
        store.delete(eid)
      end
    end
  end

  def clear_checked_modified(eid)
    cond = ['user_id = ? and last_modifieds.eid = ?', auth.id, eid]
    if checked = CheckedModified.find(:first, :conditions => cond, :include => 'last_modified')
      checked.destroy
    end
    if checked = session[:checked]
      checked.delete(eid)
    end
  end
end
