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
    attr_accessor :feed
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
      @eid = @eids = @query = @user = @feed = @room = @friends = @like = @comment = @link = @label = @service = @start = @num = @likes = @comments = nil
      @fold = false
      @inbox = false
      @home = true
      @moderate = nil
      @param = nil
    end

    def parse(param, setting)
      return unless param
      @param = param
      @eid = param(:eid)
      @eids = param(:eids).split(',') if param(:eids)
      @query = param(:query)
      @user = param(:user)
      @feed = param(:feed)
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
      @home = !(@eid or @eids or @inbox or @query or @like or @comment or @user or @friends or @feed or @room or @link or @label)
    end

    def single?
      !!@eid
    end

    def list?
      !single?
    end

    def feedid
      user_for || room_for || feed || 'home'
    end

    def profile_for
      user_for || room_for
    end

    def direct_message?
      feedid == 'filter/direct'
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
        opt.merge(:eid => @eid)
      elsif @eids
        opt.merge(:eids => @eids, :merge_entry => false)
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
      elsif @feed
        if @feed == 'filter/direct'
          opt.merge(:feed => @feed, :merge_entry => false)
        else
          opt.merge(:feed => @feed, :merge_service => true)
        end
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
        :feed => @feed,
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

    def list_for
      if /\Alist\b/ =~ @feed or /\Asummary\b/ =~ @feed
        @feed
      elsif self.home
        'home'
      end
    end

    def link_opt(opt = {})
      opt.merge(:action => default_action, :eid => @eid)
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
  end

  verify :only => :list,
          :method => [:get, :post],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}

  def list
    @ctx = restore_ctx { |ctx|
      ctx.parse(params, @setting)
    }
    with_feedinfo(@ctx.feedid, @ctx) do
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
    with_feedinfo(@ctx.feedid, @ctx) do
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
          :params => [:eid],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}

  def show
    @ctx = EntryContext.new(auth)
    @ctx.eid = param(:eid)
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
    with_feedinfo(@ctx.feedid, @ctx) do
      opt = find_opt()
      # allow to use cache except self reloading
      if flash[:show_reload_detection] != @ctx.eid and !updated_id_in_flash
        opt[:allow_cache] = true
      end
      @threads = find_entry_thread(opt)
      if sess_ctx
        # pin/unpin redirect caused :eid set.
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
    @to_lines = 1
    @to = []
    @cc = true
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
    @feedinfo = User.ff_feedinfo(auth, auth.name)
  end

  verify :only => :reshare,
          :method => :get,
          :params => [:reshared_from],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}

  def reshare
    @ctx = EntryContext.new(auth)
    @ctx.viewname = 'reshare entry'
    @to_lines = 1
    @to = []
    @cc = true
    @reshared_from = param(:reshared_from)
    opt = create_opt(:eid => @reshared_from)
    t = find_entry_thread(opt).first
    if t.nil?
      redirect_to_list
      return
    end
    @entry = t.root
    if !@entry.short_url
      opt = create_opt(:eid => @entry.id)
      entry = Entry.create_short_url(opt)
      @entry.short_id = entry.short_id
      @entry.short_url = entry.short_url
    end
    if @entry.link
      @link = @entry.link
      @link_title = %Q[Fwd: "#{@entry.body}" via (#{@entry.short_url || @entry.url})]
    else
      @link = @entry.short_url || @entry.url
      @link_title = %Q[Fwd: "#{@entry.body}"]
    end
    @feedinfo = User.ff_feedinfo(auth, auth.name)
  end

  def search
    @ctx = EntryContext.new(auth)
    @ctx.viewname = 'search entries'
    @ctx.parse(params, @setting)
    @feedinfo = User.ff_feedinfo(auth, auth.name)
  end

  verify :only => :add,
          :method => [:get, :post],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}

  def add
    @ctx = EntryContext.new(auth)
    @ctx.viewname = 'post new entry' # setting for address search result
    if ctx = session[:ctx]
      @ctx.inbox = ctx.inbox
    end
    @to_lines = intparam(:to_lines) || 0
    @to = []
    @to_lines.times do |idx|
      @to[idx] = param("to_#{idx}")
    end
    @cc = param(:cc)
    @body = param(:body)
    link_title = param(:link_title)
    @link = param(:link)
    @link_title = param(:link_title)
    @with_form = param(:with_form)
    file = param(:file)
    @reshared_from = param(:reshared_from)
    @title = param(:title)
    @lat = param(:lat)
    @long = param(:long)
    @address = param(:address)
    @setting.google_maps_zoom = intparam(:zoom) if intparam(:zoom)
    @placemark = nil
    case param(:commit)
    when 'search'
      do_location_search
      @feedinfo = User.ff_feedinfo(auth, auth.name)
      render :action => 'new'
      return
    when 'more'
      @to_lines += 1
      @feedinfo = User.ff_feedinfo(auth, auth.name)
      if @reshared_from
        render :action => 'reshare'
      else
        render :action => 'new'
      end
      return
    end
    opt = create_opt(:to => @to.compact)
    opt[:to] << 'me' if @cc == 'checked'
    if @body and @lat and @long and @address
      opt[:geo] = "#{@lat},#{@long}"
      generator = GoogleMaps::URLGenerator.new
      image_link = generator.link_url(@lat, @long, @address)
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
      (opt[:file] ||= []) << file
    end
    unless opt[:body]
      @feedinfo = User.ff_feedinfo(auth, auth.name)
      render :action => 'new'
      return
    end
    entry = Entry.create(opt)
    unless entry
      msg = 'Posting failure.'
      if opt[:file]
        msg += ' Unsupported media type?'
      else
        msg += ' Try later.'
      end
      flash[:message] = msg
      @feedinfo = User.ff_feedinfo(auth, auth.name)
      render :action => 'new'
      return
    end
    unpin_entry(@reshared_from, false)
    if session[:ctx]
      session[:ctx].reset_for_new
    end
    flash[:added_id] = entry.id
    redirect_to_list
  end

  verify :only => :update,
          :method => [:post],
          :params => [:eid, :body],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}

  def update
    id = param(:eid)
    body = param(:body)
    if entry = Entry.update(create_opt(:eid => id, :body => body))
      flash[:updated_id] = entry.id
      flash[:allow_cache] = true
    end
    redirect_to_entry_or_list
  end

  verify :only => :delete,
          :method => :get,
          :params => [:eid],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}

  def delete
    id = param(:eid)
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
          :params => [:eid],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}

  def undelete
    id = param(:eid)
    comment = param(:comment)
    do_delete(id, comment, true)
    flash[:updated_id] = id
    redirect_to_list
  end

  verify :only => :add_comment,
          :method => :post,
          :params => [:eid, :body],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}

  def add_comment
    id = param(:eid)
    comment = param(:comment)
    body = param(:body)
    if comment
      if c = Entry.edit_comment(create_opt(:comment => comment, :body => body))
        flash[:updated_id] = id
        flash[:updated_comment] = c.id
      end
    else
      c = Entry.add_comment(create_opt(:eid => id, :body => body))
      unpin_entry(id)
      flash[:added_id] = id
      flash[:added_comment] = c.id
      flash[:allow_cache] = true
    end
    redirect_to_entry_or_list
  end

  verify :only => :like,
          :method => :get,
          :params => [:eid],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}

  def like
    id = param(:eid)
    if id
      Entry.add_like(create_opt(:eid => id))
    end
    flash[:updated_id] = id
    flash[:allow_cache] = true
    redirect_to_entry_or_list
  end

  verify :only => :unlike,
          :method => :get,
          :params => [:eid],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}

  def unlike
    id = param(:eid)
    if id
      Entry.delete_like(create_opt(:eid => id))
    end
    flash[:updated_id] = id
    flash[:allow_cache] = true
    redirect_to_entry_or_list
  end

  verify :only => :hide,
          :method => :get,
          :params => [:eid],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}

  def hide
    id = param(:eid)
    if id
      Entry.hide(create_opt(:eid => id))
    end
    flash[:updated_id] = id
    redirect_to_list
  end

  verify :only => :pin,
          :method => :get,
          :params => [:eid],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}

  def pin
    if id = param(:eid)
      pin_entry(id)
    end
    flash[:allow_cache] = true
    redirect_to_entry_or_list
  end

  verify :only => :unpin,
          :method => :get,
          :params => [:eid],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}

  def unpin
    if id = param(:eid)
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
      :updated_id => updated_id,
      :fof => (@setting.disable_fof ? nil : 1)
    )
  end

  def updated_id_in_flash
    flash[:added_id] || flash[:updated_id] || flash[:deleted_id]
  end

  def pin_entry(id)
    if id
      Entry.add_pin(create_opt(:eid => id))
      clear_checked_modified(id)
    end
  end

  def unpin_entry(id, commit = true)
    if id
      Entry.delete_pin(create_opt(:eid => id))
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
      Entry.delete_comment(create_opt(:eid => id, :comment => comment, :undelete => undelete))
    else
      Entry.delete(create_opt(:eid => id, :undelete => undelete))
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

  def with_feedinfo(feedid, ctx)
    tasks = []
    tasks << Task.run {
      @feedlist = User.ff_feedlist(auth)
    }
    tasks << Task.run {
      @feedinfo = User.ff_feedinfo(auth, feedid)
    }
    yield
    # just pull the result
    tasks.each do |task|
      task.result
    end
  end
end
