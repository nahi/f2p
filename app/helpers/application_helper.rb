# Methods added to this helper will be available to all templates in the application.

require 'time'


module ApplicationHelper
  APPNAME = 'f2p'
  DATE_THRESHOLD = (24 - 8).hours
  YEAR_THRESHOLD = 1.year
  SELF_LABEL = 'You'
  GWT_URL_BASE = 'http://www.google.com/gwt/n?u='

  def u(arg)
    if arg
      super(arg)
    end
  end

  def appname
    h(APPNAME)
  end

  def service_icon(service, link = nil)
    icon_url = v(service, 'iconUrl')
    name = v(service, 'name')
    link ||= v(service, 'profileUrl')
    if icon_url and name
      if link
        label = "profile on #{name}"
        link_to(image_tag(icon_url, :alt => h(name), :title => h(label)), link)
      else
        image_tag(icon_url, :alt => h(name), :title => h(name))
      end
    end
  end

  def room(room)
    link_to(h(room.name), :controller => 'entry', :action => 'list', :room => u(room.nickname))
  end

  def user_picture(user)
    user_id = v(user, 'id')
    nickname = v(user, 'nickname')
    name = v(user, 'name')
    if nickname == @auth.name
      name = SELF_LABEL
    end
    if nickname
      url = ff_client.get_picture_url(nickname, 'small')
      link_to(image_tag(url, :alt => h(name), :title => h(name), :size => image_size(25, 25)), :controller => 'entry', :action => 'list', :user => u(nickname || user_id))
    end
  end

  def user(user)
    user_id = v(user, 'id')
    nickname = v(user, 'nickname')
    name = v(user, 'name')
    if nickname == @auth.name
      name = SELF_LABEL
    end
    link_to(h(name), :controller => 'entry', :action => 'list', :user => u(nickname || user_id))
  end

  def via(via)
    name = v(via, 'name')
    link = v(via, 'url')
    if link
      %Q[via #{link_to(h(name), link)}</a>]
    elsif name
      %Q[via #{h(name)}]
    end
  end

  def image_size(width, height)
    "#{width}x#{height}"
  end

  def date(time, compact = true)
    return unless time
    unless time.is_a?(Time)
      time = Time.parse(time.to_s).localtime
    end
    elapsed = Time.now - time
    format = nil
    if !compact
      if elapsed > YEAR_THRESHOLD
        format = "[%y/%m/%d %H:%M]"
      else
        format = "[%m/%d %H:%M]"
      end
    else
      if elapsed > YEAR_THRESHOLD
        format = "%y/%m/%d"
      elsif elapsed > DATE_THRESHOLD
        format = "%m/%d"
      else
        format = "%H:%M"
      end
    end
    body = h(time.strftime(format))
    latest(time, body)
  end

  def latest(time, body)
    case elapsed(time)
    when (-1.hour)..(1.hour) # may have a time lag
      %Q[<span class="latest1">#{body}</span>]
    when 0..3.hour
      %Q[<span class="latest2">#{body}</span>]
    when 0..6.hour
      %Q[<span class="latest3">#{body}</span>]
    else
      %Q[<span class="older">#{body}</span>]
    end
  end

  def elapsed(time)
    if time
      Time.now - time
    end
  end

  # not enabled for now; need to be configurable to use this or not
  def link_to(markup, *rest)
    if rest.size == 1 and rest.first.is_a?(String)
      opt = {}
      opt[:target] = '_blank' if @setting.link_open_new_window
      if @setting.link_type == 'gwt'
        return super(markup, GWT_URL_BASE + u(rest.first), opt)
      else
        return super(markup, rest.first, opt)
      end
    end
    super
  end

  def link_url(url)
    link_to(h(url), url)
  end

  def q(str)
    h('"') + str + h('"')
  end

  def v(hash, *keywords)
    keywords.inject(hash) { |r, k|
      r[k] if r
    }
  end

  def fold_length(str, length)
    str.scan(Regexp.new("^.{0,#{length}}", Regexp::MULTILINE, 'u'))[0] || ''
  end

private

  def ff_client
    ApplicationController.ff_client
  end
end
