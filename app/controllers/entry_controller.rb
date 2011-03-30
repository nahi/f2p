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
    if @ctx.pin?
      opt = find_opt()
      @feed = find_entry_thread(opt)
      @threads = @feed.entries
      @cont = opt[:start].to_i
    else
      with_feedinfo(@ctx) do
        opt = find_opt()
        @feed = find_entry_thread(opt)
        @threads = @feed.entries
      end
    end
    return if redirect_to_entry(@threads)
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
    @feed = find_entry_thread(find_opt)
    @threads = @feed.entries
    last_checked = session[:friendfeed_last_checked] || Time::ZERO
    next_last_checked = session[:friendfeed_next_last_checked] || Time::ZERO
    if @ctx.start == 0 and updated_id_in_flash.nil?
      last_checked = session[:friendfeed_last_checked] = next_last_checked
    end
    if next_last_checked
      max = next_last_checked
      @threads.each do |t|
        t.entries.each do |e|
          e.checked_at = last_checked
          max = [max, e.modified_at].max
        end
      end
      session[:friendfeed_next_last_checked] = max
    end
    return if redirect_to_entry(@threads)
    render :action => 'list'
  end

  def updated
    redirect_to :action => 'inbox'
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
    if @ctx.query
      @ctx.feed = 'home'
      @ctx.user = nil
    end
    @ctx.home = false
    id = params[:id]
    @body = flash[:post_body]
    unless token = auth.token('twitter', id)
      session[:back_to] = {:controller => 'entry', :action => 'tweets'}
      redirect_to :controller => 'login', :action => 'initiate_twitter_oauth_login'
      return
    end
    @service_source = token.service
    @service_user = token.service_user
    @service_user_screen_name = token.params
    @saved_searches = twitter_saved_searches(token)
    @twitter_lists = twitter_lists(token)
    opt = {:count => @ctx.num}
    opt[:max_id] = Entry.if_service_id(@ctx.max_id) if @ctx.max_id
    case @ctx.feed
    when 'user'
      @ctx.user ||= @service_user_screen_name
      @profile = Tweet.profile(token, @ctx.user)
      opt[:include_rts] = 'true'
      tweets = Tweet.user_timeline(token, @ctx.user, opt)
      twitter_api_initialize(tweets)
      feedname = '@' + (@profile.name || @ctx.user)
    when 'mentions'
      tweets = Tweet.mentions(token, opt)
      twitter_api_initialize(tweets)
      feedname = @ctx.feed
      if tweets
        unless tweets.empty?
          session[:twitter_mentions_last_checked] = tweets.first[:created_at]
          session_cache(:twitter_latest_mention, true) {
            session[:twitter_mentions_last_checked]
          }
        end
      end
    when 'direct'
      t1 = Task.run { Tweet.direct_messages(token, opt) }
      t1.result if $DEBUG
      tweets = Tweet.sent_direct_messages(token, opt) + t1.result
      twitter_api_initialize(t1.result)
      feedname = @ctx.feed
      if sent = t1.result
        unless sent.empty?
          session[:twitter_direct_last_checked] = sent.first[:created_at]
          session_cache(:twitter_latest_dn, true) {
            session[:twitter_direct_last_checked]
          }
        end
      end
    when 'favorites'
      tweets = Tweet.favorites(token, opt)
      twitter_api_initialize(tweets)
      feedname = @ctx.feed
    when 'following'
      opt[:cursor] = @ctx.max_id
      opt.delete(:max_id)
      res = Tweet.friends(token, @ctx.user, opt)
      twitter_api_initialize(res)
      tweets = twitter_users_to_statuses(res)
      max_id_override = res[:next_cursor]
      feedname = @ctx.feed
    when 'followers'
      opt[:cursor] = @ctx.max_id
      opt.delete(:max_id)
      res = Tweet.followers(token, @ctx.user, opt)
      twitter_api_initialize(res)
      tweets = twitter_users_to_statuses(res)
      max_id_override = res[:next_cursor]
      feedname = @ctx.feed
    when 'retweeted_to_me'
      tweets = Tweet.send(@ctx.feed, token, opt)
      twitter_api_initialize(tweets)
      feedname = 'RT by friends'
    when 'retweeted_by_me'
      tweets = Tweet.send(@ctx.feed, token, opt)
      twitter_api_initialize(tweets)
      feedname = 'RT by you'
    when 'retweets_of_me'
      tweets = Tweet.send(@ctx.feed, token, opt)
      twitter_api_initialize(tweets)
      feedname = 'RT of yours'
    when /\A@([^\/]+)\/([^\/]+)\z/
      user, list = $1, $2
      tweets = Tweet.list_statuses(token, user, list, opt)
      twitter_api_initialize(tweets)
      feedname = @ctx.feed
    else
      if @ctx.query
        tweets = Tweet.search(token, @ctx.query, opt)
        twitter_api_initialize(tweets)
        feedname = @ctx.query
      else
        tweets = Tweet.home_timeline(token, opt)
        twitter_api_initialize(tweets)
        feedname = 'home'
        last_checked = session[:twitter_last_checked] || Time::ZERO
        next_last_checked = session[:twitter_next_last_checked] || Time::ZERO
        if @ctx.max_id.nil? and updated_id_in_flash.nil? and @ctx.in_reply_to_status_id.nil?
          last_checked = session[:twitter_last_checked] = next_last_checked
        end
      end
    end
    File.open("/tmp/twitter", "wb") { |f| f << tweets.to_json } if $DEBUG and tweets
    feed_opt = find_opt.merge(
      :tweets => tweets,
      :feedname => "Tweets(#{feedname})",
      :service_user => token.service_user,
      :feed => @ctx.feed
    )
    feed_opt[:merge_entry] = false if max_id_override
    @feed = find_entry_thread(feed_opt)
    @threads = @feed.entries
    @threads.max_id = max_id_override if max_id_override
    if next_last_checked
      max = next_last_checked
      @threads.each do |t|
        t.entries.each do |e|
          e.checked_at = last_checked
          max = [max, e.modified_at].max
        end
      end
      session[:twitter_next_last_checked] = max
    end
    @twitter_mentions_updated = session[:twitter_mentions_last_checked] != twitter_latest_mention(token)
    @twitter_direct_updated = session[:twitter_direct_last_checked] != twitter_latest_direct(token)
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
    if @ctx.query
      @ctx.feed = 'home'
      @ctx.user = nil
    end
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
      t = Task.run { @profile = Buzz.profile(token, user) }
      t.result if $DEBUG
      buzz = Buzz.activities(token, "#{user}/@self", opt)
      t.result
      feedname = @profile.name
    when 'comments'
      user = @ctx.user || '@me'
      buzz = Buzz.activities(token, [user, '@comments'].join('/'), opt)
      feedname = @ctx.feed
    when 'likes'
      user = @ctx.user || '@me'
      buzz = Buzz.activities(token, [user, '@liked'].join('/'), opt)
      feedname = @ctx.feed
    when 'discussions'
      user = @ctx.user || token.params
      opt[:q] = "commenter:#{user}"
      buzz = Buzz.activities(token, 'search', opt)
      feedname = @ctx.feed
    when 'following'
      user = @ctx.user || token.service_user
      @ctx.fold = false
      res = Buzz.groups(token, user, '@following', opt)
      buzz = buzz_users_to_statuses(res)
      feedname = @ctx.feed
    when 'followers'
      user = @ctx.user || token.service_user
      @ctx.fold = false
      res = Buzz.groups(token, user, '@followers', opt)
      buzz = buzz_users_to_statuses(res)
      feedname = @ctx.feed
    else # home
      if @ctx.query
        opt[:q] = @ctx.query
        buzz = Buzz.activities(token, 'search', opt)
        feedname = @ctx.query
      else
        buzz = Buzz.activities(token, '@me/@consumption', opt)
        feedname = 'home'
        last_checked = session[:buzz_last_checked] || Time::ZERO
        next_last_checked = session[:buzz_next_last_checked] || Time::ZERO
        if @ctx.max_id.nil? and updated_id_in_flash.nil?
          last_checked = session[:buzz_last_checked] = next_last_checked
        end
      end
    end
    buzz ||= Hash::EMPTY
    File.open("/tmp/buzz", "wb") { |f| f << buzz.to_json } if $DEBUG
    if buzz['links'] and (nxt = buzz['links']['next'])
      @buzz_c_tag = nxt.first['href'].match(/c=([^&]*)/)[1]
    end
    feed_opt = find_opt.merge(
      :buzz => buzz['items'] || [],
      :feedname => "Buzz(#{feedname})",
      :service_user => token.service_user
    )
    feed_opt[:merge_entry] = false
    @feed = find_entry_thread(feed_opt)
    @threads = @feed.entries
    if next_last_checked
      max = next_last_checked
      @threads.each do |t|
        t.entries.each do |e|
          e.checked_at = last_checked
          max = [max, e.modified_at].max
        end
      end
      session[:buzz_next_last_checked] = max
    end
    render :action => 'list'
  end

  verify :only => :graph,
          :method => [:get, :post],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}
  def graph
    pin_check
    @ctx = restore_ctx { |ctx|
      ctx.parse(params, @setting)
    }
    @ctx.service_source = 'graph'
    @ctx.feed ||= 'home'
    @ctx.home = false
    id = params[:id]
    unless token = auth.token('graph', id)
      session[:back_to] = {:controller => 'entry', :action => 'graph'}
      redirect_to :controller => 'login', :action => 'initiate_facebook_oauth_login'
      return
    end
    @service_source = token.service
    @service_user = token.service_user
    opt = {:limit => @ctx.num}
    opt[:until] = @ctx.max_id
    case @ctx.feed
    when 'user'
      user = @ctx.user || 'me'
      t = Task.run { @profile = Graph.profile(token, user) }
      graph = Graph.connections(token, "#{user}/feed", opt)
      t.result
      feedname = @profile.name
    else # home
      if @ctx.query
        opt[:q] = @ctx.query
        graph = Graph.connections(token, 'search', opt)
        feedname = @ctx.query
      else
        graph = Graph.connections(token, 'me/home', opt)
        feedname = 'News feed'
        last_checked = session[:graph_last_checked] || Time::ZERO
        next_last_checked = session[:graph_next_last_checked] || Time::ZERO
        if @ctx.max_id.nil? and updated_id_in_flash.nil?
          last_checked = session[:graph_last_checked] = next_last_checked
        end
      end
    end
    File.open('/tmp/graph', 'w') { |f| f << graph.to_json } if $DEBUG and graph
    feed_opt = find_opt.merge(
      :graph => graph['data'],
      :feedname => "Facebook(#{feedname})",
      :service_user => token.service_user
    )
    @feed = find_entry_thread(feed_opt)
    @threads = @feed.entries
    if next_last_checked
      max = next_last_checked
      @threads.each do |t|
        t.entries.each do |e|
          e.checked_at = last_checked
          max = [max, e.modified_at].max
        end
      end
      session[:graph_next_last_checked] = max
    end
    render :action => 'list'
  end

  verify :only => :delicious,
          :method => [:get, :post],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}
  def delicious
    pin_check
    @ctx = restore_ctx { |ctx|
      ctx.parse(params, @setting)
    }
    @ctx.service_source = 'delicious'
    @ctx.feed ||= 'home'
    @ctx.home = false
    unless token = auth.token('delicious')
      session[:back_to] = {:controller => 'entry', :action => 'delicious'}
      redirect_to :controller => 'login', :action => 'initiate_delicious_oauth_login'
      return
    end
    @service_source = token.service
    @service_user = token.service_user
    opt = {:results => @ctx.num, :start => @ctx.start}
    if @ctx.query
      opt[:tag] = @ctx.query
      feedname = @ctx.query
    elsif @ctx.label
      opt[:tag] = @ctx.label
      feedname = @ctx.label
    else
      feedname = 'all'
    end
    posts = Delicious.all(token, opt)
    File.open('/tmp/delicious', 'w') { |f| f << posts.to_json } if $DEBUG and posts
    feed_opt = find_opt.merge(
      :delicious => posts ? posts['post'] : Array::EMPTY,
      :feedname => "Delicious(#{feedname})",
      :merge_entry => false,
      :service_user => token.service_user
    )
    @feed = find_entry_thread(feed_opt)
    @threads = @feed.entries
    render :action => 'list'
  end

  verify :only => :tumblr,
          :method => [:get, :post],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'inbox'}
  def tumblr
    pin_check
    @ctx = restore_ctx { |ctx|
      ctx.parse(params, @setting)
    }
    @ctx.service_source = 'tumblr'
    @ctx.feed ||= 'home'
    if @ctx.query
      @ctx.feed = 'home'
    end
    @ctx.home = false
    id = params[:id]
    unless token = auth.token('tumblr', id)
      session[:back_to] = {:controller => 'entry', :action => 'tumblr'}
      redirect_to :controller => 'login', :action => 'initiate_tumblr_oauth_login'
      return
    end
    @service_source = token.service
    @service_user = token.service_user
    opt = {:start => @ctx.start, :num => @ctx.num}
    case @ctx.feed
    when 'user'
      user = @ctx.user || @service_user
      tumblr = Tumblr.read(token, user, opt)
      @profile = tumblr['profile']
      feedname = user
    else
      if @ctx.query and @ctx.user
        tumblr = Tumblr.search(token, @ctx.user, @ctx.query, opt)
        @profile = tumblr['profile']
        feedname = @ctx.query
      else
        tumblr = Tumblr.dashboard(token, opt)
        feedname = 'home'
        last_checked = session[:tumblr_last_checked] || Time::ZERO
        next_last_checked = session[:tumblr_next_last_checked] || Time::ZERO
        if @ctx.start == 0 and updated_id_in_flash.nil?
          last_checked = session[:tumblr_last_checked] = next_last_checked
        end
      end
    end
    File.open("/tmp/tumblr", "wb") { |f| f << tumblr.to_json } if $DEBUG
    feed_opt = find_opt.merge(
      :tumblr => tumblr ? tumblr['posts'] : Array::EMPTY,
      :feedname => "Tumblr(#{feedname})",
      :service_user => token.service_user,
      :feed => @ctx.feed
    )
    @feed = find_entry_thread(feed_opt)
    @threads = @feed.entries
    if next_last_checked
      max = next_last_checked
      @threads.each do |t|
        t.entries.each do |e|
          e.checked_at = last_checked
          max = [max, e.modified_at].max
        end
      end
      session[:tumblr_next_last_checked] = max
    end
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
    @body = flash[:post_body]
    entry = nil
    Entry.if_service_id(@ctx.eid) do |sid|
      case @ctx.eid[0]
      when ?t
        unless token = auth.token('twitter')
          session[:back_to] = {:controller => 'entry', :action => 'tweets'}
          redirect_to :controller => 'login', :action => 'initiate_twitter_oauth_login'
          return
        end
        if param(:rt)
          t = Task.run { Tweet.retweets(token, sid, :count => F2P::Config.max_friend_list_num) }
          t.result if $DEBUG
        end
        entry = Tweet.show(token, sid)
        twitter_api_initialize(entry)
        if param(:rt)
          entry[:retweets] = t.result
        end
      when ?b
        unless token = auth.token('buzz')
          session[:back_to] = {:controller => 'entry', :action => 'buzz'}
          redirect_to :controller => 'login', :action => 'initiate_buzz_oauth_login'
          return
        end
        entry = Buzz.show_all(token, sid)
      when ?g
        unless token = auth.token('graph')
          session[:back_to] = {:controller => 'entry', :action => 'graph'}
          redirect_to :controller => 'login', :action => 'initiate_facebook_oauth_login'
          return
        end
        entry = Graph.show_all(token, sid)
        File.open('/tmp/graph', 'w') { |f| f << entry.to_json } if $DEBUG and entry
      when ?m
        unless token = auth.token('tumblr')
          session[:back_to] = {:controller => 'entry', :action => 'tumblr'}
          redirect_to :controller => 'login', :action => 'initiate_tumblr_oauth_login'
          return
        end
        entry = Tumblr.show(token, sid)
        File.open('/tmp/tumblr', 'w') { |f| f << entry.to_json } if $DEBUG and entry
      end
      if pin = Pin.find_by_user_id_and_eid(auth.id, @ctx.eid)
        pin.entry = entry
        pin.save!
      end
      @service_source = token.service
      @service_user = token.service_user
    end
    @ctx.comment = param(:comment)
    @ctx.moderate = param(:moderate)
    @ctx.service_source = @service_source
    @ctx.home = false
    pin_check
    case @service_source
    when 'twitter'
      render_single_twitter_entry(entry)
    when 'buzz'
      render_single_buzz_entry(entry)
    when 'graph'
      render_single_graph_entry(entry)
    when 'tumblr'
      render_single_tumblr_entry(entry)
    else
      render_single_entry
    end
    @threads = @feed.entries
    if sess_ctx = session[:ctx]
      sess_ctx.eid = @ctx.eid
    end
    flash[:show_reload_detection] = @ctx.eid
    render :action => 'list'
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
      when 'graph'
        unless token
          flash[:message] = 'Token not found'
          render :action => 'graph'
          return
        end
      end
    end
    msg = nil
    unpin_entry(@reshared_from)
    begin
      entry = Entry.create(opt)
    rescue JSON::ParserError => e
      logger.warn(e)
      msg = 'Unexpected response from the server: ' + e.class.name
    rescue Exception => e
      logger.warn(e)
      msg = e.message
    end
    unless entry
      set_post_error(msg, @body)
      if param(:service_source)
        redirect_to_list
      else
        fetch_feedinfo
        render :action => 'new'
      end
      return
    end
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
      @ctx.service_source = ctx.service_source
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
        logger.warn(e)
        msg = 'Unexpected response from the server: ' + e.class.name
      rescue Exception => e
        logger.warn(e)
        msg = e.message
      end
      if entry
        flash[:retweeted_id] = entry.id
      else
        msg = 'Retweet failure. ' + msg.to_s
        flash[:message] = msg
      end
    end
    if session[:ctx]
      session[:ctx].reset_for_new
    end
    redirect_to_list
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
    if param(:service_source)
      opt = {:eid => id}
      opt[:service_source] = param(:service_source)
      opt[:token] = auth.token(param(:service_source), param(:service_user))
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
    in_reply_to_screen_name = param(:in_reply_to_screen_name)
    in_reply_to_status_id = param(:in_reply_to_status_id)
    opt = {:body => body}
    if param(:service_source)
      token = auth.token(param(:service_source), param(:service_user))
      opt[:service_source] = param(:service_source)
      opt[:token] = token
    end
    if in_reply_to_status_id
      opt[:in_reply_to_status_id] = in_reply_to_status_id
    end
    if comment
      opt[:comment] = comment
      if c = Entry.edit_comment(create_opt(opt))
        flash[:updated_id] = id
        flash[:updated_comment] = c.id
      end
    else
      opt[:eid] = id
      msg = nil
      begin
        c = Entry.add_comment(create_opt(opt))
      rescue Exception => e
        logger.warn(e)
        msg = e.message
      end
      unless c
        set_post_error(msg, body)
        if param(:service_source) == 'twitter'
          redirect_to(:action => :show, :eid => id)
        else
          redirect_to_entry_or_list
        end
        return
      end
      unpin_entry(id)
      flash[:added_id] = id
      flash[:added_comment] = c.id
    end
    if param(:service_source) == 'twitter'
      redirect_to_list
      return
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
        opt[:tumblr_reblog_key] = param(:reblog_key) if param(:reblog_key)
      end
      begin
        Entry.add_like(opt)
      rescue
        logger.warn($!)
      end
    end
    unless param(:service_source)
      flash[:updated_id] = id
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
        opt[:tumblr_reblog_key] = param(:reblog_key) if param(:reblog_key)
      end
      begin
        Entry.delete_like(opt)
      rescue
        logger.warn($!)
      end
    end
    unless param(:service_user)
      flash[:updated_id] = id
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
      opt[:tumblr_reblog_key] = param(:reblog_key) if param(:reblog_key)
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
    @ctx = session[:ctx] || EntryContext.new(auth)
    id = param(:eid)
    Entry.if_service_id(id) do |sid|
      case id[0]
      when ?b
        token = auth.token('buzz')
        buzz = Buzz.comments(token, sid)
        comments = Entry.buzz_comments(buzz['items'])
        last_checked = session[:buzz_last_checked]
      when ?g
        token = auth.token('graph')
        graph = Graph.comments(token, sid)
        comments = Entry.graph_comments(graph['data'])
        last_checked = session[:buzz_last_checked]
      end
      comments.each do |c|
        c.checked_at = last_checked
      end
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
      last_checked = session[:friendfeed_last_checked]
      comments.each do |c|
        c.checked_at = last_checked
      end
    end
    render :partial => 'comments_remote', :locals => { :eid => eid, :comments => comments }
  end

