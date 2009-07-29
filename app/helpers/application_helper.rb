# Methods added to this helper will be available to all templates in the application.

require 'time'
require 'xsd/datatypes'


module ApplicationHelper
  include XSD::XSDDateTimeImpl

  APPNAME = 'f2p'
  DATE_THRESHOLD = (24 - 8).hours
  YEAR_THRESHOLD = 1.year - 2.days
  SELF_LABEL = 'You'
  GWT_URL_BASE = 'http://www.google.com/gwt/n?u='
  ICON_NAME = {
    'star' => 'star.png',
    'mini_star' => 'bullet_star.png',
    #'star' => 'heart.png', # for special 2/14 configuration!
    'like' => 'thumb_up.png',
    'comment' => 'comment.png',
    #'friend_comment' => 'user_comment.png',
    'friend_comment' => 'comment.png',
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
    'media_disabled' => 'image_link.png',
    'pinned' => 'tick.png',
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

  def jpmobile?
    @controller.request.respond_to?(:mobile)
  end

  def cell_phone?
    jpmobile? and @controller.request.mobile?
  end

  def i_mode?
    jpmobile? and @controller.request.mobile.is_a?(Jpmobile::Mobile::Docomo)
  end

  def iphone?
    /(iPhone|iPod)/ =~ @controller.request.user_agent
  end

  def accesskey(key)
    @accesskey ||= {}
    key = key.to_s
    key = nil if @accesskey.key?(key)
    @accesskey[key] = true
    {:accesskey => key}
  end

  def inline_meta
    if iphone?
      content_tag('meta', nil, :name => 'viewport', :content => 'width=device-width; initial-scale=1.0')
    else
      content_tag('meta', nil, :name => 'viewport', :content => 'width=device-width, height=device-height')
    end
  end

  def inline_stylesheet
    return if i_mode?
    h1_size = setting ? setting.font_size + 1 : 11
    body_size = setting ? setting.font_size : 10
    content = <<__EOS__
  p.header { font-size: #{h1_size}pt; }
  body { font-size: #{body_size}pt; }
  img.inline  { vertical-align: text-top; }
  img.media   { border: 1px solid #ccc; padding: 1px; }
  img.profile { border: 1px solid #ccc; padding: 0px; }
  a img { border: none; }
  p {
    margin-top: 1ex;
    margin-bottom: 1ex;
  }
  p.message { color: red; }
  .latest1 { color: #F00; }
  .latest2 { color: #C00; }
  .latest3 { color: #900; }
  .older { color: #008; }
  .comment { color: #666; }
  .inbox { font-weight: bold; }
  .body,.comment-body,.likes {
    text-indent: -16px;
    margin-left: 16px;
  }
  .comment-body {
    margin-bottom: 0.5ex;
  }
  .related {
    margin-top: 1.5ex;
  }
  div.listings .thread1 {
    background-color: #EEE;
    border-top: 1px solid #ccc;
    border-bottom: 1px solid #ccc;
    padding-top: 0.5ex;
    padding-bottom: 1.0ex;
  }
  div.listings .thread2 {
    padding-top: 0.5ex;
    padding-bottom: 1.0ex;
  }
  div.listings hr.separator { display: none; }
  div.listings .body {
    padding-bottom: 0.5ex;
  }
  div.listings .entry {
    margin-bottom: 0.8ex;
  }
  div.single {
    border-top: 1px solid #ccc;
    border-bottom: 1px solid #ccc;
  }
  div.single .header {
    background-color: #EEE;
  }
  div.single .body {
    padding-top: 1ex;
    padding-bottom: 1ex;
  }
  div.single .entry-menu {
    margin-bottom: 1ex;
  }
  #{ inline_stylesheet_iphone }
__EOS__
    content_tag('style', content, :type => "text/css")
  end

  def inline_stylesheet_iphone
    if iphone?
      <<__EOS__
  body {
    -webkit-user-select: none;
    -webkit-text-size-adjust: none;
  }
__EOS__
    end
  end

  def oauth_image_tag
    label = 'OAuth'
    link_to(image_tag(icon_url('sign-in-with-friendfeed.gif'), :alt => h(label), :title => h(label)), :controller => :login, :action => :initiate_oauth_login)
  end

  def top_menu
    menu = menu_link(menu_icon(:bottom, '8') + h('menu'), '#bottom', accesskey('8'))
    if auth and auth.oauth?
      icon_tag(:shield) + ' ' + menu
    else
      menu
    end
  end

  def common_menu(*arg)
    [
      write_new_link,
      search_link,
      settings_link,
      help_link,
      logout_link,
      to_top_menu
    ].join(' ')
  end

  def to_top_menu
    menu_link(menu_icon(:top, '2'), '#top', accesskey('2'))
  end

  def self_label
    SELF_LABEL
  end

  def timezone
    if setting
      setting.timezone ||= F2P::Config.timezone
    else
      F2P::Config.timezone
    end
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
    image_tag(url, :alt => h(alt), :title => h(title), :size => '16x16')
  end

  def profile_link(id)
    link_to(menu_label('profile'), :controller => :profile, :action => :show, :id => id)
  end

  def profile_image_tag(url, alt, title)
    image_tag(url, :class => h('profile'), :alt => h(alt), :title => h(title), :size => '25x25')
  end

  def inbox_link
    menu_link(menu_label('inbox', '0'), { :controller => :entry, :action => :inbox }, accesskey('0'))
  end

  def all_link
    name = feed_name || 'Home feed'
    menu_link(menu_label('show all entries in ' + name, '7'), { :controller => :entry, :action => :list }, accesskey('7'))
  end

  def pinned_link
    menu_link(menu_label('pin', '9'), { :controller => :entry, :action => :list, :label => 'pin' }, accesskey('9'))
  end

  def write_new_link
    link_to(menu_label('post'), :controller => 'entry', :action => 'new')
  end

  def search_link
    link_to(menu_label('search'), :controller => 'entry', :action => 'search')
  end

  def settings_link
    link_to(menu_label('settings'), :controller => 'setting', :action => 'index')
  end

  def logout_link
    link_to(menu_label('logout'), :controller => 'login', :action => 'clear')
  end

  def help_link
    link_to(menu_label('help'), :controller => 'help', :action => 'index')
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

  def entry_status(entry)
    if entry.from_id
      user_status(entry.from_id)
    else # imaginary user
      'private'
    end
  end

  def imaginary?(id)
    /\A[0-9a-f]{32}\z/ =~ id
  end

  def picture(id, size = 'small')
    return if imaginary?(id)
    name = id
    if name == auth.name
      name = self_label
    end
    image_url = User.ff_picture_url(id, size)
    profile_image_tag(image_url, name, name)
  end

  def user(user)
    return unless user
    name = user.name
    if user.id == auth.name
      name = self_label
    end
    link_to(h(name), :controller => 'entry', :action => 'list', :user => u(user.id))
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
    content_tag('span', h(body), :class => klass)
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

  def link_to(name, options = {}, html_options = {})
    if setting and options.is_a?(String) and !url_for_app?(options)
      if setting.link_open_new_window
        html_options = html_options.merge(:target => '_blank')
      end
      if setting.link_type == 'gwt'
        return super(name, GWT_URL_BASE + u(options), html_options)
      else
        return super(name, options, html_options)
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

  # TODO: should move to controller
  def remember_checked(entry)
    if ctx.inbox or ctx.home
      store = @controller.request.session[:checked]
      store[entry.id] = entry.modified
    end
  end

  # TODO: should move to controller
  def commit_checked_modified(entry)
    if entry.view_unread
      if store = @controller.request.session[:checked]
        store.delete(entry.id)
      end
      EntryThread.update_checked_modified(auth, entry.id => entry.modified)
    end
  end

  def links_if_exists(label, enum, max = nil, &block)
    if max and enum.size > max + 1
      ary = enum[0, max].collect { |v| yield(v) }
      ary << "... #{enum.size - max} more"
    else
      ary = enum.collect { |v| yield(v) }
    end
    str = ary.join(' ')
    str = h(label) + str unless str.empty?
    str
  end

  def menu_link(label, opt, html_opt = {}, &block)
    if block.nil? or block.call
      link_to(label, opt, html_opt)
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

  def feed_description
    return unless @feedinfo
    @feedinfo.description
  end

  def feed_subscriptions_user
    return unless @feedinfo
    max = F2P::Config.max_friend_list_num
    lists = @feedinfo.feeds + @feedinfo.subscriptions
    lists = lists.find_all { |e| e.user? }
    if lists.size == 1
      title = '1 user: '
    else
      title = lists.size.to_s + ' users: '
    end
    links_if_exists(title, lists, max) { |e|
      label = "[#{e.name}]"
      link_to(h(label), link_entry_list(:user => e.id))
    }
  end

  def feed_subscriptions_group
    return unless @feedinfo
    max = F2P::Config.max_friend_list_num
    lists = @feedinfo.feeds + @feedinfo.subscriptions
    lists = lists.find_all { |e| e.group? }
    if lists.size == 1
      title = '1 group: '
    else
      title = lists.size.to_s + ' groups: '
    end
    links_if_exists(title, lists, max) { |e|
      label = "[#{e.name}]"
      link_to(h(label), link_entry_list(:room => e.id))
    }
  end

  def link_entry_action(action, opt = {})
    { :controller => 'entry', :action => action }.merge(opt)
  end

  def link_entry_list(opt = {})
    link_entry_action('list', opt)
  end

  def timezone_select_tag(varname, default)
    candidates = ActiveSupport::TimeZone::ZONES.sort { |a, b|
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
    links << menu_link(menu_label('Profile'), :controller => :profile, :action => :show, :id => auth.name)
    links << menu_link(menu_label('Inbox', '0'), { :controller => :entry, :action => :inbox }, accesskey('0'))
    links << menu_link(menu_label('My feed'), :controller => :entry, :action => :list, :user => auth.name)
    feedid = 'filter/direct'
    links << menu_link(menu_label('Direct messages'), :controller => :entry, :action => :list, :feed => feedid)
    feedid = 'filter/discussions'
    links << menu_link(menu_label('My discussions'), :controller => :entry, :action => :list, :feed => feedid)
    feedid = [auth.name, 'likes'].join('/')
    feedid = 'notifications/desktop'
    links << menu_link(menu_label('Notifications'), :controller => :entry, :action => :list, :feed => feedid)
    links.join(' ')
  end

  def list_links
    return unless @feedlist
    links = []
    links << menu_link(menu_label('Home'), link_list)
    lists = @feedlist['lists'] || []
    lists.each do |list|
      links << menu_link(menu_label(list.name), :controller => :entry, :action => :list, :feed => list.id)
    end
    links.join(' ')
  end

  def saved_search_links
    return unless @feedlist
    links = []
    lists = @feedlist['searches'] || []
    lists.each do |search|
      links << menu_link(menu_label(search.name), :controller => :entry, :action => :list, :feed => search.id)
    end
    links.join(' ')
  end
end
