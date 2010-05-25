require 'google_maps'
require 'entry_context'


class EntryController < ApplicationController
  before_filter :login_required
  before_filter :verify_authenticity_token, :except => [:inbox, :list]
  after_filter :strip_heading_spaces
  after_filter :compress

  # for backward compatibility. it's already in session...
  EntryContext = ::EntryContext

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
    unless auth.authenticated_in_ff?
      session[:back_to] = {:controller => 'entry', :action => 'inbox'}
      redirect_to :controller => 'login', :action => 'initiate_oauth_login'
      return
    end
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
    @ctx.service_source = 'twitter'
    @ctx.feed ||= 'home'
    @ctx.home = false
    id = params[:id]
    unless token = auth.token('twitter', id)
      session[:back_to] = {:controller => 'entry', :action => 'tweets'}
      redirect_to :controller => 'login', :action => 'initiate_twitter_oauth_login'
      return
    end
    @service_source = token.service
    @service_user = token.service_user
    @saved_searches = twitter_saved_searches(token)
    opt = {:count => @ctx.num}
    opt[:max_id] = Entry.if_service_id(@ctx.max_id) if @ctx.max_id
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
    when 'favorites'
      tweets = Tweet.favorites(token, opt)
      feedname = @ctx.feed
    else # home
      if @ctx.query
        tweets = Tweet.search(token, @ctx.query, opt)
        feedname = @ctx.query
      else
        tweets = Tweet.home_timeline(token, opt)
        feedname = 'home'
        last_checked = session[:twitter_last_checked] || Time.at(0)
        next_last_checked = session[:twitter_next_last_checked] || Time.at(0)
        if @ctx.max_id.nil?
          session[:twitter_last_checked] = next_last_checked
        end
      end
    end
    feed_opt = find_opt.merge(
      :tweets => tweets,
      :feedname => "Tweets(#{feedname})",
      :service_user => token.service_user
    )
    @feed = find_entry_thread(feed_opt)
    @threads = @feed.entries
    if next_last_checked
      max = next_last_checked
      @threads.each do |t|
        t.entries.each do |e|
          e.view_unread = last_checked < e.modified_at
          max = [max, e.modified_at].max
        end
      end
      session[:twitter_next_last_checked] = max
    end
    initialize_checked_modified
    render :action => 'list'
  end

  verify :only => :buzz,
          :method => [:get, :post],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}
  def buzz
    pin_check
    @ctx = restore_ctx { |ctx|
      ctx.parse(params, @setting)
    }
    @ctx.service_source = 'buzz'
    @ctx.feed ||= 'home'
    @ctx.home = false
    id = params[:id]
    unless token = auth.token('buzz', id)
      session[:back_to] = {:controller => 'entry', :action => 'buzz'}
      redirect_to :controller => 'login', :action => 'initiate_buzz_oauth_login'
      return
    end
    @service_source = token.service
    @service_user = token.service_user
    opt = {'max-results' => @ctx.num}
    opt[:c] = @ctx.max_id if @ctx.max_id
    opt['max-comments'] = @setting.entries_in_thread
    opt['max-liked'] = F2P::Config.max_friend_list_num
    case @ctx.feed
    when 'user'
      user = @ctx.user || '@me'
      buzz = Buzz.activities(token, "#{user}/@self", opt)
      feedname = 'user'
    else # home
      buzz = Buzz.activities(token, '@me/@consumption', opt)
      feedname = 'home'
      last_checked = session[:buzz_last_checked] || Time.at(0)
      next_last_checked = session[:buzz_next_last_checked] || Time.at(0)
      if @ctx.max_id.nil?
        session[:buzz_last_checked] = next_last_checked
      end
    end
    if nxt = buzz['links']['next']
      @buzz_c_tag = nxt.first['href'].match(/c=([^&]*)/)[1]
    end
    feed_opt = find_opt.merge(
      :buzz => buzz['items'],
      :feedname => "Buzz(#{feedname})",
      :service_user => token.service_user
    )
    @feed = find_entry_thread(feed_opt)
    @threads = @feed.entries
    if next_last_checked
      max = next_last_checked
      @threads.each do |t|
        t.entries.each do |e|
          e.view_unread = last_checked < e.modified_at
          max = [max, e.modified_at].max
        end
      end
      session[:buzz_next_last_checked] = max
    end
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
    buzz = nil
    Entry.if_service_id(@ctx.eid) do |bid|
      unless token = auth.token('buzz')
        session[:back_to] = {:controller => 'entry', :action => 'buzz'}
        redirect_to :controller => 'login', :action => 'initiate_buzz_oauth_login'
        return
      end
      task1 = Task.run { Buzz.show(token, bid) }
      task2 = Task.run { Buzz.comments(token, bid) }
      task3 = Task.run { Buzz.liked(token, bid) }
      buzz = task1.result
      buzz['object']['comments'] = task2.result['items']
      buzz['object']['liked'] = task3.result['entry']
      @service_source = token.service
      @service_user = token.service_user
    end
    @ctx.comment = param(:comment)
    @ctx.moderate = param(:moderate)
    @ctx.home = false
    pin_check
    if buzz
      render_single_buzz_entry(buzz)
    else
      render_single_entry
    end
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
      @ctx.service_source = ctx.service_source
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
    if param(:service_source)
      token = auth.token(param(:service_source), param(:service_user))
      opt[:service_source] = param(:service_source)
      opt[:token] = token
      case param(:service_source)
      when 'twitter'
        unless token
          flash[:message] = 'Token not found'
          render :action => 'tweets'
          return
        end
        if in_reply_to_status_id and opt[:body].index("@#{in_reply_to_screen_name}") == 0
          opt[:in_reply_to_status_id] = in_reply_to_status_id
          @reshared_from = Entry.from_service_id('twitter', in_reply_to_status_id)
        end
      when 'buzz'
        unless token
          flash[:message] = 'Token not found'
          render :action => 'buzz'
          return
        end
      end
    end
    msg = nil
    unpin_entry(@reshared_from, false)
    begin
      entry = Entry.create(opt)
    rescue JSON::ParserError => e
      msg = 'Unexpected response from the server: ' + e.class.name
    rescue Exception => e
      msg = e.message
    end
    unless entry
      msg = 'Posting failure. ' + msg.to_s
      if opt[:file]
        msg += ' Unsupported media type?'
      end
      flash[:message] = msg
      if param(:service_source)
        redirect_to_list
      else
        fetch_feedinfo
        render :action => 'new'
      end
      return
    end
    unpin_entry(@reshared_from, false)
    if session[:ctx]
      session[:ctx].reset_for_new
    end
    flash[:added_id] = entry.id
    redirect_to_list
  end

  verify :only => :retweet,
          :method => [:get, :post],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}
  def retweet
    @ctx = EntryContext.new(auth)
    if ctx = session[:ctx]
      @ctx.inbox = ctx.inbox
    end
    if id = param(:id)
      unless token = auth.token('twitter', param(:service_user))
        flash[:message] = 'Token not found'
        fetch_feedinfo
        render :action => 'tweets'
        return
      end
      begin
        entry = Tweet.retweet(token, Entry.if_service_id(id))
      rescue JSON::ParserError => e
        msg = 'Unexpected response from the server: ' + e.class.name
      rescue Exception => e
        msg = e.message
      end
      unless entry
        msg = 'Retweet failure. ' + msg.to_s
        flash[:message] = msg
      end
    end
    if session[:ctx]
      session[:ctx].reset_for_new
    end
    flash[:retweeted_id] = entry.id
    redirect_to :controller => 'entry', :action => 'tweets'
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
    if param(:service_source) == 'buzz'
      opt = {:eid => id}
      unless token = auth.token(param(:service_source), param(:service_user))
        flash[:message] = 'Token not found'
        render :action => 'buzz'
        return
      end
      opt[:service_source] = param(:service_source)
      opt[:token] = token
      Entry.delete(opt)
    else
      do_delete(id, comment, false)
      flash[:deleted_id] = id
      flash[:deleted_comment] = comment
    end
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
    opt = {:body => body}
    if param(:service_source) == 'buzz'
      unless token = auth.token(param(:service_source), param(:service_user))
        flash[:message] = 'Token not found'
        render :action => 'buzz'
        return
      end
      opt[:service_source] = param(:service_source)
      opt[:token] = token
    end
    if comment
      opt[:comment] = comment
      if c = Entry.edit_comment(create_opt(opt))
        flash[:updated_id] = id
        flash[:updated_comment] = c.id
      end
    else
      opt[:eid] = id
      if c = Entry.add_comment(create_opt(opt))
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
      opt = create_opt(:eid => id)
      if service_source = param(:service_source)
        service_user = param(:service_user)
        token = auth.token(service_source, service_user)
        opt[:token] = token
        opt[:service_source] = service_source
        opt[:service_user] = service_user
      end
      begin
        Entry.add_like(opt)
      rescue
        logger.warn($!)
      end
    end
    unless param(:service_source)
      flash[:updated_id] = id
      flash[:allow_cache] = true
    end
    redirect_to_entry_or_list
  end

  verify :only => :unlike,
          :method => :get,
          :params => [:eid],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}

  def unlike
    if id = param(:eid)
      opt = create_opt(:eid => id)
      if service_source = param(:service_source)
        service_user = param(:service_user)
        token = auth.token(service_source, service_user)
        opt[:token] = token
        opt[:service_source] = service_source
        opt[:service_user] = service_user
      end
      begin
        Entry.delete_like(opt)
      rescue
        logger.warn($!)
      end
    end
    unless param(:service_user)
      flash[:updated_id] = id
      flash[:allow_cache] = true
    end
    redirect_to_entry_or_list
  end

  def like_remote
    @ctx = EntryContext.new(auth)
    id = param(:eid)
    opt = create_opt(:eid => id)
    if service_source = param(:service_source)
      service_user = param(:service_user)
      token = auth.token(service_source, service_user)
      opt[:token] = token
      opt[:service_source] = service_source
      opt[:service_user] = service_user
    end
    begin
      if !!param(:liked)
        entry = Entry.delete_like(opt)
      else
        entry = Entry.add_like(opt)
      end
    rescue
      logger.warn($!)
    end
    unless param(:service_user)
      opt = create_opt(:eid => id, :maxcomments => 0)
      t = find_entry_thread(opt).entries.first
      if t.nil?
        entry = nil
      else
        entry = t.root
      end
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
      opt = {:eid => id}
      if service_source = param(:service_source)
        service_user = param(:service_user)
        token = auth.token(service_source, service_user)
        opt[:token] = token
        opt[:service_source] = service_source
        opt[:service_user] = service_user
      end
      Entry.hide(create_opt(opt))
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
    Entry.if_service_id(id) do |bid|
      token = auth.token('buzz')
      buzz = Buzz.comments(token, bid)
      comments = Entry.buzz_comments(buzz['items'])
      render :partial => 'comments_remote', :locals => { :eid => id, :comments => comments }
      return
    end
    t = find_entry_thread(create_opt(:eid => id)).entries.first
    if t.nil?
      eid = nil
      comments = nil
    else
      entry = t.root
      eid = entry.id
      comments = entry.comments
    end
    render :partial => 'comments_remote', :locals => { :eid => eid, :comments => comments }
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
      Entry.if_service_id(id) do |tid|
        tid, service_source, service_user = tid.split('_', 3)
        id = Entry.from_service_id(service_source, tid)
        token = auth.token(service_source, service_user)
        if token
          case service_source
          when 'twitter'
            entry = Tweet.show(token, tid)
            modified = Time.parse(entry[:created_at]).gmtime.xmlschema
          when 'buzz'
            entry = Buzz.show(token, tid)
            modified = Time.parse(entry['updated']).gmtime.xmlschema
          end
          source = service_source
          # Tweets are not under unread mgmt now.
          remember_checked_modified(id, modified)
        end
      end
      Entry.add_pin(create_opt(:eid => id, :entry => entry, :source => source))
      commit_checked_modified(id)
    end
  end

  def unpin_entry(id, commit = true)
    if id
      Entry.if_service_id(id) do |tid|
        tid, service_source, service_user = tid.split('_', 3)
        if service_source
          id = Entry.from_service_id(service_source, tid)
        end
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

  def render_single_buzz_entry(buzz)
    sess_ctx = session[:ctx]
    opt = find_opt.merge(:buzz => buzz)
    @feed = find_entry_thread(opt)
    @threads = @feed.entries
    @original_feed = nil # can we implement it? needed?
    if sess_ctx
      sess_ctx.eid = @ctx.eid
    end
    flash[:show_reload_detection] = @ctx.eid
    render :action => 'list'
  end

  def twitter_saved_searches(token)
    ss = session[:twitter_saved_search] ||= {}
    if updated_at = ss[:updated_at]
      if ss[:entries] and (Time.now.to_i - updated_at < F2P::Config.twitter_api_cache)
        return ss[:entries]
      end
    end
    # Hash[] needed for session Marshalling to avoid singleton. JSON issue?
    ss[:entries] = Tweet.saved_searches(token).map { |e| Hash[e] }
    ss[:updated_at] = Time.now.to_i
    ss[:entries]
  end
end
