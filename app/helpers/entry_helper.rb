module EntryHelper
  BRIGHTKITE_MAP_ZOOM = 12
  BRIGHTKITE_MAP_WIDTH = 120
  BRIGHTKITE_MAP_HEIGHT = 80

  def top_menu
    if ctx.list?
      super
    else
      [
        write_new_link, 
        search_link 
      ].join
    end
  end

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
    elsif ctx.like == 'liked'
      "#{feed_name}'s liked entries"
    elsif ctx.user
      feed_name
    elsif ctx.feed
      feed_name
    elsif ctx.room
      feed_name
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

  def link_action(action, opt = {})
    { :controller => 'entry', :action => action }.merge(opt)
  end

  def link_list(opt = {})
    link_action('list', opt)
  end

  def link_show(id, opt = {})
    link_action('show', opt.merge(:eid => id))
  end

  def link_user(user, opt = {})
    link_list(opt.merge(:user => user))
  end

  def link_feed(feedid, opt = {})
    link_list(opt.merge(:feed => feedid))
  end

  def author_picture(entry)
    return if !setting.list_view_profile_picture
    if id = entry.origin_id
      unless imaginary?(id)
        picture(entry.from_id)
      end
    end
  end

  def pin_link(entry)
    if entry.view_pinned
      link_to(icon_tag(:pinned, 'unpin'), link_action('unpin', :eid => entry.id))
    else
      link_to(icon_tag(:pin), link_action('pin', :eid => entry.id))
    end
  end

  def to(entry)
    links = entry.to.map { |to|
      if to.group?
        opt = { :room => to.id }
        link = link_list(opt)
        (icon(to) || '') + link_to(h(to.name), link)
      elsif to.id != entry.from_id
        (icon(to) || '') + h(to.name)
      end
    }.compact
    unless links.empty?
      'to ' + links.join(', ')
    end
  end

  def icon(from)
    if from.private
      lock_icon_tag
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
    content = common_content(entry)
    if entry.via and entry.via.twitter?
      content = twitter_content(content, entry)
    end
    scan_media_from_link(entry)
    unless entry.view_medias.empty?
      content += media_indent
      entry.view_medias.each do |uri|
        content += media_tag(entry, uri)
      end
    end
    content
  end

  def common_content(entry)
    body = entry.body
    return '' unless body
    if link_entry?(entry)
      content = link_content(body, entry)
    else
      fold, str, links = escape_text(body, ctx.fold ? setting.text_folding_size : nil)
      entry.view_links = links
      if fold
        msg = '(more)'
        str += link_to(h(msg), link_show(entry.id))
      end
      content = str
    end
    if !entry.files.empty?
      content += entry.files.map { |file|
        label = file.type
        icon = image_tag(file.icon, :alt => h(label), :title => h(label), :size => '16x16')
        str = media_indent + link_to(icon + h(file.name), file.url)
        str += h(" (#{file.size} bytes)") if file.size
        str
      }.join(', ')
    end
    if !entry.thumbnails.empty?
      # entries from Hatena contains 'enclosure' but no title and link for now.
      with_media = content_with_media(entry)
      content += media_indent + with_media unless with_media.empty?
    end
    if entry.geo and !entry.view_map
      point = GoogleMaps::Point.new(body, entry.geo.lat, entry.geo.long)
      zoom = F2P::Config.google_maps_zoom
      width = F2P::Config.google_maps_width
      height = F2P::Config.google_maps_height
      if entry.via and entry.via.brightkite?
        if !entry.thumbnails.empty?
          zoom = BRIGHTKITE_MAP_ZOOM
          width = BRIGHTKITE_MAP_WIDTH
          height = BRIGHTKITE_MAP_HEIGHT
        end
      end
      content += ' ' + google_maps_link(point, entry, zoom, width, height)
    end
    content
  end

  def link_entry?(entry)
    entry.link and !(ctx.list? and entry.via and entry.via.twitter?)
  end

  def scan_media_from_link(entry)
    if entry.view_links and entry.view_medias.empty?
      entry.view_links.each do |link|
        case link
        # http://twitpic.com/api.do#thumbnails
        when /\btwitpic.com\b/
          if uri = uri(link)
            uri.path = "/show/mini#{uri.path}"
            entry.view_medias << uri.to_s
          end
        # via gotoken
        when /\bmovapic.com\/pic\/([a-z0-9]+)/
          uri = "http://image.movapic.com/pic/t_#{$1}.jpeg"
          entry.view_medias << uri
        # http://code.google.com/p/imageshackapi/wiki/YFROGthumbnails
        when /\byfrog.com\b/
          uri = link + '.th.jpg'
          entry.view_medias << uri
        # http://pic.im/website/api
        when /\bpic.im\b/
          if uri = uri(link)
            uri.path = "/website/thumbnail#{uri.path}"
            entry.view_medias << uri.to_s
          end
        # http://pix.im/api#thumbnails
        when /\bpix.im\b/
          uri = link + '/thumbnail'
          entry.view_medias << uri
        end
      end
    end
  end

  def media_indent
    "<br />\n&nbsp;&nbsp;&nbsp;"
  end

  def friend_of(entry)
    if fof = entry.friend_of
      h(" (through #{fof.name})")
    end
  end

  def author_link(entry)
    (icon(entry.from) || '') + (user(entry) || '') + (friend_of(entry) || '')
  end

  def service_icon(entry)
    if via = entry.via
      if via.service_icon_url
        link_to(service_icon_tag(via.service_icon_url, via.name, via.name),
                search_opt(:action => :list, :query => '', :service => via.service_id))
      end
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
    link = entry.url
    link_content = "See original (#{uri_domain(link)})"
    entry_link_to(h(link_content), link)
  end

  def link_content(body, entry)
    link = entry.link
    h(body) + ' ' + entry_link_to(h("(#{uri_domain(link)})"), link)
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

  def content_with_media(entry)
    medias = entry.thumbnails
    if ctx.single?
      display = medias
    else
      display = medias[0, F2P::Config.medias_in_thread]
    end
    str = display.collect { |tb|
      link = tb.link
      label = entry.body
      size = image_size(tb.width, tb.height) if tb.width and tb.height
      safe_content = media_tag(entry, tb.url, :alt => h(label), :title => h(label), :size => size)
      if !media_disabled? and link
        link_to(safe_content, link)
      else
        safe_content
      end
    }.join(' ')
    if medias.size != display.size
      msg = " (#{medias.size - display.size} more images)"
      str += link_to(msg, link_show(entry.id))
    end
    str
  end

  def select_thumbnail(tbs)
    if /movapic/ =~ tbs.first.url
      if tb = tbs.find { |e| /t_/ =~ e.url }
        return tb
      end
    end
    if tb = tbs.find_all { |e| e.height }.min_by { |e| e.height }
      return tb
    end
    if ctx.single? or !cell_phone?
      tbs.first
    end
  end

  def find_image_from_enclosure(encs)
    if encs
      if ctx.single? or !cell_phone?
        if enc = encs.find { |e| e['url'] and /\Aimage/i =~ e['type'] }
          return enc['url']
        end
      end
    end
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
      a.date_at <=> b.date_at
    }.map { |e| e.id }.join(',')
    if media_disabled?
      content = h('[filter geo entries]')
    else
      content = media_tag(nil, tb, :size => image_size(F2P::Config.google_maps_width, F2P::Config.google_maps_height))
    end
    link_to(content, link_list(:eids => ids))
  end

  def twitter_content(common, entry)
    common.gsub(/@([a-zA-Z0-9_]+)/) {
      '@' + link_to($1, "http://twitter.com/#{$1}")
    }
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
    label = entry_or_comment.respond_to?(:comments) ? 'from' : 'via'
    super(entry_or_comment.via, label)
  end

  def likes(entry)
    me = []
    friends = []
    rest = []
    entry.likes.each do |e|
      if e.from_id == auth.name
        me << e
      elsif !e.from.commands.include?('subscribe')
        friends << e
      else
        rest << e
      end
    end
    likes = me + friends + rest
    if !likes.empty?
      if liked?(entry)
        icon = link_to(icon_tag(:star, 'unlike'), link_action('unlike', :eid => entry.id))
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
    likes = entry.likes.find_all { |e| !e.from.commands.include?('subscribe') }
    if !entry.likes.empty?
      if liked?(entry)
        icon = link_to(icon_tag(:star, 'unlike'), link_action('unlike', :eid => entry.id))
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
    str = date(entry.date_at, compact)
    if emphasize_as_unread?(entry)
      str = emphasize_as_unread(str)
    end
    str
    #if compact
    #  link_to(str, link_show(entry.id))
    #else
    #  str
    #end
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
      return super(entry_or_comment.from)
    end
    entry = entry_or_comment
    if setting.twitter_comment_hack and entry.service.twitter?
      if id = entry.from_id
        name = entry.user.name
        tw_name = entry.twitter_username
        if name != tw_name
          if id == auth.name
            name = self_label
          end
          name += "(#{tw_name})"
          return link_to(h(name), link_user(id))
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
    opt = { :class => 'comment-icon' }
    by_self ? icon_tag(:comment, label, opt) : icon_tag(:friend_comment, label, opt)
  end

  def comment(comment)
    fold, str, links = escape_text(comment.body, ctx.fold ? setting.text_folding_size : nil)
    comment.view_links = links
    if fold
      msg = '(more)'
      str += link_to(h(msg), link_show(comment.entry.id))
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
    str += hidden_field_tag('room', ctx.room_for) if ctx.room_for
    str += hidden_field_tag('friends', ctx.friends) if ctx.friends
    str += hidden_field_tag('service', ctx.service) if ctx.service
    if str.empty? and ctx.query.nil?
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
    unless ctx.direct_message?
      str = ''
      str += hidden_field_tag('to_lines', '1')
      if ctx.room_for and @feedinfo.commands.include?('post')
        str += hidden_field_tag('to_0', ctx.room_for) + h(feed_name) + ': '
      end
      str += text_field_tag('body', nil, :placeholder => 'post') + submit_tag('post')
      str
    end
  end

  def post_comment_form(entry)
    if entry.commands.include?('comment')
      if entry.via and setting.twitter_comment_hack and entry.via.twitter?
        default = entry.twitter_username
        unless default.empty?
          default = "@#{default} "
        end
      end
      text_field_tag('body', default, :placeholder => 'comment') + submit_tag('post')
    else
      h('(comment disabled)')
    end
  end

  def edit_entry_form(entry)
    if entry.commands.include?('edit')
      default = entry.body
      text_field_tag('body', default) + submit_tag('post')
    end
  end

  def edit_comment_form(comment)
    default = comment.body
    text_field_tag('body', default) + submit_tag('post')
  end

  def fold_link(entry)
    msg = "(#{entry.fold_entries} related entries)"
    link_to(msg, list_opt(ctx.link_opt(:start => ctx.start, :num => ctx.num, :fold => 'no')))
  end

  def fold_comment_link(fold)
    msg = "(#{fold.fold_entries} more comments)"
    link_to(msg, link_show(fold.entry_id))
  end

  def write_new_link
    link_to(icon_tag(:write), link_action('new', :room => ctx.room_for))
  end

  def search_link
    link_to(icon_tag(:search), search_opt(link_action('search')))
  end

  def list_links
    return unless @feedlist
    links = []
    @feedlist['lists'].each do |list|
      links << menu_link(menu_label(list.name), link_feed(list.id)) {
        @ctx.feed != list.id
      }
    end
    links.join(' ')
  end

  def saved_search_links
    return unless @feedlist
    links = []
    @feedlist['searches'].each do |search|
      links << menu_link(menu_label(search.name), link_feed(search.id)) {
        @ctx.feed != search.id
      }
    end
    links.join(' ')
  end

  def zoom_select_tag(varname, default)
    candidates = (0..19).map { |e| [e, e] }
    select_tag(varname, options_for_select(candidates, default))
  end

  def to_select_tag(varname, default)
    user = auth.name
    candidates = @feedinfo.subscriptions.find_all { |e| e.group? and e.commands.include?('post') }.map { |e| ['(group) ' + e.name, e.id] }
    candidates += @feedinfo.subscribers.find_all { |e| e.user? and e.commands.include?('dm') }.map { |e| ['(direct) ' + e.name, e.id] }
    candidates.unshift([nil, nil])
    select_tag(varname, options_for_select(candidates, default))
  end

  def group_select_tag(varname, default)
    user = auth.name
    feeds = @feedinfo.subscriptions.find_all { |e| e.group? }
    candidates = feeds.map { |e| [e.name, e.id] }
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
      if e.id == ctx.room_for and !ctx.service and !ctx.label
        h(label)
      else
        link_to(h(label), link_list(:room => e.id))
      end
    }
  end

  def user_links(user)
    max = F2P::Config.max_friend_list_num
    users = user_subscriptions(user)
    users = users.find_all { |e| e.id != auth.name }
    links_if_exists("#{users.size} subscriptions: ", users, max) { |e|
      label = "[#{e.name}]"
      link_to(h(label), link_user(e.id))
    }
  end

  def imaginary_user_links(user)
    max = F2P::Config.max_friend_list_num
    users = user_subscriptions(user)
    links_if_exists("#{users.size} imaginary friends: ", users, max) { |e|
      label = "<#{e.name}>"
      link_to(h(label), link_user(e.id))
    }
  end

  def member_links(room)
    max = F2P::Config.max_friend_list_num
    members = room_members(room)
    me, rest = members.partition { |e| e.id == auth.name }
    members = me + rest
    links_if_exists("(#{members.size} members) ", members, max) { |e|
      label = "[#{e.name}]"
      if e.id
        link_to(h(label), link_user(e.id))
      end
    }
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
    if ctx.inbox
      links << menu_link(menu_label('all', '7'), link_list(), accesskey('7'))
    end
    pin_label = 'pin'
    if threads = opt[:threads]
      if threads.pins and threads.pins > 0
        pin_label += "(#{threads.pins})"
      end
    end
    links << menu_link(menu_label(pin_label, '9'), link_list(:label => 'pin'), accesskey('9'))
    if ctx.list?
      links << menu_link(menu_label('>', '6'), list_opt(ctx.link_opt(:start => start + num, :num => num)), accesskey('6')) { !no_page }
      if threads = opt[:threads] and opt[:for_top]
        links << list_range_notation(threads)
      end
    end
    if ctx.inbox and opt[:for_bottom]
      links << archive_button
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

  def next_entry(entry)
    return if entry.nil? or @original_threads.nil? or @original_threads.empty?
    entries = @original_threads.map { |thread| thread.entries }.flatten
    if found = entries.find { |e| e.id == entry.id }
      if found.view_nextid
        entries.find { |e| e.id == found.view_nextid }
      end
    end
  end

  def link_to_next_entry(entry)
    title = entry.body || ''
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

  def user_page_links
    links = []
    links << menu_link(menu_label('My feed'), link_user(auth.name)) {
      ctx.user_for != auth.name
    }
    feedid = 'filter/direct'
    links << menu_link(menu_label('Direct msg'), link_feed(feedid)) {
      ctx.feed != feedid
    }
    feedid = 'filter/discussions'
    links << menu_link(menu_label('My discussions'), link_feed(feedid)) {
      ctx.feed != feedid
    }
    feedid = 'summary/1'
    links << menu_link(menu_label('Best of a day'), link_feed(feedid)) {
      ctx.feed != feedid
    }
    feedid = [auth.name, 'likes'].join('/')
    links << menu_link(menu_label('Likes'), link_feed(feedid)) {
      ctx.feed != feedid
    }
    links << menu_link(menu_label('Liked'), link_list(:like => 'liked', :user => auth.name)) {
      ctx.user_for != auth.name or ctx.like != 'liked'
    }
    feedid = [auth.name, 'friends'].join('/')
    links << menu_link(menu_label('With friends'), link_feed(feedid)) {
      ctx.feed != feedid
    }
    links.join(' ')
  end

  def best_of_list_links(listid)
    listid = listid.split('/')[0, 2].join('/')
    links = []
    feedid = [listid, 'summary/1'].join('/')
    links << menu_link(menu_label('a day'), link_feed(feedid)) {
      ctx.feed != feedid
    }
    feedid = [listid, 'summary/3'].join('/')
    links << menu_link(menu_label('3 days'), link_feed(feedid)) {
      ctx.feed != feedid
    }
    feedid = [listid, 'summary/7'].join('/')
    links << menu_link(menu_label('7 days'), link_feed(feedid)) {
      ctx.feed != feedid
    }
    feedid = listid
    links << menu_link(menu_label('all'), link_feed(feedid)) {
      ctx.feed != feedid
    }
    links.join(' ')
  end

  def menu_icon(icon, accesskey = nil, reverse = false)
    label_with_accesskey(inline_icon_tag(icon), accesskey, reverse)
  end

  def comment_link(comment)
    if comment.last?
      if comment.entry.commands.include?('comment')
        label = inline_icon_tag(:comment_add)
      else
        label = h('show')
      end
      link_to(label, link_show(comment.entry.id))
    end
  end

  def post_comment_link(entry, opt = {})
    if !entry.comments.empty? and !comment_inline?(entry)
      if entry.comments.size == 1
        str = "#{entry.comments.size} comment"
      else
        str = "#{entry.comments.size} comments"
      end
      str = latest(entry.modified_at, str)
      if emphasize_as_unread?(entry)
        str = emphasize_as_unread(str)
      end
    elsif entry.commands.include?('comment')
      str = inline_icon_tag(:comment_add)
    else
      str = h('show')
    end
    link_to(str, link_show(entry.id))
  end

  def url_link(entry)
    return unless ctx.single?
    link = entry.link
    link ||= entry.view_links ? entry.view_links.first : nil
    if link
      url_link_to(link)
    end
  end

  def comment_date(comment, compact = true)
    str = date(comment.date, compact)
    if emphasize_as_unread?(comment)
      str = emphasize_as_unread(str)
    end
    #if compact and comment.last?
    #  link_to(str, link_show(comment.entry.id))
    #else
    #  str
    #end
    str
  end

  def comment_url_link(comment)
    if ctx.single? and comment.view_links
      url_link_to(comment.view_links.first)
    end
  end

  def url_link_to(link, query = nil)
    if link and ctx.link != link
      link_to(inline_menu_label(:url, 'Search link'), link_list(:link => link, :query => query))
    end
  end

  def delete_link(entry)
    if entry.commands.include?('delete')
      link_to(inline_menu_label(:delete, 'Delete'), link_action('delete', :eid => entry.id), :confirm => 'Delete?')
    end
  end

  def undo_delete_link(id, comment)
    link_to(h('Deleted.  UNDO?'), link_action('undelete', :eid => id, :comment => comment))
  end

  def undo_add_link(id)
    link_to(h('Added.  UNDO?'), link_action('delete', :eid => id))
  end

  def undo_add_comment_link(id, comment)
    link_to(h('Added.  UNDO?'), link_action('delete', :eid => id, :comment => comment))
  end

  def moderate_link(entry)
    if !ctx.moderate and editable?(entry)
      link_to(inline_menu_label(:comment_edit, 'Edit'),
              link_action('show', :eid => entry.id, :moderate => true))
    end
  end

  def editable?(entry)
    entry.commands.include?('edit') or
      entry.comments.any? { |c| c.commands.include?('edit') or c.commands.include?('delete') }
  end

  def edit_comment_link(comment)
    if ctx.moderate
      if comment.commands.include?('edit')
        link_to(inline_icon_tag(:comment_edit, 'edit'), link_action('show', :eid => comment.entry.id, :comment => comment.id))
      end
    end
  end

  def delete_comment_link(comment)
    if ctx.moderate
      if comment.commands.include?('delete')
        link_to(inline_icon_tag(:delete), link_action('delete', :eid => comment.entry.id, :comment => comment.id), :confirm => 'Delete?')
      end
    end
  end

  def inline_menu_label(icon, label = nil)
    if ctx.single?
      label || icon.to_s
    else
      inline_icon_tag(icon, label)
    end
  end

  def like_link(entry)
    if entry.commands.include?('like')
      link_to(inline_menu_label(:like, 'Like'),
              link_action('like', :eid => entry.id))
    end
  end

  def hide_link(entry)
    if entry.commands.include?('hide')
      link_to(inline_menu_label(:hide, 'Hide'),
              link_action('hide', :eid => entry.id), :confirm => 'Hide?')
    end
  end

  def reshare_link(entry)
    if (ctx.single? or entry.view_pinned) and
        entry.from_id != auth.name and entry.link
      link_to(inline_menu_label(:reshare, 'Reshare'),
              link_action('reshare', :eid => entry.id))
    end
  end

  def liked?(entry)
    entry.likes.find { |like| like.from_id == auth.name }
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
