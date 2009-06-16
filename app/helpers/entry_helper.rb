module EntryHelper
  BRIGHTKITE_MAP_ZOOM = 12
  BRIGHTKITE_MAP_WIDTH = 120
  BRIGHTKITE_MAP_HEIGHT = 80

  def viewname
    if ctx.service
      viewname_base + "(#{ctx.service})"
    else
      viewname_base
    end
  end

  def viewname_base
    return ctx.viewname if ctx.viewname
    if ctx.eid
      'entry'
    elsif ctx.query
      'search results'
    elsif ctx.like == 'likes'
      "entries #{user_name(ctx.user || auth.name)} likes"
    elsif ctx.like == 'liked'
      "#{user_name(ctx.user || auth.name)}'s liked entries"
    elsif ctx.comment == 'discussion'
      "#{user_name(ctx.user || auth.name)}'s discussion"
    elsif ctx.user
      "#{user_name(ctx.user || auth.name)}"
    elsif ctx.friends
      "#{user_name(ctx.user || auth.name)} with friends"
    elsif ctx.list
      "'#{list_name(ctx.list)}' entries"
    elsif ctx.room
      if ctx.room == '*'
        'groups'
      else
        "#{room_name(ctx.room_for)}"
      end
    elsif ctx.link
      'related entries'
    elsif ctx.label == 'pin'
      'pinned'
    elsif ctx.inbox
      'inbox'
    else
      'archived'
    end
  end

  def ctx
    @ctx
  end

  def cache_profile(entries)
    users = [auth.name]
    rooms = []
    # TODO: do not show status icon for query result page now for performance
    # reason.
    if ctx.query.nil? and ctx.link.nil?
      entries.each do |t|
        t.entries.each do |e|
          if e.room
            rooms << e.room.nickname
            else
            users << e.nickname if e.nickname
          end
        end
      end
    end
    @user_status = User.ff_status_map(auth, users.uniq)
    @room_status = Room.ff_status_map(auth, rooms.uniq)
  end

  def link_action(action, opt = {})
    { :controller => 'entry', :action => action }.merge(opt)
  end

  def link_list(opt = {})
    link_action('list', opt)
  end

  def link_show(id, opt = {})
    link_action('show', opt.merge(:id => u(id)))
  end

  def link_user(user, opt = {})
    link_list(opt.merge(:user => user))
  end

  def author_picture(entry)
    return if !ctx.single? and !setting.list_view_profile_picture
    return if ctx.user_for or ctx.room_for
    if nickname = entry.origin_nickname
      if nickname == entry.nickname
        user_picture(entry.nickname)
      else
        room_picture(entry.room.nickname)
      end
    end
  end

  def pin_link(entry)
    if entry.view_pinned
      link_to(icon_tag(:pinned, 'unpin'), link_action('unpin', :id => entry.id))
    else
      link_to(icon_tag(:pin), link_action('pin', :id => entry.id))
    end
  end

  def icon(entry)
    service = entry.service
    return unless service
    if ctx.user
      user = entry.nickname || entry.user_id
    end
    room_entry = (entry.room and entry.room.nickname != ctx.room_for)
    if room_entry
      opt = { :room => u(entry.room.nickname) }
      user = nil
    elsif entry.room
      opt = { :room => u(entry.room.nickname), :service => u(service.id) }
    else
      opt = { :service => u(service.id) }
    end
    opt[:label] = ctx.label
    link = link_user(user, opt)
    if room_entry
      str = room_icon(service, entry.room.nickname, link)
    else
      str = service_icon(service, link)
    end
    # TODO: do not show status icon for query result page now for performance
    # reason.
    if ctx.query.nil? and ctx.link.nil? and !ctx.user_for
      if entry_status(entry) != 'public'
        str = icon_tag(:private) + str
      end
    end
    str
  end

  def icon_extra(entry)
    room_entry = (entry.room and entry.room.nickname != ctx.room_for)
    str = nil
    if room_entry
      str = entry.room.name
    end
    if entry.service.service_group?
      str = entry.service.name
    end
    if str
      h("(#{str})")
    end
  end

  def media_disabled?
    ctx.list? and !setting.list_view_media_rendering
  end

  def media_tag(entry, url, opt = {})
    if entry and media_disabled?
      link_to(icon_tag(:media_disabled), link_show(entry.id))
    else
      image_tag(url, opt.merge(:class => h('media')))
    end
  end

  def content(entry)
    common = common_content(entry)
    return common unless entry.service
    if entry.service.twitter?
      twitter_content(common, entry)
    elsif entry.service.tumblr?
      tumblr_content(common, entry)
    elsif entry.service.stumbleupon?
      stumbleupon_content(common, entry)
    else
      common
    end
  end

  def common_content(entry)
    title = entry.title
    return unless title
    if entry.link and with_link?(entry.service)
      content = link_content(title, entry)
    else
      fold, str, links = escape_text(title, ctx.fold ? setting.text_folding_size : nil)
      entry.view_links = links
      if fold
        str += link_to(inline_icon_tag(:more), link_show(entry.id))
      end
      content = q(str)
    end
    if !entry.medias.empty?
      # entries from Hatena contains 'enclosure' but no title and link for now.
      with_media = content_with_media(entry)
      content += media_indent + with_media unless with_media.empty?
    end
    if entry.geo and !entry.view_map
      point = GoogleMaps::Point.new(title, entry.geo.lat, entry.geo.long)
      zoom = F2P::Config.google_maps_zoom
      width = F2P::Config.google_maps_width
      height = F2P::Config.google_maps_height
      if entry.service.brightkite?
        if !entry.medias.empty?
          zoom = BRIGHTKITE_MAP_ZOOM
          width = BRIGHTKITE_MAP_WIDTH
          height = BRIGHTKITE_MAP_HEIGHT
        end
      end
      content += ' ' + google_maps_link(point, entry, zoom, width, height)
    end
    content
  end

  def media_indent
    "<br />\n&nbsp;&nbsp;&nbsp;"
  end

  def friend_of(entry)
    if friend_of = entry.friend_of
      if entry.comments.find { |c| c.nickname == friend_of.nickname }
        h(" (through #{friend_of.name})")
      elsif entry.likes.find { |l| l.nickname == friend_of.nickname }
        h(" (through #{friend_of.name})")
      end
    end
  end

  def author_link(entry)
    if !entry.anonymous and !ctx.user_only?
      (user(entry) || '') + (friend_of(entry) || '')
    end
  end

  def comment_author_link(comment)
    unless comment.posted_with_entry?
      h('by ') + user(comment)
    end
  end

  def emphasize_as_unread?(entry_or_comment)
    (ctx.home or ctx.inbox or ctx.label) and entry_or_comment.view_unread
  end

  def original_link(entry)
    return unless ctx.single?
    # no need to show original link for link only content.
    if entry.link and !with_link?(entry.service)
      if unknown_where_to_go?(entry)
        link_content = icon_tag(:go) + h("(#{uri_domain(entry.link)})")
      else
        link_content = icon_tag(:go)
      end
      entry_link_to(link_content, entry.link)
    end
  end

  def link_content(title, entry)
    if ctx.single?
      icon = icon_tag(:go)
    else
      icon = ''
    end
    if unknown_where_to_go?(entry)
      entry_link_to(icon + h(title), entry.link) + h(" (#{uri_domain(entry.link)})")
    else
      entry_link_to(icon + h(title), entry.link)
    end
  end

  def link_content_without_link(title, entry)
    q(h(title))
  end

  def entry_link_to(name, options = {}, html_options = {})
    @already_linked ||= false
    unless @already_linked
      @already_linked = true
      html_options = html_options.merge(:id => 'first_link')
    end
    link_to(name, options, html_options)
  end

  def uri(str)
    begin
      uri = URI.parse(str)
      uri = nil if uri.host.nil?
      uri
    rescue
      nil
    end
  end

  def uri_domain(str)
    uri = uri(str)
    if uri
      uri.host
    else
      str
    end
  end

  def unknown_where_to_go?(entry)
    link_url = uri(entry.link)
    profile_url = uri(entry.service.profile_url)
    if profile_url and link_url
      (profile_url.host.downcase != link_url.host.downcase)
    else
      entry.service.service_group? or entry.service.tumblr?
    end
  end

  def with_link?(service)
    service and service.entry_type != 'message' and !service.twitter?
  end

  def content_with_media(entry)
    medias = entry.medias
    if ctx.single?
      display = medias
    else
      display = medias[0, F2P::Config.medias_in_thread]
    end
    str = display.collect { |media|
      title = media.title
      if direct_image_link?(entry, media)
        link = extract_first_media_link(media)
      else
        link = media.link
      end
      tbs = media.thumbnails
      safe_content = nil
      if tbs and tbs.first
        tb = tbs.first
        tb_url = tb.url
        tb_width = tb.width
        tb_height = tb.height
        if tb_url
          label = title || entry.title
          safe_content = media_tag(entry, tb_url, :alt => h(label), :title => h(label), :size => image_size(tb_width, tb_height))
        end
      elsif title
        safe_content = h(title)
      end
      if safe_content
        if !media_disabled? and link
          link_to(safe_content, link)
        else
          safe_content
        end
      end
    }.join(' ')
    if medias.size != display.size
      msg = " (#{medias.size - display.size} more images)"
      str += link_to(icon_tag(:more), link_show(entry.id)) + h(msg)
    end
    str
  end

  def direct_image_link?(entry, media)
    if entry.service.internal?
      if c = media.contents.first
        if tb = media.thumbnails.first
          if tb.width == c.width and tb.height == c.height
            return false
          end
        end
      end
      true
    else
      false
    end
  end

  def extract_first_media_link(media)
    if c = media.contents.first
      link = c.url
    end
    if media.enclosures.first
      link ||= media.enclosures.first['url']
    end
    link ||= media.link
    link
  end

  def google_maps_link(point, entry, zoom = F2P::Config.google_maps_zoom, width = F2P::Config.google_maps_width, height = F2P::Config.google_maps_height)
    generator = GoogleMaps::URLGenerator.new(F2P::Config.google_maps_api_key)
    lat = point.lat
    long = point.long
    address = point.address
    tb = generator.staticmap_url(F2P::Config.google_maps_maptype, lat, long, :zoom => zoom, :width => width, :height => height)
    link = generator.link_url(lat, long, address)
    content = media_tag(entry, tb, :alt => h(address), :title => h(address), :size => image_size(width, height))
    if media_disabled?
      content
    else
      link_to(content, link)
    end
  end

  def google_maps_markers_link(entries)
    generator = GoogleMaps::URLGenerator.new(F2P::Config.google_maps_api_key)
    markers = entries.map { |e|
      [e.geo.lat, e.geo.long]
    }
    tb = generator.staticmap_markers_url(F2P::Config.google_maps_maptype, markers, :width => F2P::Config.google_maps_width, :height => F2P::Config.google_maps_height)
    ids = entries.sort { |a, b|
      a.published_at <=> b.published_at
    }.map { |e| e.id }.join(',')
    if media_disabled?
      content = h('[filter geo entries]')
    else
      content = media_tag(nil, tb, :size => image_size(F2P::Config.google_maps_width, F2P::Config.google_maps_height))
    end
    link_to(content, link_list(:ids => ids))
  end

  def twitter_content(common, entry)
    str = common.gsub(/@([a-zA-Z0-9_]+)/) {
      '@' + link_to($1, "http://twitter.com/#{$1}")
    }
    if link = entry.view_links.find { |e| /\btwitpic.com\b/ =~ e }
      if uri = uri(link)
        uri.path = "/show/mini#{uri.path}"
        str += media_indent + media_tag(entry, uri.to_s)
      end
    end
    if link = entry.view_links.find { |e| /\bmovapic.com\/pic\/([a-z0-9]+)/ =~ e }
      str += media_indent + media_tag(entry, "http://image.movapic.com/pic/t_#{$1}.jpeg")
    end
    str
  end

  def tumblr_content(common, entry)
    title = entry.title
    fold = fold_length(title, setting.text_folding_size - 3)
    if ctx.fold and entry.medias.empty? and fold != title
      link_content(fold + '...', entry) + link_to(inline_icon_tag(:more), link_show(entry.id))
    else
      common
    end
  end

  def stumbleupon_content(common, entry)
    if entry.medias.empty?
      common
    else
      str = entry.medias.collect { |media|
        link = media.link
        if media.enclosures.first
          url = media.enclosures.first['url']
          label = entry.title
          safe_content = media_tag(entry, url, :alt => h(label), :title => h(label))
        end
        if safe_content
          if !media_disabled? and link
            link_to(safe_content, link)
          else
            safe_content
          end
        end
      }.join(' ')
      common + media_indent + str
    end
  end

  def escape_text(content, fold_size = nil)
    str = ''
    fold_size ||= content.length
    org_size = 0
    m = nil
    links = []
    while content.match(URI.regexp(['http', 'https']))
      m = $~
      added, part = fold_concat(m.pre_match, fold_size - org_size)
      str += h(part)
      if added
        org_size += added
      else
        return true, str, links
      end
      target = m[0]
      content = m.post_match
      if target[-1] == ?)
        target[-1, 1] = ''
        content = ')' + content
      end
      uri = uri(target)
      added, part = fold_concat(target, fold_size - org_size)
      if uri.nil? or !uri.is_a?(URI::HTTP)
        str += h(part)
        if added
          org_size += added
        else
          return true, str, links
        end
      else
        links << target
        if added
          str += link_to(h(target), target)
          org_size += added
        else
          str += link_to(h(part), target)
          return true, str, links
        end
      end
    end
    added, part = fold_concat(content, fold_size - org_size)
    str += h(part)
    unless added
      return true, str, links
    end
    return false, str, links
  end

  def fold_concat(str, fold_size)
    return 0, str if str.empty?
    size = str.scan(/./u).size
    if size > fold_size
      return nil, fold_length(str, fold_size - 3) + '...'
    else
      return size, str
    end
  end

  def via(entry_or_comment)
    label = entry_or_comment.respond_to?(:service) ? 'from' : 'via'
    super(entry_or_comment.via, label)
  end

  def likes(entry)
    me = []
    friends = []
    rest = []
    subscriptions = user_subscriptions(auth.name).inject({}) { |r, e| r[e.nickname] = true; r }
    entry.likes.each do |e|
      if e.nickname == auth.name
        me << e
      elsif subscriptions.key?(e.nickname)
        friends << e
      else
        rest << e
      end
    end
    likes = me + friends + rest
    if !likes.empty?
      if liked?(entry)
        icon = link_to(icon_tag(:star, 'unlike'), link_action('unlike', :id => u(entry.id)))
      else
        icon = icon_tag(:star)
      end
      icon += h(likes.size.to_s)
      max = F2P::Config.max_friend_list_num
      if likes.size > max + 1
        msg = "... #{likes.size - max} more likes"
        members = likes[0, max].collect { |like| user(like) }.join(' ') + ' ' + h(msg)
      else
        members = likes.collect { |like| user(like) }.join(' ')
      end
      icon + '(' + members + ')'
    end
  end

  def friends_likes(entry)
    subscriptions = user_subscriptions(auth.name).inject({}) { |r, e| r[e.nickname] = true; r }
    likes = entry.likes.find_all { |e| subscriptions.key?(e.nickname) }
    if !entry.likes.empty?
      if liked?(entry)
        icon = link_to(icon_tag(:star, 'unlike'), link_action('unlike', :id => u(entry.id)))
      else
        icon = icon_tag(:star)
      end
      if entry.likes.size != likes.size
        icon += link_to(h(entry.likes.size.to_s), link_show(entry.id))
      else
        icon += h(entry.likes.size.to_s)
      end
      if !likes.empty?
        members = likes.collect { |like| user(like) }.join(' ')
        icon += '(' + members + ')'
      end
      icon
    end
  end

  def comments(entry, compact)
    unless entry.comments.empty?
      link_to(icon_tag(:comment) + h(entry.comments.size.to_s), link_show(entry.id))
    end
  end

  def updated(entry, compact)
    date(entry.modified, compact)
  end

  def emphasize_as_unread(str)
    content_tag('span', str, :class => 'inbox')
  end

  def published(entry, compact = false)
    str = date(entry.published_at, compact)
    if emphasize_as_unread?(entry)
      str = emphasize_as_unread(str)
    end
    str
  end

  def modified_if(entry, compact)
    if compact
      pub = published(entry, compact)
      mod = date(entry.modified, compact)
      if pub != mod
        "(#{mod} up)"
      end
    end
  end

  def user(entry_or_comment)
    unless entry_or_comment.respond_to?(:service)
      return super(entry_or_comment.user)
    end
    entry = entry_or_comment
    if setting.twitter_comment_hack and entry.service.twitter?
      if nickname = entry.nickname
        name = entry.user.name
        tw_name = entry.twitter_username
        if name != tw_name
          if nickname == auth.name
            name = self_label
          end
          name += "(#{tw_name})"
          return link_to(h(name), link_user(nickname))
        end
      end
    end
    super(entry.user)
  end

  def comment_icon(comment = nil)
    if comment
      by_self = comment.by_user(auth.name)
      label = "##{comment.index}"
    else
      by_self = true
      label = nil
    end
    by_self ? icon_tag(:comment, label) : icon_tag(:friend_comment, label)
  end

  def comment(comment)
    fold, str, links = escape_text(comment.body, ctx.fold ? setting.text_folding_size : nil)
    comment.view_links = links
    if fold
      str += link_to(inline_icon_tag(:more), link_show(comment.entry.id))
    end
    str
  end

  def inline_comment(comment)
    if comment.posted_with_entry?
      comment(comment)
    else
      comment(comment) + ' ' + comment_date(comment, true)
    end
  end

  def search_form(opt = {})
    str = ''
    str += hidden_field_tag('user', ctx.user) if ctx.user
    str += hidden_field_tag('list', ctx.list) if ctx.list
    str += hidden_field_tag('room', ctx.room_for) if ctx.room_for
    str += hidden_field_tag('friends', ctx.friends) if ctx.friends
    str += hidden_field_tag('service', ctx.service) if ctx.service
    if str.empty?
      str += hidden_field_tag('friends', 'me')
    end
    if opt[:compact]
      str += text_field_tag('query', ctx.query, :size => 6, :placeholder => 'search')
    else
      str += text_field_tag('query', ctx.query, :placeholder => 'search') + submit_tag('search')
    end
    str
  end

  def search_drilldown_links
    opt = search_opt
    links = []
    likes = opt[:likes].to_i + 1
    links << menu_link(h("[likes >= #{likes}]"), opt.merge(:likes => likes))
    comments = opt[:comments].to_i + 1
    links << menu_link(h("[comments >= #{comments}]"), opt.merge(:comments => comments))
    mine_opt = opt.merge(:user => 'me')
    mine_opt.delete(:friends)
    links << menu_link(h('[mine]'), mine_opt) {
      opt[:user] != 'me'
    }
    links << menu_link(h('[FriendFeed entry]'), opt.merge(:service => 'internal')) {
      opt[:service] != 'internal'
    }
    h('drill down on: ') + links.join(' ')
  end

  def geo_markers_link(threads)
    found = []
    threads.each do |t|
      t.entries.each do |e|
        found << e if e.geo
      end
    end
    if found.size > 1
      google_maps_markers_link(found[0, 26])
    end
  end

  def post_entry_form
    str = ''
    str += hidden_field_tag('room', ctx.room_for) + h(room_name(ctx.room_for)) + ': ' if ctx.room_for
    str += text_field_tag('body', nil, :placeholder => 'post') + submit_tag('post')
    str
  end

  def post_comment_form(entry)
    if setting.twitter_comment_hack and entry.service.twitter? and user_status(entry.user_id) == 'public'
      default = entry.twitter_username
      unless default.empty?
        default = "@#{default} "
      end
    end
    text_field_tag('body', default, :placeholder => 'comment') + submit_tag('post')
  end

  def edit_comment_form(comment)
    default = comment.body
    text_field_tag('body', default) + submit_tag('post')
  end

  def fold_link(entry)
    msg = " (#{entry.fold_entries} related entries)"
    link_to(icon_tag(:more), list_opt(ctx.link_opt(:start => ctx.start, :num => ctx.num, :fold => 'no'))) + h(msg)
  end

  def fold_comment_link(fold)
    msg = " (#{fold.fold_entries} more comments)"
    link_to(icon_tag(:more), link_show(fold.entry_id)) + h(msg)
  end

  def write_new_link
    link_to(icon_tag(:write), link_action('new', :room => u(ctx.room_for)))
  end

  def search_link
    link_to(icon_tag(:search), search_opt(link_action('search')))
  end

  def service_links(user)
    services = user_services(user)
    map = services.inject({}) { |r, e|
      r[e.id] = e.name
      r
    }
    links_if_exists("#{map.size} services: ", map.to_a.sort_by { |k, v| k }) { |id, name|
      label = "[#{name}]"
      if ctx.service == id
        h(label)
      else
        link_to(h(label), list_opt(link_user(user, :service => u(id))))
      end
    }
  end

  def list_links
    lists = user_lists(auth.name)
    links_if_exists('Lists: ', lists) { |e|
      label = "[#{e.name}]"
      if ctx.list == e.nickname
        h(label)
      else
        link_to(h(label), link_list(:list => u(e.nickname)))
      end
    }
  end

  def zoom_select_tag(varname, default)
    candidates = (0..19).map { |e| [e, e] }
    select_tag(varname, options_for_select(candidates, default))
  end

  def room_select_tag(varname, default)
    user = auth.name
    rooms = user_rooms(user)
    candidates = rooms.map { |e| [e.name, e.nickname] }
    candidates.unshift([nil, nil])
    select_tag(varname, options_for_select(candidates, default))
  end

  def likes_select_tag(varname, default)
    candidates = [1, 2, 3, 4, 5, 10].map { |e| [e, e] }
    candidates.unshift([nil, nil])
    select_tag(varname, options_for_select(candidates, default))
  end

  def room_links(user)
    rooms = user_rooms(user)
    links_if_exists('Groups: ', rooms) { |e|
      label = "[#{e.name}]"
      if e.nickname == ctx.room_for and !ctx.service and !ctx.label
        h(label)
      else
        link_to(h(label), link_list(:room => u(e.nickname)))
      end
    }
  end

  def user_links(user)
    max = F2P::Config.max_friend_list_num
    users = user_subscriptions(user)
    users = users.find_all { |e| e.nickname and e.nickname != auth.name }
    links_if_exists("#{users.size} subscriptions: ", users, max) { |e|
      label = "[#{e.name}]"
      link_to(h(label), link_user(e.nickname))
    }
  end

  def imaginary_user_links(user)
    max = F2P::Config.max_friend_list_num
    users = user_subscriptions(user)
    users = users.find_all { |e| !e.nickname }
    links_if_exists("#{users.size} imaginary friends: ", users, max) { |e|
      label = "<#{e.name}>"
      link_to(h(label), link_user(e.id))
    }
  end

  def member_links(room)
    max = F2P::Config.max_friend_list_num
    members = room_members(room)
    me, rest = members.partition { |e| e.nickname == auth.name }
    members = me + rest
    links_if_exists("(#{members.size} members) ", members, max) { |e|
      label = "[#{e.name}]"
      if e.nickname
        link_to(h(label), link_user(e.nickname))
      end
    }
  end

  def list_user_links(list)
    max = F2P::Config.max_friend_list_num
    users = list_users(list)
    links_if_exists("(#{users.size} users) ", users, max) { |e|
      label = "[#{e.name}]"
      if e.nickname
        link_to(h(label), link_user(e.nickname))
      end
    }
  end

  def list_room_links(list)
    rooms = list_rooms(list)
    links_if_exists("(#{rooms.size} groups) ", rooms) { |e|
      label = "[#{e.name}]"
      if e.nickname == ctx.room_for and !ctx.service and !ctx.label
        h(label)
      else
        link_to(h(label), link_list(:room => u(e.nickname)))
      end
    }
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

  def page_links(opt = {})
    no_page = ctx.start.nil?
    start = ctx.start || 0
    num = ctx.num || 0
    links = []
    if opt[:for_top]
      links << menu_link(menu_icon(:bottom, '8'), '#bottom', accesskey('8'))
    end
    if opt[:for_bottom]
      links << menu_link(menu_icon(:top, '2'), '#top', accesskey('2'))
    end
    if ctx.list?
      links << menu_link(menu_label('<', '4', true), list_opt(ctx.link_opt(:start => start - num, :num => num, :direction => 'rewind')), accesskey('4')) {
        !no_page and start - num >= 0
      }
    end
    links << menu_link(menu_label('inbox', '0'), link_action('inbox'), accesskey('0'))
    if ctx.list? and threads = opt[:threads]
      if entry = find_show_entry(threads)
        links << menu_link(menu_label('next', '1'), link_show(entry.id), accesskey('1'))
      end
    end
    pin_label = 'pin'
    if threads = opt[:threads]
      if threads.pins and threads.pins > 0
        pin_label += "(#{threads.pins})"
      end
    end
    links << menu_link(menu_label(pin_label, '9'), link_list(:label => u('pin')), accesskey('9'))
    if ctx.list?
      links << menu_link(menu_label('>', '6'), list_opt(ctx.link_opt(:start => start + num, :num => num)), accesskey('6')) { !no_page }
      if threads = opt[:threads] and opt[:for_top]
        links << list_range_notation(threads)
      end
    end
    if ctx.inbox and opt[:for_bottom]
      links << archive_button
      links << menu_link(menu_label('all', '7'), link_list(), accesskey('7'))
    end
    links.join(' ')
  end

  def find_show_entry(threads)
    if thread = threads.first
      thread.root
    end
  end

  def list_range_notation(threads)
    if threads.from_modified and threads.to_modified
      from = ago(threads.from_modified)
      if ctx.start == 0
        h("(#{from} ago ~ now)")
      else
        to = ago(threads.to_modified)
        if from == to
          h("(#{from} ago)")
        else
          h("(#{from} ~ #{to} ago)")
        end
      end
    end
  end

  def next_entry(eid)
    return if @original_threads.nil? or @original_threads.empty?
    entries = @original_threads.map { |thread| thread.entries }.flatten
    if found = entries.find { |e| e.id == eid }
      if found.view_nextid
        entries.find { |e| e.id == found.view_nextid }
      end
    end
  end

  def link_to_next_entry(entry)
    title = entry.title || ''
    fold = fold_length(title, F2P::Config.next_entry_text_folding_size - 3)
    if title != fold
      fold += '...'
    end
    content = h(fold)
    link_to(content, link_show(entry.id), accesskey('5'))
  end

  def archive_button
    label = 'mark as read'
    label = '5.' + label if cell_phone?
    submit_tag(label, accesskey('5'))
  end

  def user_page_links(user)
    return if imaginary?(user)
    name = user_name(user)
    return unless name
    links = []
    links << menu_link(menu_label(user == auth.name ? 'me' : 'self'), link_user(user)) {
      !ctx.user_only?
    }
    links << menu_link(menu_label('discussion'), link_list(:comment => 'discussion', :user => ctx.user_for)) {
      user != ctx.user_for or ctx.comment != 'discussion'
    }
    links << menu_link(menu_label('likes'), link_list(:like => 'likes', :user => ctx.user_for)) {
      user != ctx.user_for or ctx.like != 'likes'
    }
    links << menu_link(menu_label('liked'), link_list(:like => 'liked', :user => ctx.user_for)) {
      user != ctx.user_for or ctx.like != 'liked'
    }
    links << menu_link(menu_label('with friends'), link_list(:friends => user)) {
      user != ctx.user_for or !ctx.friends
    }
    h(name + "'s: ") + links.join(' ')
  end

  def menu_icon(icon, accesskey = nil, reverse = false)
    "[#{label_with_accesskey(inline_icon_tag(icon), accesskey, reverse)}]"
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

  def menu_link(label, opt, html_opt = {}, &block)
    if block.nil? or block.call
      link_to(label, opt, html_opt)
    else
      label
    end
  end

  def post_comment_link(entry, opt = {})
    str = inline_icon_tag(:comment_add, 'comment')
    if opt[:show_comments_number] and !entry.comments.empty? and !comment_inline?(entry)
      if entry.comments.size == 1
        num = "(#{entry.comments.size} comment)"
      else
        num = "(#{entry.comments.size} comments)"
      end
      num = latest(entry.modified_at, num)
      if emphasize_as_unread?(entry)
        num = emphasize_as_unread(num)
      end
      str += num
    end
    link_to(str, link_show(entry.id))
  end

  def url_link(entry)
    return unless ctx.single?
    link = entry.link if with_link?(entry.service)
    link ||= entry.view_links ? entry.view_links.first : nil
    # separate search and link.
    #if entry.title.size < setting.text_folding_size
    #  query = entry.title
    #end
    if link
      url_link_to(link)
    end
  end

  def comment_date(comment, compact = true)
    str = date(comment.date, compact)
    if emphasize_as_unread?(comment)
      str = emphasize_as_unread(str)
    end
    str
  end

  def comment_url_link(comment)
    if ctx.single? and comment.view_links
      url_link_to(comment.view_links.first)
    end
  end

  def url_link_to(link, query = nil)
    if link and ctx.link != link
      link_to(inline_icon_tag(:url, 'related'), link_list(:link => link, :query => query))
    end
  end

  def delete_link(entry)
    if entry.nickname == auth.name
      link_to(inline_icon_tag(:delete), link_action('delete', :id => u(entry.id)), :confirm => 'Delete?')
    end
  end

  def undo_delete_link(id, comment)
    link_to(h('Deleted.  UNDO?'), link_action('undelete', :id => u(id), :comment => u(comment)))
  end

  def undo_add_link(id)
    link_to(h('Added.  UNDO?'), link_action('delete', :id => u(id)))
  end

  def undo_add_comment_link(id, comment)
    link_to(h('Added.  UNDO?'), link_action('delete', :id => u(id), :comment => u(comment)))
  end

  def edit_comment_link(comment)
    if comment.nickname == auth.name
      link_to(inline_icon_tag(:comment_edit, 'edit'), link_action('edit', :id => u(comment.entry.id), :comment => u(comment.id)))
    end
  end

  def delete_comment_link(comment)
    if comment.nickname == auth.name or auth.name == comment.entry.nickname
      link_to(inline_icon_tag(:delete), link_action('delete', :id => u(comment.entry.id), :comment => u(comment.id)), :confirm => 'Delete?')
    end
  end

  def like_link(entry)
    if entry.nickname != auth.name or (entry.room and !entry.service.internal?)
      unless liked?(entry)
        link_to(inline_icon_tag(:like), link_action('like', :id => u(entry.id)))
      end
    end
  end

  def hide_link(entry)
    link_to(inline_icon_tag(:hide), link_action('hide', :id => u(entry.id)), :confirm => 'Hide?')
  end

  def reshare_link(entry)
    if (ctx.single? or entry.view_pinned) and
        (entry.nickname != auth.name or entry.room) and
        entry.link
      link_to(inline_icon_tag(:reshare), link_action('reshare', :eid => u(entry.id)))
    end
  end

  def liked?(entry)
    entry.likes.find { |like| like.nickname == auth.name }
  end

  def list_opt(hash = {})
    ctx.list_opt.merge(hash)
  end

  def search_opt(hash = {})
    search_opt = list_opt(hash)
    search_opt[:friends] = 'me' if ctx.home or ctx.inbox or ctx.label
    search_opt[:room] = nil if search_opt[:room] == '*'
    search_opt[:num] = ctx.num if ctx.num != @setting.entries_in_page
    search_opt
  end

  class Fold < Hash
    attr_reader :entry_id
    attr_reader :fold_entries

    def initialize(entry_id, fold_entries)
      super()
      @entry_id = entry_id
      @fold_entries = fold_entries
    end
  end

  def fold_entries(entries)
    if !entries.empty? and ctx.fold
      fold_items(entries.first.id, entries)
    else
      entries.dup
    end
  end

  def fold_comments(comments)
    if !comments.empty? and ctx.fold
      fold_items(comments.first.entry.id, comments)
    else
      comments.dup
    end
  end

  def fold_items(entry_id, items)
    return [] if setting.entries_in_thread == 0
    if items.size > setting.entries_in_thread + 1
      head_size = setting.entries_in_thread > 1 ? 1 : 0
      last_size = setting.entries_in_thread - head_size
      result = items[0, head_size]
      result << Fold.new(entry_id, items.size - (head_size + last_size))
      result += items[-last_size, last_size]
      result
    else
      items.dup
    end
  end

  def fold_item?(entry)
    entry and entry.respond_to?(:fold_entries)
  end

  def comment_inline?(entry)
    ctx.list? and entry.self_comment_only?
  end

  def gps_link(*arg)
    if jpmobile?
      str = get_position_link_to(*arg)
      str = nil if str.empty?
      str
    end
  end
end