private

  def set_post_error(msg, body)
    msg = 'Posting failure. ' + msg.to_s
    msg += " (Posted #{body.to_s.split(//u).size} chars)"
    flash[:message] = msg
    flash[:post_body] = @body
  end

  def find_opt(ctx = @ctx)
    updated_id = updated_id_in_flash()
    max_comments = @setting.entries_in_thread
    # for inline_comment, we need at least 1 comment.
    if max_comments == 0
      max_comments = 1
    end
    ctx.find_opt.merge(
      :updated_id => updated_id,
      :fof => (@setting.disable_fof ? nil : 1),
      :maxcomments => max_comments
    )
  end

  def updated_id_in_flash
    flash[:added_id] || flash[:updated_id] || flash[:deleted_id] || flash[:retweeted_id]
  end

  def pin_entry(id)
    if id
      entry = nil
      source = nil
      Entry.if_service_id(id) do |sid|
        sid, service_source, service_user = split_sid(sid)
        id = Entry.from_service_id(service_source, sid)
        token = auth.token(service_source, service_user)
        if token
          case service_source
          when 'twitter'
            entry = Tweet.show(token, sid)
          when 'buzz'
            entry = Buzz.show_all(token, sid)
          when 'graph'
            entry = Graph.show_all(token, sid)
          when 'delicious'
            entry = Delicious.get(token, sid)
          when 'tumblr'
            entry = Tumblr.show(token, sid)
          end
          source = service_source
        end
      end
      Entry.add_pin(create_opt(:eid => id, :entry => entry, :source => source))
    end
  end

  def unpin_entry(id)
    if id
      Entry.if_service_id(id) do |sid|
        sid, service_source, service_user = split_sid(sid)
        if service_source
          id = Entry.from_service_id(service_source, sid)
        end
      end
      Entry.delete_pin(create_opt(:eid => id))
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
    opt = find_opt()
    # We might not yet fetched comments.
    opt.delete(:maxcomments)
    opt.delete(:maxlikes)
    @feed = find_entry_thread(opt)
    if sess_ctx
      # pin/unpin redirect caused :eid set.
      ctx = sess_ctx.dup
      ctx.eid = nil
      opt = find_opt(ctx)
      opt.delete(:updated_id)
      opt[:filter_except] = @ctx.eid
      @original_feed = find_entry_thread(opt)
    else
      @original_feed = nil
    end
  end

  def render_single_twitter_entry(tweet)
    opt = find_opt.merge(:tweets => tweet)
    @feed = find_entry_thread(opt)
    @original_feed = nil # can we implement it? needed?
  end

  def render_single_buzz_entry(buzz)
    opt = find_opt.merge(:buzz => buzz)
    @feed = find_entry_thread(opt)
    @original_feed = nil # can we implement it? needed?
  end

  def render_single_graph_entry(graph)
    opt = find_opt.merge(:graph => graph)
    @feed = find_entry_thread(opt)
    @original_feed = nil # can we implement it? needed?
  end

  def render_single_tumblr_entry(post)
    opt = find_opt.merge(:tumblr => post)
    @feed = find_entry_thread(opt)
    @original_feed = nil # can we implement it? needed?
  end

  def twitter_latest_mention(token)
    session_cache(:twitter_latest_mention) {
      if tweets = Tweet.mentions(token, :count => 1)
        unless tweets.empty?
          tweets.first[:created_at]
        end
      end
    }
  end

  def twitter_latest_direct(token)
    session_cache(:twitter_latest_direct) {
      if tweets = Tweet.direct_messages(token, :count => 1)
        if tweets.empty?
          'N/A'
        else
          tweets.first[:created_at]
        end
      end
    }
  end

  def twitter_saved_searches(token)
    session_cache(:twitter_saved_search) {
      # Hash[] needed for session Marshalling to avoid singleton. JSON issue?
      if tweets = Tweet.saved_searches(token)
        tweets.map { |e| Hash[e] }
      end
    }
  end

  def twitter_lists(token)
    session_cache(:twitter_lists) {
      if tweets = Tweet.lists(token, token.service_user)
        tweets.map { |e|
          {
            :id => e[:id],
            :name => e[:name],
            :full_name => e[:full_name]
          }
        }
      end
    }
  end

  def split_sid(sid)
    components = sid.split('_')
    service_user = components.pop
    service_source = components.pop
    if components.empty?
      # Graph API uses id format: 'nnnnn_nnnn' so here may be 'g_nnnn_nnnn'
      return sid, nil, nil
    else
      return components.join('_'), service_source, service_user
    end
  end

  def twitter_api_initialize(res)
    @api_remaining = res.ratelimit_remaining.to_i
    @api_limit = res.ratelimit_limit.to_i
    @api_to_reset = res.ratelimit_reset.to_i - Time.now.to_i
  end

  def twitter_users_to_statuses(res)
    users = res[:users] || Array::EMPTY
    users.map { |hash|
      s = hash[:status] || {}
      s[:id] ||= "0"
      s[:user] = hash
      hash[:status] = nil
      s.delete(:retweeted_status)
      s['service_source'] = hash['service_source']
      s['service_user'] = hash['service_user']
      s
    }
  end

  def buzz_users_to_statuses(res)
    users = res['entry'] || Array::EMPTY
    {
      'items' =>
        users.map { |hash|
          s = {}
          s['id'] = hash['id']
          s['title'] = Entry.normalize_content_in_buzz(hash['aboutMe']) || ''
          s['actor'] = hash
          s['crosspostSource'] = hash['profileUrl']
          s['service_source'] = hash['service_source']
          s['service_user'] = hash['service_user']
          s
        }
    }
  end
end
