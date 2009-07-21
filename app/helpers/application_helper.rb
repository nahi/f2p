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
    'pin' => 'anchor.png',
    'bottom' => 'arrow_down.png',
    'top' => 'arrow_up.png',
    'map' => 'map.png',
    'help' => 'help.png',
    'group' => 'group.png',
    'private' => 'shield.png',
    'hide' => 'sound_mute.png',
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
    h2_size = setting ? setting.font_size : 10
    body_size = setting ? setting.font_size : 10
    content = <<__EOS__
  h1 { font-size: #{h1_size}pt; }
  h2 { font-size: #{h2_size}pt; }
  p.header { font-size: #{h1_size}pt; }
  body { font-size: #{body_size}pt; }
  a img { border: none; }
  p {
    margin-top: 1ex;
    margin-bottom: 1ex;
  }
  img { margin-right: 0.3ex; }
  img.inline  { vertical-align: text-top; }
  img.media   { border: 1px solid #ccc; padding: 1px; }
  img.profile { border: 1px solid #ccc; padding: 0px; }
  p.message { color: red; }
  .latest1 { color: #F00; }
  .latest2 { color: #C00; }
  .latest3 { color: #900; }
  .older { color: #008; }
  .comment { color: #666; }
  .comment-block {
    margin-bottom: 0.6ex;
  }
  .comment-block p { }
  .inbox { font-weight: bold; }
  div.listings .thread1 {
    background-color: #EEE;
    border-top: 1px solid #ccc;
    border-bottom: 1px solid #ccc;
    padding-top: 0.5ex;
    padding-bottom: 0.4ex;
  }
  div.listings .thread2 {
    padding-top: 0.5ex;
    padding-bottom: 0.4ex;
  }
  div.listings hr.separator { display: none; }
  div.listings ul {
    list-style-type: none;
    margin-top: 0pt;
    margin-bottom: 0pt;
  }
  div.listings p {
    margin-top: 0pt;
    margin-bottom: 0pt;
  }
  div.listings .entry {
    margin-bottom: 1.0ex;
  }
  div.listings .related {
    margin-bottom: 0.4ex;
  }
  div.listings .title-header {
    background-color: #EEE;
  }
  div.listings .title {
    padding-top: 1.5ex;
    padding-bottom: 1.0ex;
  }
  div.listings .single-entry {
    border-top: 1px solid #ccc;
    border-bottom: 1px solid #ccc;
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
    [
      write_new_link, 
      search_link, 
      settings_link, 
      help_link, 
      logout_link
    ].join
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
    image_tag(icon_url(:lock), :alt => h(label), :title => h(label), :size => '8x10')
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
    image_tag(url, :class => h('inline'), :alt => h(alt), :title => h(title), :size => '16x16')
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

  def entry_status(entry)
    if entry.from_id
      user_status(entry.from_id)
    else # imaginary user
      'private'
    end
  end

  def list_name(id)
    if @feedlist
      if found = @feedlist['lists'].find { |e| e.id == id }
        found.name
      end
    elsif @feedinfo
      if @feedinfo.id == id
        @feedinfo.name
      end
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

  def subscribe_status
    return unless @feedinfo
    if @feedinfo.commands.include?('unsubscribe')
      '(subscribed)'
    elsif @feedinfo.commands.include?('subscribe')
      '(not subscribed)'
    end
  end

  def feed_name
    return unless @feedinfo
    @feedinfo.name
  end

  def feed_description
    return unless @feedinfo
    @feedinfo.description
  end

  def feed_subscriptions_user
    return unless @feedinfo
    max = F2P::Config.max_friend_list_num
    if lists = @feedinfo.feeds || @feedinfo.subscriptions
      lists = lists.find_all { |e| e.user? }
      links_if_exists(lists.size.to_s + ' users: ', lists, max) { |e|
        label = "[#{e.name}]"
        link_to(h(label), link_entry_list(:user => e.id))
      }
    end
  end

  def feed_subscriptions_group
    return unless @feedinfo
    max = F2P::Config.max_friend_list_num
    if lists = @feedinfo.feeds || @feedinfo.subscriptions
      lists = lists.find_all { |e| e.group? }
      links_if_exists(lists.size.to_s + ' groups: ', lists, max) { |e|
        label = "[#{e.name}]"
        link_to(h(label), link_entry_list(:room => e.id))
      }
    end
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
end
