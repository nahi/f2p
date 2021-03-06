require 'google_maps'


class EntryController < ApplicationController
  before_filter :login_required
  before_filter :verify_authenticity_token, :except => [:inbox, :list]
  after_filter :strip_heading_spaces
  after_filter :compress

  class EntryContext
    attr_accessor :eid
    attr_accessor :eids
    attr_accessor :query
    attr_accessor :user
    attr_accessor :list
    attr_accessor :room
    attr_accessor :friends
    attr_accessor :like
    attr_accessor :comment
    attr_accessor :link
    attr_accessor :label
    attr_accessor :service
    attr_accessor :start
    attr_accessor :num
    attr_accessor :likes
    attr_accessor :comments
    attr_accessor :fold
    attr_accessor :inbox
    attr_accessor :home
    attr_accessor :moderate

    attr_accessor :viewname

    def initialize(auth)
      @auth = auth
      @viewname = nil
      @eid = @eids = @query = @user = @list = @room = @friends = @like = @comment = @link = @label = @service = @start = @num = @likes = @comments = nil
      @fold = false
      @inbox = false
      @home = true
      @moderate = nil
      @param = nil
    end

    def parse(param, setting)
      return unless param
      @param = param
      @eid = param(:id)
      @eids = param(:ids).split(',') if param(:ids)
      @query = param(:query)
      @user = param(:user)
      @list = param(:list)
      @room = param(:room)
      @friends = param(:friends)
      @like = param(:like)
      @comment = param(:comment)
      @link = param(:link)
      @label = param(:label)
      @service = param(:service)
      @start = (param(:start) || '0').to_i
      @num = intparam(:num) || setting.entries_in_page
      @likes = intparam(:likes)
      @comments = intparam(:comments)
      @fold = param(:fold) != 'no'
      @inbox = false
      @home = !(@eid or @eids or @inbox or @query or @like or @comment or @user or @friends or @list or @room or @link or @label)
    end

    def single?
      !!@eid
    end

    def list?
      !single?
    end

    def user_only?
      @user and !@like and !@comment
    end

    def friend_view?
      user_only? and @user != @auth.name
    end

    def find_opt
      opt = {
        :auth => @auth,
        :start => @start,
        :num => @num,
        :service => @service,
        :label => @label,
        :merge_entry => true,
        :merge_service => false
      }
      if @eid
        opt.merge(:id => @eid)
      elsif @eids
        opt.merge(:ids => @eids, :merge_entry => false)
      elsif @link
        opt.merge(:link => @link, :query => @query, :merge_service => true)
      elsif @query
        opt.merge(:query => @query, :likes => @likes, :comments => @comments, :user => @user, :room => @room, :friends => @friends, :service => @service, :merge_entry => false)
      elsif @like
        opt.merge(:like => @like, :user => @user || @auth.name, :merge_entry => false)
      elsif @comment
        opt.merge(:comment => @comment, :user => @user || @auth.name, :merge_entry => false)
      elsif @user
        opt.merge(:user => @user)
      elsif @friends
        opt.merge(:friends => @friends, :merge_service => true)
      elsif @list
        opt.merge(:list => @list, :merge_service => true)
      elsif @room
        opt.merge(:room => @room, :merge_service => true, :merge_entry => (@room != '*'))
      elsif @inbox
        opt.merge(:inbox => true, :merge_service => true)
      else
        opt.merge(:merge_service => true)
      end
    end

    def reset_for_new
      @eid = @comment = nil
    end

    def list_opt
      {
        :query => @query,
        :likes => @likes,
        :comments => @comments,
        :user => @user,
        :list => @list,
        :room => @room,
        :friends => @friends,
        :like => @like,
        :comment => @comment,
        :link => @link,
        :label => @label,
        :service => @service,
        :fold => @fold ? nil : 'no'
      }
    end

    def room_for
      (@room != '*') ? @room : nil
    end

    def user_for
      user = @user || @friends
      user != 'me' ? user : nil
    end

    def link_opt(opt = {})
      opt.merge(:action => default_action, :id => @eid)
    end

  private

    def param(key)
      ApplicationController.param(@param, key)
    end

    def intparam(key)
      ApplicationController.intparam(@param, key)
    end

    def default_action
      if @eid
        'show'
      elsif @inbox
        'inbox'
      else
        'list'
      end
    end
  end

  def initialize(*arg)
    super
    @user_profiles = {}
    @room_profiles = {}
    @list_profiles = {}
  end

  verify :only => :list,
          :method => [:get, :post],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}

  def list
    @ctx = restore_ctx { |ctx|
      ctx.parse(params, @setting)
    }
    with_profile_cache(@ctx) do
      @threads = find_entry_thread(find_opt)
    end
    initialize_checked_modified
  end

  def index
    if unpin = param(:unpin)
      unpin_entry(unpin)
    end
    if pin = param(:pin)
      pin_entry(pin)
    end
    redirect_to_list
  end

  verify :only => :inbox,
          :method => [:get, :post],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}

  def inbox
    @ctx = restore_ctx { |ctx|
      ctx.start = (param(:start) || '0').to_i
      ctx.num = intparam(:num) || @setting.entries_in_page
      ctx.inbox = true
      ctx.home = false
      ctx.fold = param(:fold) != 'no'
    }
    retry_times = @ctx.start.zero? ? 0 : F2P::Config.max_skip_empty_inbox_pages
    with_profile_cache(@ctx) do
      @threads = find_entry_thread(find_opt)
    end
    retry_times.times do
      break unless @threads.empty?
      if param(:direction) == 'rewind'
        break if @ctx.start - @ctx.num < 0
        @ctx.start -= @ctx.num
      else
        @ctx.start += @ctx.num
      end
      @threads = find_entry_thread(find_opt)
    end
    initialize_checked_modified
    render :action => 'list'
  end

  def updated
    redirect_to :action => 'inbox'
  end

  verify :only => :archive,
          :method => [:get, :post],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}
  def archive
    update_checked_modified
    flash[:allow_cache] = true
    redirect_to_list
  end

  verify :only => :show,
          :method => :get,
          :params => [:id],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}

  def show
    @ctx = EntryContext.new(auth)
    @ctx.eid = param(:id)
    @ctx.comment = param(:comment)
    @ctx.moderate = param(:moderate)
    @ctx.home = false
    sess_ctx = session[:ctx]
    if unpin = param(:unpin)
      unpin_entry(unpin)
    end
    if pin = param(:pin)
      pin_entry(pin)
    end
    with_profile_cache(@ctx) do
      opt = find_opt()
      # allow to use cache except self reloading
      if flash[:show_reload_detection] != @ctx.eid and !updated_id_in_flash
        opt[:allow_cache] = true
      end
      @threads = find_entry_thread(opt)
      if sess_ctx
        # pin/unpin redirect caused :id set.
        ctx = sess_ctx.dup
        ctx.eid = nil
        opt = find_opt(ctx)
        opt[:allow_cache] = true
        opt.delete(:updated_id)
        # avoid inbox threds update
        opt[:filter_inbox_except] = @ctx.eid
        @original_threads = find_entry_thread(opt)
      else
        @original_threads = []
      end
    end
    if sess_ctx
      sess_ctx.eid = @ctx.eid
    end
    flash[:show_reload_detection] = @ctx.eid
    render :action => 'list'
  end

  def new
    @ctx = EntryContext.new(auth)
    @ctx.viewname = 'post new entry'
    @ctx.room = param(:room)
    @body = param(:body)
    @link = param(:link)
    @with_form = param(:with_form)
    @title = param(:title)
    @lat = param(:lat)
    @long = param(:long)
    @address = param(:address)
    @setting.google_maps_zoom = intparam(:zoom) if intparam(:zoom)
    @setting.google_maps_zoom ||= F2P::Config.google_maps_zoom
    if jpmobile? and request.mobile
      if pos = request.mobile.position
        @lat = pos.lat.to_s
        @long = pos.lon.to_s
      end
    end
    @placemark = nil
    if @lat and @long
      geocoder = GoogleMaps::GoogleGeocoder.new(http_client, F2P::Config.google_maps_api_key)
      lang = @setting.google_maps_geocoding_lang || 'ja'
      @placemark = geocoder.reversesearch(@lat, @long, lang) rescue nil
      if @placemark and !@placemark.ambiguous?
        @address = @placemark.address
      end
    end
  end

  verify :only => :reshare,
          :method => :get,
          :params => [:eid],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}

  def reshare
    @ctx = EntryContext.new(auth)
    @ctx.viewname = 'reshare entry'
    @ctx.room = param(:room)
    @eid = param(:eid)
    opt = create_opt(:id => @eid)
    t = find_entry_thread(opt).first
    if t.nil?
      redirect_to_list
      return
    end
    @entry = t.root
    @link = @entry.link
    @link_title = %Q("#{@entry.title}")
  end

  def search
    @ctx = EntryContext.new(auth)
    @ctx.viewname = 'search entries'
    @ctx.parse(params, @setting)
  end

  verify :only => :add,
          :method => [:get, :post],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}

  def add
    @ctx = EntryContext.new(auth)
    @ctx.viewname = 'post new entry' # setting for address search result
    @ctx.room = param(:room)
    if ctx = session[:ctx]
      @ctx.inbox = ctx.inbox
    end
    @body = param(:body)
    link_title = param(:link_title)
    @link = param(:link)
    @with_form = param(:with_form)
    file = param(:file)
    reshared_from = param(:reshared_from)
    @title = param(:title)
    @lat = param(:lat)
    @long = param(:long)
    @address = param(:address)
    @setting.google_maps_zoom = intparam(:zoom) if intparam(:zoom)
    @placemark = nil
    if param(:commit) == 'search'
      do_location_search
      render :action => 'new'
      return
    end
    opt = create_opt(:room => @ctx.room)
    if @body and @lat and @long and @address
      generator = GoogleMaps::URLGenerator.new
      image_url = generator.staticmap_url(F2P::Config.google_maps_maptype, @lat, @long, :zoom => @setting.google_maps_zoom, :width => F2P::Config.google_maps_width, :height => F2P::Config.google_maps_height)
      image_link = generator.link_url(@lat, @long, @address)
      (opt[:images] ||= []) << [image_url, image_link]
      @body += " ([map] #{@address})"
      if !@link and !file
        opt[:link] = image_link
      end
    end
    if @link
      if link_title
        opt[:body] = link_title
        opt[:comment] = @body
      else
        opt[:body] = @body || capture_title(@link)
      end
      opt[:link] = @link
    elsif @body
      opt[:body] = @body
    end
    if file
      if !file.content_type or /\Aimage\//i !~ file.content_type
        render :action => 'new'
        return
      end
      (opt[:files] ||= []) << [file]
    end
    unless opt[:body]
      render :action => 'new'
      return
    end
    id = Entry.create(opt)
    unpin_entry(reshared_from, false)
    if session[:ctx]
      session[:ctx].reset_for_new
    end
    flash[:added_id] = id
    redirect_to_list
  end

  verify :only => :delete,
          :method => :get,
          :params => [:id],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}

  def delete
    id = param(:id)
    comment = param(:comment)
    do_delete(id, comment, false)
    flash[:deleted_id] = id
    flash[:deleted_comment] = comment
    # redirect to list view (not single thread view) when an entry deleted.
    if !comment and (ctx = @ctx || session[:ctx])
      ctx.eid = nil
    end
    redirect_to_entry_or_list
  end

  verify :only => :undelete,
          :method => :get,
          :params => [:id],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}

  def undelete
    id = param(:id)
    comment = param(:comment)
    do_delete(id, comment, true)
    flash[:updated_id] = id
    redirect_to_list
  end

  verify :only => :add_comment,
          :method => :post,
          :params => [:id, :body],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}

  def add_comment
    id = param(:id)
    comment = param(:comment)
    body = param(:body)
    if comment
      comment_id = Entry.edit_comment(create_opt(:id => id, :comment => comment, :body => body))
      flash[:updated_id] = id
      flash[:updated_comment] = comment_id
    else
      comment_id = Entry.add_comment(create_opt(:id => id, :body => body))
      unpin_entry(id)
      flash[:added_id] = id
      flash[:added_comment] = comment_id
      flash[:allow_cache] = true
    end
    redirect_to_entry_or_list
  end

  verify :only => :like,
          :method => :get,
          :params => [:id],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}

  def like
    id = param(:id)
    if id
      Entry.add_like(create_opt(:id => id))
    end
    flash[:updated_id] = id
    flash[:allow_cache] = true
    redirect_to_entry_or_list
  end

  verify :only => :unlike,
          :method => :get,
          :params => [:id],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}

  def unlike
    id = param(:id)
    if id
      Entry.delete_like(create_opt(:id => id))
    end
    flash[:updated_id] = id
    flash[:allow_cache] = true
    redirect_to_entry_or_list
  end

  verify :only => :hide,
          :method => :get,
          :params => [:id],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}

  def hide
    id = param(:id)
    if id
      Entry.hide(create_opt(:id => id))
    end
    flash[:updated_id] = id
    redirect_to_list
  end

  verify :only => :pin,
          :method => :get,
          :params => [:id],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}

  def pin
    if id = param(:id)
      pin_entry(id)
    end
    flash[:allow_cache] = true
    redirect_to_entry_or_list
  end

  verify :only => :unpin,
          :method => :get,
          :params => [:id],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}

  def unpin
    if id = param(:id)
      unpin_entry(id)
    end
    flash[:allow_cache] = true
    redirect_to_entry_or_list
  end

