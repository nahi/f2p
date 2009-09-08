module ProfileHelper
  def viewname
    'profile'
  end

  def dm_link
    return unless @feedinfo
    if @feedinfo.commands.include?('dm') and @feedinfo.id != auth.name
      link_to(h('Send direct message'), :controller => :entry, :action => :new, :to_lines => 1, :to_0 => @id, :cc => '')
    end
  end

  def feed_service_links()
    return unless @feedinfo
    if services = @feedinfo.services
      map = services.inject({}) { |r, e|
        r[e.id] = e.name
        r
      }
      title = "Services(#{map.size}): "
      links_if_exists(title, map.to_a.sort_by { |k, v| k }) { |id, name|
        link_to(h(name), link_entry_action(:list, :user => @feedinfo.id, :query => nil, :service => id))
      }
    end
  end

  def user_page_links
    links = []
    links << link_to(h(feed_name), link_entry_list(:user => @id))
    feedid = [@id, 'likes'].join('/')
    links << link_to(h('Likes'), link_entry_list(:feed => feedid))
    links << link_to(h('Liked'), link_entry_list(:like => 'liked', :user => @id))
    feedid = [@id, 'friends'].join('/')
    links << link_to(h('With friends'), link_entry_list(:feed => feedid))
    if auth.name == @id
      feedid = 'notifications/desktop'
      links << link_to(h('Notifications'), :controller => :entry, :action => :list, :feed => feedid)
    end
    links.join(' ')
  end
end
