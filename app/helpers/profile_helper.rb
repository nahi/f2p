module ProfileHelper
  def viewname
    'profile'
  end

  def feed_service_links()
    return unless @feedinfo
    if services = @feedinfo.services
      map = services.inject({}) { |r, e|
        r[e.id] = e.name
        r
      }
      links_if_exists("#{map.size} services: ", map.to_a.sort_by { |k, v| k }) { |id, name|
        label = "[#{name}]"
        link_to(h(label), link_entry_action(:search, :q => 'service:' + id))
      }
    end
  end

  def feed_subscribers()
    return unless @feedinfo
    max = F2P::Config.max_friend_list_num
    if lists = @feedinfo.subscribers
      links_if_exists(lists.size.to_s + ' subscribers: ', lists, max) { |e|
        label = "[#{e.name}]"
        link_to(h(label), link_entry_list(:user => e.id))
      }
    end
  end

  def user_page_links
    links = []
    links << menu_link(menu_label(feed_name), link_entry_list(:user => @id))
    feedid = [@id, 'likes'].join('/')
    links << menu_link(menu_label('Likes'), link_entry_list(:feed => feedid))
    links << menu_link(menu_label('Liked'), link_entry_list(:like => 'liked', :user => @id))
    feedid = [@id, 'friends'].join('/')
    links << menu_link(menu_label('With friends'), link_entry_list(:feed => feedid))
    links.join(' ')
  end
end
