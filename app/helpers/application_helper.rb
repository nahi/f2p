# Methods added to this helper will be available to all templates in the application.

require 'time'


module ApplicationHelper
  APPNAME = 'f2p'
  DATE_THRESHOLD = (24 - 8).hours
  YEAR_THRESHOLD = 1.year - 2.days
  SELF_LABEL = 'You'
  GWT_URL_BASE = 'http://www.google.com/gwt/n?u='
  ICON_NAME = {
    'star' => 'star.png',
    #'star' => 'heart.png', # for special 2/14 configuration!
    'like' => 'thumb_up.png',
    'comment' => 'comment.png',
    'friend_comment' => 'user_comment.png',
    'comment_add' => 'comment_add.png',
    'comment_edit' => 'comment_edit.png',
    'delete' => 'delete.png',
    'more' => 'add.png',
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
    'pin' => 'anchor.png',
    'bottom' => 'arrow_down.png',
    'top' => 'arrow_up.png',
    'map' => 'map.png',
    'help' => 'help.png',
    'group' => 'group.png',
    'private' => 'shield.png',
  }

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
    h1_size = setting.font_size + 1
    h2_size = setting.font_size
    body_size = setting.font_size
    content = <<__EOS__
  h1 { font-size: #{h1_size}pt; }
  h2 { font-size: #{h2_size}pt; }
  body { font-size: #{body_size}pt; }
  a img { border: none; }
  img.media   { border: 1px solid #ccc; padding: 1px; }
  img.profile { border: 1px solid #ccc; padding: 0px; }
  p.message { color: red; }
  .latest1 { color: #F00; }
  .latest2 { color: #C00; }
  .latest3 { color: #900; }
  .older { color: #008; }
  .comment {
    padding-bottom: 0.5ex;
    color: #666;
  }
  .inbox { font-weight: bold; }
  div.listings .thread1 { padding-bottom: 0.8ex; background-color: #EEE; }
  div.listings .thread2 { padding-bottom: 0.8ex; }
  div.listings ul {
    list-style-type: none;
    margin-top: 0pt;
    margin-bottom: 0pt;
  }
  div.listings p {
    margin-top: 0pt;
    margin-bottom: 0pt;
  }
  div.listings .title {
    margin-top: 2ex;
    margin-bottom: 1.2ex;
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

  def top_menu
    write_new_link +
      search_link +
      settings_link +
      help_link +
      logout_link
  end

  def self_label
    SELF_LABEL
  end

  def timezone
    session[:timezone] || F2P::Config.timezone
  end

  def now
    @now ||= Time.now.in_time_zone(timezone)
  end

  def icon_url(name)
    icon_name = ICON_NAME[name.to_s]
    if icon_name and i_mode?
      icon_name = icon_name.sub(/.png\z/, '.gif')
    end
    F2P::Config.icon_url_base + (icon_name || name.to_s)
  end

  def icon_tag(name, alt = nil)
    name = name.to_s
    label = alt || name.gsub(/_/, ' ')
    image_tag(icon_url(name), :alt => h(label), :title => h(label), :size => '16x16')
  end

  def service_icon_tag(url, alt, title)
    if i_mode? and %r{([^/]*)\.png\b} =~ url
      url = icon_url($1 + '.gif')
    end
    image_tag(url, :alt => h(alt), :title => h(title), :size => '16x16')
  end

  def profile_image_tag(url, alt, title)
    image_tag(url, :class => h('profile'), :alt => h(alt), :title => h(title), :size => '25x25')
  end

  def write_new_link
    link_to(icon_tag(:write), :controller => 'entry', :action => 'new')
  end

  def search_link
    link_to(icon_tag(:search), :controller => 'entry', :action => 'search')
  end

  def settings_link
    link_to(icon_tag(:settings), :controller => 'setting', :action => 'index')
  end

  def logout_link
    link_to(icon_tag(:logout), :controller => 'login', :action => 'clear')
  end

  def help_link
    link_to(icon_tag(:help), :controller => 'help', :action => 'index')
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

  def user_profiles
    @user_profiles
  end

  def room_profiles
    @room_profiles
  end

  def list_profiles
    @list_profiles
  end

  def service_icon(service, link = nil)
    icon_url = service.icon_url
    name = service.name
    link ||= service.profile_url
    if service.icon_url and service.name
      if link
        label = "filter by #{name}"
        link_to(service_icon_tag(service.icon_url, name, label), link)
      else
        service_icon_tag(service.icon_url, name, name)
      end
    end
  end

  def room_icon(service, room, link = nil)
    if link
      label = "filter by #{room}"
    else
      label = room
    end
    if service.internal?
      icon = icon_tag(:group, label)
    else
      icon = service_icon_tag(service.icon_url, room, label)
    end
    link_to(icon, link)
  end

  def entry_status(entry)
    if entry.room
      room_status(entry.room.nickname)
    elsif entry.nickname
      user_status(entry.nickname)
    else # imaginary user
      'private'
    end
  end

  def list_name(nickname)
    if found = user_lists(auth.name).find { |e| e.nickname == nickname }
      found.name
    end
  end

  def room_profile(nickname)
    room_profiles[nickname] ||= Room.ff_profile(auth, nickname)
  end

  def room_name(nickname)
    room_profile(nickname)['name']
  end

  def room_status(nickname)
    @room_status ||= {}
    @room_status[nickname] ||= room_profile(nickname)['status']
  end

  def room_description(nickname)
    room_profile(nickname)['description']
  end

  def room_picture(nickname, size = 'small')
    name = nickname
    image_url = Room.ff_picture_url(nickname, size)
    profile_image_tag(image_url, name, name)
  end

  def room_picture_with_link(nickname, size = 'small')
    if image = room_picture(nickname, size)
      url = room_profile(nickname)['url']
      link_to(image, url)
    end
  end

  def room_status_icon(nickname)
    status_icon(room_status(nickname))
  end

  def room_members(nickname)
    room_profile(nickname)['members'] || []
  end

  def list_profile(nickname)
    list_profiles[nickname] ||= List.ff_profile(auth, nickname)
  end

  def list_rooms(nickname)
    list_profile(nickname)['rooms'] || []
  end

  def list_users(nickname)
    list_profile(nickname)['users'] || []
  end

  def imaginary?(nickname)
    /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/ =~ nickname
  end

  def user_profile(nickname)
    user_profiles[nickname] ||= User.ff_profile(auth, nickname)
  end

  def user_name(nickname)
    user_profile(nickname)['name']
  end

  def user_status(nickname)
    @user_status ||= {}
    @user_status[nickname] ||= user_profile(nickname)['status']
  end

  def user_picture(nickname, size = 'small')
    return if imaginary?(nickname)
    name = nickname
    if name == auth.name
      name = self_label
    end
    image_url = User.ff_picture_url(nickname, size)
    profile_image_tag(image_url, name, name)
  end

  def user_picture_with_link(nickname, size = 'small')
    if image = user_picture(nickname, size)
      url = user_profile(nickname)['profileUrl']
      link_to(image, url)
    end
  end

  def user_status_icon(nickname)
    status_icon(user_status(nickname))
  end

  def status_icon(status)
    if status != 'public'
      icon_tag(:private)
    end
  end

  def user_services(nickname)
    user_profile(nickname)['services'] || []
  end

  def user_rooms(nickname)
    user_profile(nickname)['rooms'] || []
  end

  def user_lists(nickname)
    user_profile(nickname)['lists'] || []
  end

  def user_subscriptions(nickname)
    user_profile(nickname)['subscriptions'] || []
  end

  def user(user)
    return unless user
    name = user.name
    if user.nickname == auth.name
      name = self_label
    end
    link_to(h(name), :controller => 'entry', :action => 'list', :user => u(user.nickname || user.id))
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
    if options.is_a?(String) and !url_for_app?(options)
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
    store = @controller.request.session[:checked]
    store[entry.id] = entry.modified
  end

  # TODO: should move to controller
  def commit_checked_modified(entry)
    if entry.view_inbox
      if store = @controller.request.session[:checked]
        store.delete(entry.id)
      end
      EntryThread.update_checked_modified(auth, entry.id => entry.modified)
    end
  end
end
