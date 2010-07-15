# Methods added to this helper will be available to all templates in the application.

require 'time'
require 'xsd/datatypes'
require 'geo_city'


module ApplicationHelper
  include XSD::XSDDateTimeImpl

  APPNAME = 'm.ctor.org'
  DATE_THRESHOLD = (24 - 8).hours
  YEAR_THRESHOLD = 1.year - 2.days
  SELF_LABEL = 'You'
  SELF_FEED_LABEL = 'Your feed'
  GWT_URL_BASE = 'http://www.google.com/gwt/n?u='
  IMG_MAX_HEIGHT = 175
  IMG_MAX_WIDTH = 525
  ICON_NAME = {
    'liked' => 'emoticon_smile.png',
    'like' => 'thumb_up.png',
    'comment' => 'comment.png',
    'friend_comment' => 'user_comment.png',
    'comment_add' => 'comment_add.png',
    'comment_edit' => 'comment_edit.png',
    'delete' => 'delete.png',
    #'more' => 'add.png',
    'write' => 'pencil_add.png',
    'settings' => 'cog_edit.png',
    'search' => 'find.png',
    'logout' => 'user_go.png',
    'previous' => 'resultset_previous.png',
    'next' => 'resultset_next.png',
    'url' => 'world_link.png',
    'reshare' => 'pencil_go.png',
    'related' => 'link.png',
    'go' => 'page_white_world.png',
    'media_disabled' => 'image.png',
    'images' => 'images.png',
    'pinned' => 'star.png',
    'pin' => 'bullet_arrow_down.png',
    'bottom' => 'arrow_down.png',
    'top' => 'arrow_up.png',
    'map' => 'map.png',
    'help' => 'help.png',
    'group' => 'group.png',
    'private' => 'lock.png',
    'hide' => 'sound_mute.png',
    'shield' => 'shield.png',
  }
  OAUTH_IMAGE_URL = 'http://friendfeed.com/static/images/sign-in-with-friendfeed.png'

  def ajax?
    setting and setting.use_ajax
  end

  def jpmobile?
    @controller.jpmobile?
  end

  def cell_phone?
    @controller.cell_phone?
  end

  def i_mode?
    @controller.i_mode?
  end

  def iphone?
    @controller.iphone?
  end

  def android?
    @controller.android?
  end

  def accesskey(key)
    @accesskey ||= {}
    key = key.to_s
    key = nil if @accesskey.key?(key)
    @accesskey[key] = true
    {:accesskey => key}
  end

  def inline_meta(opt = {})
    if iphone? or android?
      str = content_tag('meta', nil, :name => 'viewport', :content => 'width=device-width; initial-scale=1.0')
    else
      str = content_tag('meta', nil, :name => 'viewport', :content => 'width=device-width, height=device-height')
    end
    if opt[:reload] and setting
      if setting.reload_list_in_minutes and setting.reload_list_in_minutes > 0
        str += content_tag('meta', nil, 'http-equiv' => 'refresh', :content => setting.reload_list_in_minutes * 60)
      end
    end
    str
  end

  def inline_stylesheet
    return if i_mode?
    content = <<__EOS__
  img.inline  { vertical-align: text-top; }
  img.profile {
    border: 1px solid #ccc;
    padding: 0px;
    vertical-align: text-bottom;
  }
  img.media   {
    border: 1px solid #ccc;
    padding: 1px;
    vertical-align: text-top;
  }
  a img { border: none; }
  a.twname {
    text-decoration: none;
    color: black;
  }
  a.hlink { text-decoration: none; }
  p {
    margin-top: 1ex;
    margin-bottom: 1ex;
  }
  p.message { color: red; }
  textarea { vertical-align: text-top; }
  .latest1 { color: #F00; }
  .latest2 { color: #C00; }
  .latest3 { color: #900; }
  .older { color: #008; }
  .archived { color: #558; }
  .inbox { font-weight: bold; }
  .hashtag a { color: #000; }
  .comment-body,.likes {
    text-indent: -16px;
    margin-left: 16px;
  }
  .comment-block { margin-top: 0.2ex; margin-left: 1ex; }
  .comment-body { margin-top: 0.6ex; }
  .comment-fold { margin-left: 16px; }
  .comment-fold a { color: #666; }
  .menu-links {
    background-color: #ddf;
    border-top: 1px solid #aaf;
    border-bottom: 1px solid #aaf;
    padding-top: 0.6ex;
    padding-bottom: 0.6ex;
  }
  div.single a.menu-link {
    border: outset 1px;
    text-decoration: none;
    color: #999;
  }
  div.listings a.menu-link {
    text-decoration: none;
    color: #999;
  }
  div.single .menu-links a.menu-link {
    color: #000;
    background-color: #aaf;
  }
  div.listings .menu-links a.menu-link {
    border: outset 1px;
    color: #000;
    background-color: #aaf;
  }
  div.listings .thread1,.thread2 {
    border-top: 1px solid #aaf;
    padding-top: 0.5ex;
    padding-bottom: 0.8ex;
  }
  div.listings .page-links-bottom {
    margin-bottom: 1em;
  }
  div.listings hr.separator { display: none; }
  div.listings .body {
    margin-top: 0.5ex;
    text-indent: -16px;
    margin-left: 16px;
  }
  div.listings .entry { margin-bottom: 0.8ex; }
  div.listings .related {
    margin-top: 1.0ex;
    margin-bottom: 0.8ex;
  }
  div.listings .tweets { color: #666; }
  div.listings .tweets a.twname { color: #666; }
  div.single {
    border-bottom: 1px solid #aaf;
    margin-bottom: 1em;
  }
  div.single .body {
    padding-top: 1.5ex;
    padding-bottom: 1ex;
  }
  div.single .likes a.menu-link { border: none; }
  #{ inline_stylesheet_iphone }
__EOS__
    if setting and setting.font_size
      body_size = setting.font_size
      content += <<__EOS__
  body { font-size: #{body_size}pt; }
__EOS__
    end
    content_tag('style', content, :type => "text/css")
  end

  def inline_stylesheet_iphone
    if iphone? or android?
      if setting and setting.font_size
        menu_size = setting.font_size + 1
      else
        menu_size = 13
      end
      <<__EOS__
  body {
    -webkit-user-select: none;
    -webkit-text-size-adjust: none;
    font-family: Arial,Helvetica,sans-serif;
  }
  input.text {
    -webkit-text-size-adjust: 200%;
  }
  a.menu-link {
    color: #3333cc;
    text-decoration: none;
  }
  .menu-links {
    font-size: #{menu_size}pt;
  }
  a.tab {
    display: block;
    float: left;
    line-height: 32px;
    padding-left: 4px;
    padding-right: 4px;
    font-size: 12px;
    font-weight: bold;
    font-family: Helvetica, sans-serif;
    text-decoration: none;
    text-align: center;
    color: #000;
    text-shadow: #fff 0px 1px 1px;
  }
  .tabclear { clear: left; }
__EOS__
    end
  end

  def oauth_image_tag
    label = 'OAuth'
    link_to(image_tag(icon_url('sign-in-with-friendfeed.gif'), :alt => h(label), :title => h(label)), :controller => :login, :action => :initiate_oauth_login)
  end

  def top_marker
    if auth and auth.oauth?
      icon_tag(:shield)
    end
  end

  def top_menu
    links = []
    links << link_to(h('FF'), { :controller => :entry, :action => :inbox }, accesskey('0').merge(:class => :tab))
    links << link_to(h('Twitter'), { :controller => :entry, :action => :tweets }, {:class => :tab})
    links << link_to(h('Buzz'), { :controller => :entry, :action => :buzz }, {:class => :tab})
    links << link_to(h('FB'), { :controller => :entry, :action => :graph }, {:class => :tab})
    #links << link_to(h('Delicious'), { :controller => :entry, :action => :delicious }, {:class => :tab})
    links << link_to(h('Tumblr'), { :controller => :entry, :action => :tumblr }, {:class => :tab})
    pin_label = h('Star')
    pin_label += "(#{@threads.pins})" if @threads
    links << link_to(pin_label, { :controller => :entry, :action => :list, :label => 'pin' }, {:class => :tab})
    links << link_to(h('[menu]'), '#bottom', accesskey('8').merge(:class => :tab))
    links.join(' ')
  end

  def span(body, klass)
    content_tag('span', body, :class => klass)
  end

  def common_menu(*arg)
    [
      settings_link,
      logout_link,
      help_link,
      to_top_menu
    ].compact.join(' ')
  end

  def to_top_menu
    menu_link(menu_label('^', '2'), '#top', accesskey('2'))
  end

  def self_label
    SELF_LABEL
  end

  def self_feed_label
    SELF_FEED_LABEL
  end

  def timezone
    @timezone || F2P::Config.timezone
  end

  def now
    @now ||= Time.now.in_time_zone(timezone)
  end

  def lock_icon_tag
    label = 'private'
    image_tag(icon_url('private'), :class => h('inline'), :alt => h(label), :title => h(label))
  end

  def icon_url(name)
    icon_name = ICON_NAME[name.to_s]
    if icon_name and i_mode?
      icon_name = icon_name.sub(/.png\z/, '.gif')
    end
    F2P::Config.icon_url_base + (icon_name || name.to_s)
  end

  def icon_tag(name, alt = nil, opt = {})
    name = name.to_s
    label = alt || name.gsub(/_/, ' ')
    image_tag(icon_url(name), opt.merge(:alt => h(label), :title => h(label), :size => '16x16'))
  end

  def inline_icon_tag(name, alt = nil)
    name = name.to_s
    label = alt || name.gsub(/_/, ' ')
    image_tag(icon_url(name), :class => h('inline'), :alt => h(label), :title => h(label), :size => '16x16')
  end

  def service_icon_tag(url, alt, title)
    if i_mode? and %r{([^/]*)\.png\b} =~ url
      url = icon_url($1 + '.gif')
    end
    image_tag(url, :class => 'inline', :alt => h(alt), :title => h(title), :size => '16x16')
  end

  def friendfeed_icon_tag
    service_icon_tag('http://friendfeed.com/static/images/icons/internal.png', 'FriendFeed', 'FriendFeed')
  end

  def twitter_icon_tag
    service_icon_tag('http://friendfeed.com/static/images/icons/twitter.png', 'Twitter', 'Twitter')
  end

  def buzz_icon_tag
    service_icon_tag('http://buzzusers.com/images/buzzicon.png', 'Twitter', 'Buzz')
  end

  def facebook_icon_tag
    service_icon_tag('http://friendfeed.com/static/images/icons/facebook.png', 'Facebook', 'Facebook')
  end

  def delicious_icon_tag
    service_icon_tag('http://friendfeed.com/static/images/icons/delicious.png', 'Delicious', 'Delicious')
  end

  def tumblr_icon_tag
    service_icon_tag('http://friendfeed.com/static/images/icons/tumblr.png', 'Tumblr', 'Tumblr')
  end

  def profile_image_tag(url, alt, title)
    image_tag(url, :class => h('profile'), :alt => h(alt), :title => h(title), :size => '25x25')
  end

  def inbox_link
    menu_link(menu_label('show inbox', '0'), { :controller => :entry, :action => :inbox }, accesskey('0'))
  end

  def pinned_link(pin_label = 'Star')
    link_to(h(pin_label), { :controller => :entry, :action => :list, :label => 'pin' }, accesskey('9'))
  end

  def settings_link
    menu_link(menu_label('settings'), :controller => 'setting', :action => 'index')
  end

  def logout_link
    menu_link(menu_label('logout'), :controller => 'login', :action => 'clear')
  end

  def help_link
    menu_link(menu_label('?'), :controller => 'help', :action => 'index')
  end

  def u(arg)
    if arg
      super(arg)
    end
  end

  def appname
    h(APPNAME)
  end

  def setting
    @setting
  end

  def auth
    @auth
  end

  def imaginary?(id)
    /\A[0-9a-f]{32}\z/ =~ id
  end

  def picture_link(id, size = 'small')
    if picture = picture(id, size)
      link_to(picture, User.ff_url(id))
    end
  end

  def picture(id, size = 'small')
    name = id
    if name == auth.name
      name = self_label
    end
    image_url = User.ff_picture_url(id, size)
    profile_image_tag(image_url, name, name)
  end

  def user(user, opt = nil)
    return unless user
    case user.service_source
    when 'twitter'
      return link_to(h(user.name), user.profile_url)
    when 'buzz'
      opt ||= { :controller => 'entry', :action => 'buzz', :feed => 'user', :user => u(user.id) }
    when 'graph'
      opt ||= { :controller => 'entry', :action => 'graph', :feed => 'user', :user => u(user.id) }
    when 'tumblr'
      opt ||= { :controller => 'entry', :action => 'tumblr', :feed => 'user', :user => u(user.id) }
    else
      opt ||= { :controller => 'entry', :action => 'list', :user => u(user.id) }
    end
    name = user.name
    if user.id == auth.name
      name = self_label
    end
    link_to(h(name), opt)
  end

  def via(via, label = 'via')
    if via
      if via.url
        %Q[#{label} #{link_to(h(via.name), via.url)}]
      elsif via.name
        %Q[#{label} #{h(via.name)}]
      end
    end
  end

  def image_size(width, height)
    "#{width}x#{height}"
  end

  def image_max_style(width = IMG_MAX_WIDTH, height = IMG_MAX_HEIGHT)
    "max-width:#{width}px;max-height:#{height}px"
  end

  def title_date
    h(now.strftime("%H:%M"))
  end

  def date(time, compact = true)
    return unless time
    unless time.is_a?(Time)
      time = Time.parse(time.to_s)
    end
    elapsed = now - time
    format = nil
    if !compact
      if elapsed > YEAR_THRESHOLD
        format = "[%y/%m/%d %H:%M]"
      else
        format = "[%m/%d %H:%M]"
      end
    else
      if elapsed > YEAR_THRESHOLD
        format = "(%y/%m/%d)"
      elsif elapsed > DATE_THRESHOLD
        format = "(%m/%d)"
      else
        format = "(%H:%M)"
      end
    end
    body = time.in_time_zone(timezone).strftime(format)
    latest(time, body)
  end

  def latest(time, body)
    case elapsed(time)
    when (-1.hour)..(1.hour) # may have a time lag
      klass = 'latest1'
    when 0..3.hour
      klass = 'latest2'
    when 0..6.hour
      klass = 'latest3'
    else
      klass = 'older'
    end
    span(h(body), klass)
  end

  def ago(time)
    unless time.is_a?(Time)
      time = Time.parse(time.to_s)
    end
    elapsed = now - time
    if elapsed > 2.days
      "%d days" % (elapsed / 1.days)
    elsif elapsed > 1.days
      "1 day"
    elsif elapsed > 2.hours
      "%d hours" % (elapsed / 1.hours)
    elsif elapsed > 1.hours
      "1 hour"
    elsif elapsed > 2.minutes
      "%d minutes" % (elapsed / 1.minutes)
    elsif elapsed > 1.minutes
      "1 minute"
    else
      "%d seconds" % (elapsed / 1.seconds)
    end
  end

  def elapsed(time)
    if time
      now - time
    end
  end

  def link_to(name, options = {}, html_opt = nil)
    if setting and options.is_a?(String) and !url_for_app?(options)
      html_opt ||= {}
      if setting.link_open_new_window
        html_opt = html_opt.merge(:target => '_blank')
      end
      if setting.link_type == 'gwt'
        return super(name, GWT_URL_BASE + u(options), html_opt)
      else
        return super(name, options, html_opt)
      end
    end
    super
  end

  def url_for_app?(url)
    !!url.index(url_for(:only_path => false, :controller => '')) or url[0] == ?#
  end

  def link_url(url)
    link_to(h(url), url)
  end

  def q(str)
    h('"') + str + h('"')
  end

  def fold_length(str, length)
    len = length.to_i
    return '' if len <= 0
    str.scan(Regexp.new("^.{0,#{len.to_s}}", Regexp::MULTILINE, 'u'))[0] || ''
  end

  def need_unread_mgmt?
    ctx.inbox or (ctx.feed == 'home' and (ctx.tweets? or ctx.buzz?))
  end

  def links_if_exists(label, enum, max = nil, &block)
    if max and enum.size > max + 1
      ary = enum[0, max].collect { |v| yield(v) }
      ary << "... #{enum.size - max} more"
    else
      ary = enum.collect { |v| yield(v) }
    end
    unless ary.empty?
      ary.unshift(h(label))
      ary.join(' ')
    end
  end

  def menu_link(label, opt, html_opt = nil, &block)
    if block.nil? or block.call
      link_to(label, opt, (html_opt || {}).merge(:class => 'menu-link'))
    else
      label
    end
  end

  def menu_label(label, accesskey = nil, reverse = false)
    h("[#{label_with_accesskey(label, accesskey, reverse)}]")
  end

  def menu_icon(icon, accesskey = nil, reverse = false)
    label_with_accesskey(inline_icon_tag(icon), accesskey, reverse)
  end

  def label_with_accesskey(label, accesskey = nil, reverse = false)
    if accesskey and cell_phone?
      if reverse
        label + '.' + accesskey
      else
        accesskey + '.' + label
      end
    else
      label
    end
  end

  def subscribe_status_edit_link
    link_to(menu_label('edit'), :id => @id, :action => :edit)
  end

  def subscribe_status
    return unless @feedinfo
    if @feedinfo.commands.include?('unsubscribe')
      '(subscribed)'
    elsif @feedinfo.commands.include?('subscribe')
      '(not subscribed)'
    end
  end

  def feed_name
    if @feed
      @feed.name
    elsif @feedinfo
      @feedinfo.name
    end
  end

  def feed_name_with_icon
    if @feedinfo
      str = h(feed_name)
      str += lock_icon_tag if @feedinfo.private
      str
    end
  end

  def feed_description
    return unless @feedinfo
    @feedinfo.description
  end

  def subscription_name(from)
    if from.friend?
      '*' + from.name
    else
      from.name
    end
  end

  def feed_subscriptions_friend
    return unless @feedinfo
    max = F2P::Config.max_friend_list_num
    map = @feedinfo.subscribers.inject({}) { |r, e| r[e.id] = true; r }
    lists = @feedinfo.feeds + @feedinfo.subscriptions
    lists = lists.find_all { |e| e.user? and map.key?(e.id) }
    lists = lists.partition { |e| e.friend? }.flatten
    title = "Friend(#{lists.size}): "
    links_if_exists(title, lists, max) { |e|
      link_to(h(subscription_name(e)), link_entry_list(:user => e.id))
    }
  end

  def feed_subscriptions_user
    return unless @feedinfo
    max = F2P::Config.max_friend_list_num
    map = @feedinfo.subscribers.inject({}) { |r, e| r[e.id] = true; r }
    lists = @feedinfo.feeds + @feedinfo.subscriptions
    lists = lists.find_all { |e| e.user? and !map.key?(e.id) }
    lists = lists.partition { |e| e.friend? }.flatten
    title = "User subscription(#{lists.size}): "
    links_if_exists(title, lists, max) { |e|
      link_to(h(subscription_name(e)), link_entry_list(:user => e.id))
    }
  end

  def feed_subscriptions_group
    return unless @feedinfo
    max = F2P::Config.max_friend_list_num
    lists = @feedinfo.feeds + @feedinfo.subscriptions
    lists = lists.find_all { |e| e.group? }
    lists = lists.partition { |e| e.friend? }.flatten
    title = "Group subscription(#{lists.size}): "
    links_if_exists(title, lists, max) { |e|
      link_to(h(subscription_name(e)), link_entry_list(:room => e.id))
    }
  end

  def feed_subscribers
    return unless @feedinfo
    max = F2P::Config.max_friend_list_num
    map = @feedinfo.subscriptions.inject({}) { |r, e| r[e.id] = true; r }
    lists = @feedinfo.subscribers
    lists = lists.find_all { |e| !map.key?(e.id) }
    lists = lists.partition { |e| e.friend? }.flatten
    title = "Subscribers(#{lists.size}): "
    links_if_exists(title, lists, max) { |e|
      link_to(h(subscription_name(e)), link_entry_list(:user => e.id))
    }
  end

  def link_entry_action(action, opt = {})
    { :controller => 'entry', :action => action }.merge(opt)
  end

  def link_entry_list(opt = {})
    link_entry_action('list', opt)
  end

  def timezone_select_tag(varname, default)
    candidates = ActiveSupport::TimeZone.all.sort { |a, b|
      a.utc_offset <=> b.utc_offset
    }.map { |z|
      tz = z.utc_offset
      zone = of2tz(tz / 86400.0).sub('Z', '+00:00')
      name = "(#{zone}) " + z.name
      [name, z.name]
    }
    select_tag(varname, options_for_select(candidates, default))
  end

  def special_feed_links
    links = []
    links << link_to(h('Inbox'), { :controller => :entry, :action => :inbox }, accesskey('0'))
    links << link_to(h('You'), :controller => :entry, :action => :list, :user => 'me')
    feedid = 'filter/discussions'
    links << link_to(h('Discussions'), :controller => :entry, :action => :list, :feed => feedid)
    feedid = 'filter/direct'
    links << link_to(h('DM'), :controller => :entry, :action => :list, :feed => feedid)
    links << menu_link(menu_label('sign out'), :controller => 'login', :action => 'unlink_friendfeed')
    links.join(' ')
  end

  def twitter_links
    links = []
    base = {:controller => :entry, :action => :tweets, :id => @service_user}
    links << link_to(h('Home'), base.merge(:feed => :home))
    links << link_to(h('You'), base.merge(:feed => :user))
    label = h('Mentions')
    label = span(label, "inbox latest1") if @twitter_mentions_updated
    links << link_to(label, base.merge(:feed => :mentions))
    label = h('DM')
    label = span(label, "inbox latest1") if @twitter_direct_updated
    links << link_to(label, base.merge(:feed => :direct))
    links << link_to(h('Favorites'), base.merge(:feed => :favorites))
    links << link_to(h('following'), base.merge(:feed => :following, :max_id => -1))
    links << link_to(h('followers'), base.merge(:feed => :followers, :max_id => -1))
    sub = []
    sub << link_to(h('by friends'), base.merge(:feed => :retweeted_to_me))
    sub << link_to(h('by you'), base.merge(:feed => :retweeted_by_me))
    sub << link_to(h('yours'), base.merge(:feed => :retweets_of_me))
    links << 'RT(' + sub.join(' ') + ')'
    if @service_user
      links << menu_link(menu_label('sign out'), :controller => 'login', :action => 'unlink_twitter', :id => @service_user)
    end
    links.join(' ')
  end

  def buzz_links
    links = []
    base = {:controller => :entry, :action => :buzz, :id => @service_user}
    links << link_to(h('Home'), base.merge(:feed => :home))
    links << link_to(h('You'), base.merge(:feed => :user))
    links << link_to(h('Discussions'), base.merge(:feed => :discussions))
    links << link_to(h('following'), base.merge(:feed => :following))
    links << link_to(h('followers'), base.merge(:feed => :followers))
    if @service_user
      links << menu_link(menu_label('sign out'), :controller => 'login', :action => 'unlink_buzz', :id => @service_user)
    end
    links.join(' ')
  end

  def graph_links
    links = []
    base = {:controller => :entry, :action => :graph, :id => @service_user}
    links << link_to(h('Home'), base.merge(:feed => :home))
    links << link_to(h('You'), base.merge(:feed => :user))
    if @service_user
      links << menu_link(menu_label('sign out'), :controller => 'login', :action => 'unlink_facebook', :id => @service_user)
    end
    links.join(' ')
  end

  def delicious_links
    links = []
    base = {:controller => :entry, :action => :delicious, :id => @service_user}
    links << link_to(h('Home'), base.merge(:feed => :home))
    if @service_user
      links << menu_link(menu_label('sign out'), :controller => 'login', :action => 'unlink_delicious', :id => @service_user)
    end
    links.join(' ')
  end

  def tumblr_links
    links = []
    base = {:controller => :entry, :action => :tumblr}
    links << link_to(h('Home'), base.merge(:feed => :home))
    links << link_to(h('You'), base.merge(:feed => :user, :user => @service_user))
    if @service_user
      links << menu_link(menu_label('sign out'), :controller => 'login', :action => 'unlink_tumblr', :id => @service_user)
    end
    links.join(' ')
  end

  def list_links
    links = []
    if @feedlist
      links << link_to(h('Home'), :controller => 'entry', :action => 'list')
      lists = @feedlist['lists'] || []
      lists.each do |list|
        links << link_to(h(list.name), :controller => :entry, :action => :list, :feed => list.id)
      end
    end
    if @twitter_lists
      @twitter_lists.each do |list|
        links << link_to(h(list[:name]), :controller => :entry, :action => :tweets, :feed => list[:full_name])
      end
    end
    links.join(' ') unless links.empty?
  end

  def saved_search_links
    links = []
    if @feedlist
      lists = @feedlist['searches'] || []
      lists.each do |search|
        links << link_to(h(search.name), :controller => :entry, :action => :list, :feed => search.id)
      end
    end
    if @saved_searches
      base = {:controller => :entry, :action => :tweets, :id => @service_user}
      @saved_searches.each do |ss|
        links << link_to(h(ss[:name]), base.merge(:query => ss[:query]))
      end
    end
    links.join(' ') unless links.empty?
  end
end
