# Methods added to this helper will be available to all templates in the application.

require 'time'


module ApplicationHelper
  APPNAME = 'ffp'
  DATE_THRESHOLD = 24 - 8

  def appname
    h(APPNAME)
  end

  def service_icon(service)
    icon_url = v(service, 'iconUrl')
    name = v(service, 'name')
    profile_url = v(service, 'profileUrl')
    if icon_url and name
      if profile_url
        link_to(image_tag(icon_url, :alt => h("profile on #{name}")), profile_url)
      else
        image_tag(icon_url, :alt => h(name))
      end
    end
  end

  def room(room)
    name = v(room, 'name')
    nickname = v(room, 'nickname')
    if name and nickname
      link_to(h(name), :controller => 'entry', :action => 'list', :room => u(nickname))
    end
  end

  def user(user)
    nickname = v(user, 'nickname')
    name = v(user, 'name')
    if name
      if nickname
        link_to(h(name), :controller => 'entry', :action => 'list', :user => u(nickname))
      else
        h(name)
      end
    end
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
    if !compact
      body = h(time.strftime("%Y/%m/%d %H:%M:%S"))
    elsif Time.now - time < DATE_THRESHOLD.hour
      body = h(time.strftime("%H:%M"))
    else
      body = h(time.strftime("%m/%d"))
    end
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
      body
    end
  end

  def elapsed(time)
    if time
      Time.now - time
    end
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
end