private

  def find_opt(ctx = @ctx)
    updated_id = updated_id_in_flash()
    ctx.find_opt.merge(
      :allow_cache => flash[:allow_cache],
      :updated_id => updated_id
    )
  end

  def updated_id_in_flash
    flash[:added_id] || flash[:updated_id] || flash[:deleted_id]
  end

  def pin_entry(id)
    if id
      Entry.add_pin(create_opt(:id => id))
      clear_checked_modified(id)
    end
  end

  def unpin_entry(id, commit = true)
    if id
      Entry.delete_pin(create_opt(:id => id))
      commit_checked_modified(id) if commit
    end
  end

  def capture_title(url)
    begin
      buf = ''
      http_client.get_content(url) do |str|
        buf += str.tr("\r\n", '')
        if match = buf.match(/<title[^>]*>([^<]*)</i)
          return NKF.nkf('-wm0', match.captures[0])
        end
      end
    rescue Exception
      nil # ignore
    end
    '(unknown)'
  end

  def create_opt(hash = {})
    {
      :auth => auth
    }.merge(hash)
  end

  def do_delete(id, comment = nil, undelete = false)
    if comment and !comment.empty?
      Entry.delete_comment(create_opt(:id => id, :comment => comment, :undelete => undelete))
    else
      Entry.delete(create_opt(:id => id, :undelete => undelete))
    end
  end

  def restore_ctx
    if flash[:keep_ctx] and session[:ctx]
      ctx = session[:ctx]
    else
      ctx = EntryContext.new(auth)
      yield(ctx)
      session[:ctx] = ctx
    end
    ctx
  end

  def redirect_to_list
    redirect_to_entry_list(true)
  end

  def redirect_to_entry_or_list
    redirect_to_entry_list(false)
  end

  def do_location_search
    if @title
      lang = @setting.google_maps_geocoding_lang || 'ja'
      if lang == 'ja'
        geocoder = GoogleMaps::GeocodingJpGeocoder.new(http_client)
      else
        geocoder = GoogleMaps::GoogleGeocoder.new(http_client, F2P::Config.google_maps_api_key)
      end
      @placemark = geocoder.search(@title, lang) rescue nil
      if @placemark and !@placemark.ambiguous?
        @address = @placemark.address
        @lat = @placemark.lat
        @long = @placemark.long
      end
    end
    if @placemark.nil? and @address and @lat and @long
      @placemark = GoogleMaps::Point.new(@address, @lat, @long)
    end
  end

  def find_entry_thread(opt)
    EntryThread.find(opt) || []
  end

  def with_profile_cache(ctx)
    tasks = []
    if user = ctx.user_for
      tasks << Task.run {
        @user_profiles[user] = User.ff_profile(auth, user)
      }
    end
    if room = ctx.room_for
      tasks << Task.run {
        @room_profiles[room] = Room.ff_profile(auth, room)
      }
    end
    if list = ctx.list
      tasks << Task.run {
        @list_profiles[list] = List.ff_profile(auth, list)
      }
    end
    yield
    tasks.each do |task|
      task.result # just pull the result
    end
  end
end
