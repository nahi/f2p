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
    attr_accessor :with_likes
    attr_accessor :with_comments
    attr_accessor :with_like
    attr_accessor :with_comment
    attr_accessor :fold
    attr_accessor :inbox
    attr_accessor :home
    attr_accessor :moderate

    attr_accessor :tweets
    attr_accessor :in_reply_to_service_user
    attr_accessor :in_reply_to_screen_name
    attr_accessor :in_reply_to_status_id

    attr_accessor :viewname

    def initialize(auth)
      @auth = auth
      @viewname = nil
      @eid = @eids = @query = @user = @feed = @room = @friends = @like = @comment = @link = @label = @service = @start = @num = @with_likes = @with_comments = @with_like = @with_comment = nil
      @fold = false
      @inbox = false
      @home = true
      @moderate = nil
      @param = nil
      @tweets = false
      @in_reply_to_service_user = @in_reply_to_screen_name = @in_reply_to_status_id = nil
    end

    def parse(param, setting)
      return unless param
      @param = param
      @eid = param(:eid)
      @eids = param(:eids).split(',') if param(:eids)
      @query = @param[:query]
      @user = param(:user)
      @feed = param(:feed)
      @room = param(:room)
      @friends = param(:friends)
      if @friends == 'checked'
        @friends = @user
        @user = nil
      end
      @like = param(:like)
      @comment = param(:comment)
      @link = param(:link)
      @label = param(:label)
      @service = param(:service)
      @start = (param(:start) || '0').to_i
      @num = intparam(:num) || setting.entries_in_page
      @with_likes = intparam(:with_likes)
      @with_comments = intparam(:with_comments)
      @with_like = (param(:with_like) == 'checked')
      @with_comment = (param(:with_comment) == 'checked')
      @in_reply_to_service_user = param(:in_reply_to_service_user)
      @in_reply_to_screen_name = param(:in_reply_to_screen_name)
      @in_reply_to_status_id = param(:in_reply_to_status_id)
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
        # works only merge_entry == true
        :merge_service => true
      }
      if @eid
        opt.merge(:eid => @eid)
      elsif @eids
        opt.merge(:eids => @eids)
      elsif @link
        opt.merge(:link => @link, :query => @query)
      elsif @query or @service
        opt.merge(:query => @query, :with_likes => @with_likes, :with_comments => @with_comments, :with_like => @with_like, :with_comment => @with_comment, :user => @user, :room => @room, :friends => @friends, :service => @service, :merge_entry => (@query.nil? or @query.empty?))
      elsif @like
        opt.merge(:like => @like, :user => @user || @auth.name)
      elsif @user
        opt.merge(:user => @user, :merge_entry => false)
      elsif @feed
        if @feed == 'filter/direct'
          opt.merge(:feed => @feed, :merge_entry => false, :merge_service => false)
        else
          opt.merge(:feed => @feed)
        end
      elsif @room
        opt.merge(:room => @room, :merge_entry => (@room != '*'))
      elsif @inbox
        opt.merge(:inbox => true, :merge_service => true)
      else
        opt.merge(:merge_service => true)
      end
    end

    def reset_for_new
      @eid = @comment = nil
    end

    def back_opt
      list_opt.merge(:controller => :entry, :action => default_action, :start => @start, :num => @num)
    end

    def list_opt
      {
        :query => @query,
        :with_likes => @with_likes,
        :with_comments => @with_comments,
        :with_like => @with_like ? 'checked' : nil,
        :with_comment => @with_comment ? 'checked' : nil,
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
      return nil if tweets?
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

    def list_base?
      @home or (/\Alist\b/ =~ @feed and /\/summary\/\d+\z/ !~ @feed)
    end

    def is_summary?
      /\Asummary\b/ =~ @feed or /\/summary\/\d+\z/ =~ @feed
    end

    def tweets?
      @tweets
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
      elsif tweets?
        'tweets'
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
    pin_check
    @ctx = restore_ctx { |ctx|
      ctx.parse(params, @setting)
    }
    if @ctx.in_reply_to_service_user
      @service_source = 'twitter'
      @service_user = @ctx.in_reply_to_service_user
    end
    with_feedinfo(@ctx) do
      @feed = find_entry_thread(find_opt)
      @threads = @feed.entries
    end
    return if redirect_to_entry(@threads)
    initialize_checked_modified
  end

  def index
    pin_check
    redirect_to_list
  end

  verify :only => :inbox,
          :method => [:get, :post],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}

  def inbox
    pin_check
    @ctx = restore_ctx { |ctx|
      ctx.start = (param(:start) || '0').to_i
      ctx.num = intparam(:num) || @setting.entries_in_page
      ctx.inbox = true
      ctx.home = false
      ctx.fold = param(:fold) != 'no'
    }
    retry_times = F2P::Config.max_skip_empty_inbox_pages
    with_feedinfo(@ctx) do
      @feed = find_entry_thread(find_opt)
      @threads = @feed.entries
    end
    retry_times.times do
      break unless @threads.empty?
      if param(:direction) == 'rewind'
        break if @ctx.start - @ctx.num < 0
        @ctx.start -= @ctx.num
      else
        @ctx.start += @ctx.num
      end
      @feed = find_entry_thread(find_opt)
      @threads = @feed.entries
    end
    return if redirect_to_entry(@threads)
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

  verify :only => :tweets,
          :method => [:get, :post],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}
  def tweets
    pin_check
    @ctx = restore_ctx { |ctx|
      ctx.parse(params, @setting)
    }
    @ctx.tweets = true
    @ctx.feed ||= 'home'
    @ctx.home = false
    id = params[:id]
    max_id = params[:max_id]
    since_id = params[:since_id]
    if auth.tokens.empty? or auth.tokens.find_all_by_service('twitter').empty?
      session[:back_to] = {:controller => 'entry', :action => 'tweets'}
      redirect_to :controller => 'login', :action => 'initiate_twitter_oauth_login'
      return
    elsif id
      token = auth.tokens.find_by_service_and_service_user('twitter', id)
    else
      token = auth.tokens.find_by_service('twitter')
    end
    unless token
      redirect_to :action => 'inbox'
      return
    end
    @service_source = token.service
    @service_user = token.service_user
    opt = {:count => @ctx.num}
    opt[:max_id] = max_id if max_id
    opt[:since_id] = since_id if since_id
    with_feedinfo(@ctx) do
      case @ctx.feed
      when 'user'
        user = @ctx.user || token.params # screen_name
        tweets = Tweet.user_timeline(token, user, opt)
        feedname = '@' + user
      when 'mentions'
        tweets = Tweet.mentions(token, opt)
        feedname = @ctx.feed
      when 'direct'
        tweets = Tweet.direct_messages(token, opt)
        feedname = @ctx.feed
      else # home
        tweets = Tweet.home_timeline(token, opt)
        feedname = 'home'
      end
      feed_opt = find_opt.merge(
        :tweets => tweets,
        :feedname => "Tweets(#{feedname})",
        :service_user => token.service_user
      )
      @feed = find_entry_thread(feed_opt)
      @threads = @feed.entries
    end
    return if redirect_to_entry(@threads)
    initialize_checked_modified
    render :action => 'list'
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
    pin_check
    render_single_entry
  end

  def new
    @ctx = EntryContext.new(auth)
    @ctx.viewname = 'post new entry'
    @to_lines = intparam(:to_lines) || 1
    @to = []
    @to_lines.times do |idx|
      @to[idx] = param("to_#{idx}")
    end
    @cc = params[:cc] != ''
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
    fetch_feedinfo
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
    t = find_entry_thread(opt).entries.first
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
    fetch_feedinfo
  end

  def search
    @ctx = EntryContext.new(auth)
    @ctx.viewname = 'search entries'
    @ctx.parse(params, @setting)
    fetch_feedinfo
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
    in_reply_to_service_user = param(:in_reply_to_service_user)
    in_reply_to_screen_name = param(:in_reply_to_screen_name)
    in_reply_to_status_id = param(:in_reply_to_status_id)
    case param(:commit)
    when 'search'
      do_location_search
      fetch_feedinfo
      render :action => 'new'
      return
    when 'more'
      @to_lines += 1
      fetch_feedinfo
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
      fetch_feedinfo
      render :action => 'new'
      return
    end
    case param(:service_source)
    when 'twitter'
      unless token = auth.tokens.find_by_service_and_service_user('twitter', param(:service_user))
        flash[:message] = 'Token not found'
        fetch_feedinfo
        render :action => 'tweets'
        return
      end
      opt[:service_source] = 'twitter'
      opt[:token] = token
      p [in_reply_to_status_id, opt[:body].index("@#{in_reply_to_screen_name}")]
      if in_reply_to_status_id and opt[:body].index("@#{in_reply_to_screen_name}") == 0
        opt[:in_reply_to_status_id] = in_reply_to_status_id
      end
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
      fetch_feedinfo
      render :action => 'new'
      return
    end
    unpin_entry(@reshared_from, false)
    if session[:ctx]
      session[:ctx].reset_for_new
    end
    if param(:service_source) == 'twitter'
      redirect_to :controller => 'entry', :action => 'tweets'
    else
      flash[:added_id] = entry.id
      redirect_to_list
    end
  end

  verify :only => :update,
          :method => [:post],
          :params => [:eid, :body],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}

  def update
    @body = param(:body)
    @title = param(:title)
    @lat = param(:lat)
    @long = param(:long)
    @address = param(:address)
    @setting.google_maps_zoom = intparam(:zoom) if intparam(:zoom)
    @placemark = nil
    if param(:commit) == 'search'
      @ctx = EntryContext.new(auth)
      @ctx.eid = param(:eid)
      @ctx.comment = param(:comment)
      @ctx.moderate = param(:moderate)
      @ctx.home = false
      do_location_search
      render_single_entry
      return
    end
    id = param(:eid)
    opt = create_opt(:eid => id, :body => @body)
    if @body and @lat and @long
      opt[:geo] = "#{@lat},#{@long}"
    end
    if entry = Entry.update(opt)
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
      if c = Entry.add_comment(create_opt(:eid => id, :body => body))
        unpin_entry(id)
        flash[:added_id] = id
        flash[:added_comment] = c.id
        flash[:allow_cache] = true
      end
    end
    redirect_to_entry_or_list
  end

  verify :only => :like,
          :method => :get,
          :params => [:eid],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}

  def like
    if id = param(:eid)
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
    if id = param(:eid)
      Entry.delete_like(create_opt(:eid => id))
    end
    flash[:updated_id] = id
    flash[:allow_cache] = true
    redirect_to_entry_or_list
  end

  def like_remote
    @ctx = EntryContext.new(auth)
    id = param(:eid)
    liked = !!param(:liked)
    if liked
      Entry.delete_like(create_opt(:eid => id))
    else
      Entry.add_like(create_opt(:eid => id))
    end
    opt = create_opt(:eid => id, :maxcomments => 0)
    t = find_entry_thread(opt).entries.first
    if t.nil?
      entry = nil
    else
      entry = t.root
    end
    render :partial => 'like_remote', :locals => { :entry => entry }
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

  def pin_remote
    id = param(:eid)
    pinned = !!param(:pinned)
    if pinned
      unpin_entry(id)
    else
      pin_entry(id)
    end
    render :partial => 'pin_remote', :locals => { :id => id, :pinned => !pinned }
  end

  def comments_remote
    @ctx = EntryContext.new(auth)
    id = param(:eid)
    opt = create_opt(:eid => id)
    t = find_entry_thread(opt).entries.first
    if t.nil?
      entry = nil
    else
      entry = t.root
    end
    render :partial => 'comments_remote', :locals => { :entry => entry }
  end

