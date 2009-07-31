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
        link_to(h(name), link_entry_action(:search, :q => 'service:' + id))
      }
    end
  end

  def feed_subscribers
    return unless @feedinfo
    max = F2P::Config.max_friend_list_num
    if lists = @feedinfo.subscribers
      map = @feedinfo.subscriptions.inject({}) { |r, e| r[e.id] = true; r }
      lists = lists.partition { |e| map.key?(e.id) }.flatten
      title = "Subscribers(#{lists.size}): "
      links_if_exists(title, lists, max) { |e|
        if map.key?(e.id)
          label = '*' + e.name
        else
          label = e.name
        end
        link_to(h(label), link_entry_list(:user => e.id))
      }
    end
  end

  def user_page_links
    links = []
    links << menu_link(h(feed_name), link_entry_list(:user => @id))
    feedid = [@id, 'likes'].join('/')
    links << menu_link(h('Likes'), link_entry_list(:feed => feedid))
    links << menu_link(h('Liked'), link_entry_list(:like => 'liked', :user => @id))
    feedid = [@id, 'friends'].join('/')
    links << menu_link(h('With friends'), link_entry_list(:feed => feedid))
    links.join(' ')
  end
end