private

  def find_opt(ctx = @ctx)
    updated_id = updated_id_in_flash()
    max_comments = @setting.entries_in_thread
    # for inline_comment, we need at least 1 comment.
    if max_comments == 0
      max_comments = 1
    end
    ctx.find_opt.merge(
      :allow_cache => flash[:allow_cache],
      :updated_id => updated_id,
      :fof => (@setting.disable_fof ? nil : 1),
      :maxcomments => max_comments
    )
  end

  def updated_id_in_flash
    flash[:added_id] || flash[:updated_id] || flash[:deleted_id]
  end

  def pin_entry(id)
    if id
      entry = nil
      source = nil
      Entry.if_twitter_id(id) do |tid|
        tid, service_user = tid.split('_', 2)
        id = Entry.from_twitter_id(tid)
        token = auth.tokens.find_by_service_and_service_user('twitter', service_user)
        entry = Tweet.show(token, tid)
        source = 'twitter'
      end
      Entry.add_pin(create_opt(:eid => id, :entry => entry, :source => source))
      commit_checked_modified(id)
    end
  end

  def unpin_entry(id, commit = true)
    if id
      Entry.if_twitter_id(id) do |tid|
        tid, service_user = tid.split('_', 2)
        id = Entry.from_twitter_id(tid)
      end
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

  def redirect_to_entry(threads)
    if param(:show_first)
      if t = threads.first
        if e = t.root
          redirect_to(:action => :show, :eid => e.id)
          true
        end
      end
    end
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
    Feed.find(opt)
  end

  def with_feedinfo(ctx)
    tasks = []
    tasks << Task.run {
      begin
        @feedlist = User.ff_feedlist(auth)
      rescue
        logger.warn($!)
      end
    }
    if @ctx.list? and @ctx.label.nil? and !@ctx.inbox and !@ctx.tweets?
      tasks << Task.run {
        begin
          @feedinfo = User.ff_feedinfo(auth, @ctx.feedid, Feedinfo.opt_exclude(:subscriptions, :subscribers, :services))
        rescue
          logger.warn($!)
        end
      }
    end
    yield
    # just pull the result
    tasks.each do |task|
      task.result
    end
  end

  def pin_check
    if unpin = param(:unpin)
      unpin_entry(unpin)
    end
    if pin = param(:pin)
      pin_entry(pin)
    end
  end

  def render_single_entry
    sess_ctx = session[:ctx]
    with_feedinfo(@ctx) do
      opt = find_opt()
      # We might not yet fetched comments.
      opt.delete(:allow_cache)
      opt.delete(:maxcomments)
      opt.delete(:maxlikes)
      @feed = find_entry_thread(opt)
      @threads = @feed.entries
      if sess_ctx
        # pin/unpin redirect caused :eid set.
        ctx = sess_ctx.dup
        ctx.eid = nil
        opt = find_opt(ctx)
        opt[:allow_cache] = true
        opt.delete(:updated_id)
        opt[:filter_except] = @ctx.eid
        @original_feed = find_entry_thread(opt)
      else
        @original_feed = nil
      end
    end
    if sess_ctx
      sess_ctx.eid = @ctx.eid
    end
    flash[:show_reload_detection] = @ctx.eid
    render :action => 'list'
  end
end
