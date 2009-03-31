module EntryHelper
  VIEW_LINKS_TAG = '__view_links'

  def viewname
    return ctx.viewname if ctx.viewname
    if ctx.eid
      'entry'
    elsif ctx.query
      'search results'
    elsif ctx.like == 'likes'
      "entries #{user_name(ctx.user || auth.name)} likes"
    elsif ctx.like == 'liked'
      "#{user_name(ctx.user || auth.name)}'s liked entries"
    elsif ctx.comment == 'comments'
      "entries #{user_name(ctx.user || auth.name)} commented"
    elsif ctx.comment == 'commented'
      "#{user_name(ctx.user || auth.name)}'s commented + liked entries"
    elsif ctx.user
      'user'
    elsif ctx.friends
      'friends'
    elsif ctx.list
      "'#{list_name(ctx.list)}' entries"
    elsif ctx.room
      if ctx.room == '*'
        'rooms'
      else
        'room'
      end
    elsif ctx.link
      'related entries'
    elsif ctx.inbox
      'inbox'
    else
      'home'
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

  def link_show(id)
    link_action('show', :id => u(id))
  end

  def link_user(user, opt = {})
    link_list(opt.merge(:user => user))
  end

  def pin_link(entry)
    if ctx.inbox or ctx.single? or entry.view_pinned
      if entry.view_pinned
        link_to(icon_tag(:pinned, 'unpin'), link_action('unpin', :id => entry.id))
      else
        link_to(icon_tag(:pin), link_action('pin', :id => entry.id))
      end
    end
  end

  def icon(entry)
    service_id = entry.service_id
    name = v(entry, 'service', 'name')
    if ctx.user
      user = entry.nickname || entry.user_id
    end
    if entry.room
      room = entry.room.nickname
    end
    service_icon(v(entry, 'service'), link_user(user, :room => u(room), :service => u(service_id)))
  end

  def media_tag(entry, url, opt = {})
    if entry and ctx.list? and !setting.list_view_media_rendering
      link_to(icon_tag(:media_disabled) + '[media disabled by setting]', link_show(entry.id))
    else
      image_tag(url, opt.merge(:class => h('media')))
    end
  end

  def content(entry)
    common = common_content(entry)
    case entry.service_id
    when 'brightkite'
      brightkite_content(common, entry)
    when 'twitter'
      twitter_content(common, entry)
    when 'tumblr'
      tumblr_content(common, entry)
    else
      common
    end
  end

  def common_content(entry)
    title = entry.title
    if entry.link and with_link?(v(entry, 'service'))
      content = link_content(title, entry)
    else
      fold, str, links = escape_text(title, ctx.fold ? setting.text_folding_size : nil)
      entry[VIEW_LINKS_TAG] = links
      if fold
        str += link_to(icon_tag(:more), link_show(entry.id))
      end
      content = q(str)
    end
    if !entry.medias.empty?
      # entries from Hatena contains 'enclosure' but no title and link for now.
      with_media = content_with_media(entry)
      content += "<br />\n&nbsp;&nbsp;&nbsp;" + with_media unless with_media.empty?
    end
    content
  end

  def friend_of(entry)
    if friendof = v(entry, 'friendof')
      name = v(friendof, 'name')
      nickname = v(friendof, 'nickname')
      if entry.comments.find { |c| c.nickname == nickname }
        h(" (through #{name})")
      elsif entry.likes.find { |l| v(l, 'user', 'nickname') == nickname }
        h(" (through #{name})")
      end
    end
  end

  def author_link(entry, show_user, show_service)
    inbox_str = user_str = service_str = ''
    if show_user
      user_str += user(entry) + (friend_of(entry) || '')
    end
    if show_service
      if ctx.room_for
        name = v(entry, 'service', 'name') if entry.service_id != 'internal'
      else
        if entry.room
          name = entry.room.nickname
        elsif ['blog', 'feed'].include?(entry.service_id)
          name = v(entry, 'service', 'name')
          name = nil if name == v(entry, 'user', 'name')
        end
      end
    elsif !ctx.room_for and entry.room
      # show room name even if show_service is false
      name = entry.room.nickname
    end
    if name
      service_str = h("(#{name})")
    end
    str = inbox_str + user_str + service_str
    str += ':' unless str.empty?
    str
  end

  def inbox_label(entry)
    h('[inbox] ')
  end

  def original_link(entry)
    if entry.link and (!with_link?(v(entry, 'service')) or entry.service_id == 'tumblr')
      if unknown_where_to_go?(entry)
        link_content = icon_tag(:go) + h("(#{URI.parse(entry.link).host})")
      else
        link_content = icon_tag(:go)
      end
      link_to(link_content, entry.link)
    end
  end

  def link_content(title, entry)
    if entry.service_id == 'tumblr'
      link_content_without_link(title, entry)
    else
      link_to(icon_tag(:go) + h(title), entry.link)
    end
  end

  def link_content_without_link(title, entry)
    q(h(title))
  end

  def uri(str)
    URI.parse(str) rescue nil
  end

  def unknown_where_to_go?(entry)
    link_url = uri(entry.link)
    profile_url = uri(v(entry, 'service', 'profileUrl'))
    if profile_url and link_url
      (profile_url.host.downcase != link_url.host.downcase)
    else
      ['blog', 'feed', 'tumblr'].include?(entry.service_id)
    end
  end

  def with_link?(service)
    service_id = v(service, 'id')
    entry_type = v(service, 'entryType')
    entry_type != 'message' and service_id != 'twitter'
  end

  def content_with_media(entry)
    medias = entry.medias
    if ctx.single?
      display = medias
    else
      display = medias[0, setting.entries_in_thread - 1]
    end
    str = display.collect { |media|
      title = v(media, 'title')
      link = v(media, 'link')
      tbs = v(media, 'thumbnails')
      safe_content = nil
      if tbs and tbs.first
        tb = tbs.first
        tb_url = v(tb, 'url')
        tb_width = v(tb, 'width')
        tb_height = v(tb, 'height')
        if tb_url
          label = title || entry.title
          safe_content = media_tag(entry, tb_url, :alt => h(label), :title => h(label), :size => image_size(tb_width, tb_height))
        end
      elsif title
        safe_content = h(title)
      end
      if safe_content
        if link
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

  def extract_first_media_link(media)
    content = v(media, 'content')
    enclosures = v(media, 'enclosures')
    if content and content.first
      link = v(content.first, 'url')
    end
    if enclosures and enclosures.first
      link ||= v(enclosures.first, 'url')
    end
    link ||= v(media, 'link')
    link
  end

  def google_maps_link(point, zoom = nil, entry = nil)
    generator = GoogleMaps::URLGenerator.new(F2P::Config.google_maps_api_key)
    lat = point.lat
    long = point.long
    address = point.address
    tb = generator.staticmap_url(F2P::Config.google_maps_maptype, lat, long, :zoom => zoom || F2P::Config.google_maps_zoom, :width => F2P::Config.google_maps_width, :height => F2P::Config.google_maps_height)
    link = generator.link_url(lat, long, address)
    link_to(media_tag(entry, tb, :alt => h(address), :title => h(address), :size => image_size(F2P::Config.google_maps_width, F2P::Config.google_maps_height)), link)
  end

  def brightkite_content(common, entry)
    lat = v(entry, 'geo', 'lat')
    long = v(entry, 'geo', 'long')
    if lat and long
      point = GoogleMaps::Point.new(entry.title, lat, long)
      content = google_maps_link(point, nil, entry)
      if !entry.medias.empty?
        common + ' ' + content
      else
        common + "<br />\n&nbsp;&nbsp;&nbsp;" + content
      end
    else
      common
    end
  end

  def twitter_content(common, entry)
    common.gsub(/@([a-zA-Z0-9_]+)/) {
      '@' + link_to($1, "http://twitter.com/#{$1}")
    }
  end

  def tumblr_content(common, entry)
    title = entry.title
    fold = fold_length(title, setting.text_folding_size - 3)
    if ctx.fold and entry.medias.empty? and fold != title
      link_content(fold + '...', entry) + link_to(icon_tag(:more), link_show(entry.id))
    else
      common
    end
  end

  def escape_text(content, fold_size = nil)
    str = ''
    fold_size ||= content.length
    org_size = 0
    m = nil
    links = []
    while content.match(URI.regexp)
      m = $~
      added, part = fold_concat(m.pre_match, fold_size - org_size)
      str += h(part)
      if added
        org_size += added
      else
        return true, str, links
      end
      uri = uri(m[0])
      added, part = fold_concat(m[0], fold_size - org_size)
      if uri.nil? or !uri.is_a?(URI::HTTP)
        str += h(part)
        if added
          org_size += added
        else
          return true, str, links
        end
      else
        links << m[0]
        if added
          str += link_to(h(m[0]), m[0])
          org_size += added
        else
          str += link_to(h(part), m[0])
          return true, str, links
        end
      end
      content = m.post_match
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

  def via(entry)
    super(v(entry, 'via'))
  end

  def likes(entry, compact)
    me, rest = entry.likes.partition { |e| v(e, 'user', 'nickname') == auth.name }
    likes = me + rest
    if !likes.empty?
      if liked?(entry)
        icon = link_to(icon_tag(:star, 'unlike'), link_action('unlike', :id => u(entry.id)))
      else
        icon = icon_tag(:star)
      end
      max = compact ? F2P::Config.likes_in_page : F2P::Config.max_friend_list_num
      if likes.size > max + 1
        msg = "... #{likes.size - max} more likes"
        icon + likes[0, max].collect { |like| user(like) }.join(' ') + ' ' +
          (compact ? link_to(h(msg), link_show(entry.id)) : h(msg))
      else
        icon + "#{likes.size.to_s}(#{likes.collect { |like| user(like) }.join(' ')})"
      end
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

  def published(entry, compact = false)
    published = v(entry, 'published')
    date(published, compact)
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

  def user(entry)
    user = v(entry, 'user')
    if setting.twitter_comment_hack and v(entry, 'service') and entry.service_id == 'twitter'
      if nickname = v(user, 'nickname')
        name = v(user, 'name')
        tw_name = twitter_username(entry)
        if name != tw_name
          if nickname == auth.name
            name = self_label
          end
          name += "(#{tw_name})"
          return link_to(h(name), link_user(nickname))
        end
      end
    end
    super(user)
  end

  def comment_icon(by_self = false)
    by_self ? icon_tag(:comment) : icon_tag(:friend_comment)
  end

  def comment(comment)
    fold, str, links = escape_text(comment.body, ctx.fold ? setting.text_folding_size : nil)
    comment[VIEW_LINKS_TAG] = links
    if fold
      str += link_to(icon_tag(:more), link_show(comment.entry.id))
    end
    str
  end

  def inline_comment(comment)
    if v(comment, 'date') != v(comment.entry, 'updated')
      comment(comment) + ' ' + date(v(comment, 'date'), true)
    else
      comment(comment)
    end
  end

  def search_form
    str = ''
    str += hidden_field_tag('user', ctx.user) if ctx.user
    str += hidden_field_tag('list', ctx.list) if ctx.list
    str += hidden_field_tag('room', ctx.room_for) if ctx.room_for
    str += hidden_field_tag('friends', ctx.friends) if ctx.friends
    str += hidden_field_tag('service', ctx.service) if ctx.service
    str += text_field_tag('query', ctx.query) + submit_tag('search')
    str
  end

  def post_entry_form
    str = ''
    str += hidden_field_tag('room', ctx.room_for) + h(ctx.room_for) + ': ' if ctx.room_for
    str += text_field_tag('body') + submit_tag('post')
    str
  end

  def post_comment_form(entry)
    if setting.twitter_comment_hack and entry.service_id == 'twitter' and user_status(entry.user_id) == 'public'
      default = twitter_username(entry)
      unless default.empty?
        default = "@#{default} "
      end
    end
    text_field_tag('body', default) + submit_tag('post')
  end

  def edit_comment_form(comment)
    default = comment.body
    text_field_tag('body', default) + submit_tag('post')
  end

  def fold_link(entry)
    msg = " (#{entry.fold_entries} more entries)"
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
      r[v(e, 'id')] = v(e, 'name')
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
    user = auth.name
    lists = user_lists(user)
    links_if_exists('lists: ', lists) { |e|
      label = "[#{v(e, 'name')}]"
      nickname = v(e, 'nickname')
      if ctx.list == nickname
        h(label)
      else
        link_to(h(label), link_list(:list => u(nickname)))
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
    candidates = rooms.map { |e| [v(e, 'name'), v(e, 'nickname')] }
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
    links_if_exists('rooms: ', rooms) { |e|
      label = "[#{v(e, 'name')}]"
      nickname = v(e, 'nickname')
      link_to(h(label), link_list(:room => u(nickname)))
    }
  end

  def user_links(user)
    users = user_subscriptions(user)
    users = users.find_all { |e| v(e, 'nickname') and v(e, 'nickname') != auth.name }
    links_if_exists("#{users.size} subscriptions: ", users, F2P::Config.max_friend_list_num) { |e|
      nickname = v(e, 'nickname')
      label = "[#{v(e, 'name')}]"
      link_to(h(label), link_user(nickname))
    }
  end

  def imaginary_user_links(user)
    users = user_subscriptions(user)
    users = users.find_all { |e| !v(e, 'nickname') }
    links_if_exists("#{users.size} imaginary friends: ", users, F2P::Config.max_friend_list_num) { |e|
      user_id = v(e, 'id')
      label = "<#{v(e, 'name')}>"
      link_to(h(label), link_user(user_id))
    }
  end

  def member_links(room)
    members = room_members(room)
    me, rest = members.partition { |e| v(e, 'nickname') == auth.name }
    members = me + rest
    links_if_exists("(#{members.size} members) ", members, F2P::Config.max_friend_list_num) { |e|
      label = "[#{v(e, 'name')}]"
      nickname = v(e, 'nickname')
      if nickname
        link_to(h(label), link_user(nickname))
      end
    }
  end

  def links_if_exists(label, enum, max = nil, &block)
    ary = enum.collect { |v| yield(v) }
    if max and ary.size > max + 1
      ary = ary[0, max] << "... #{ary.size - max} more"
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
    links << menu_link(icon_tag(:previous), list_opt(ctx.link_opt(:start => start - num, :num => num)), accesskey('4')) {
      !no_page and start - num >= 0
    }
    if opt[:for_top]
      links << link_to(icon_tag(:bottom), '#bottom', accesskey('8'))
    end
    if opt[:for_bottom]
      links << link_to(icon_tag(:top), '#top', accesskey('2'))
    end
    links << menu_link(menu_label('inbox', '0'), link_action('inbox'), accesskey('0'))
    links << menu_link(menu_label('all', '1'), link_list(), accesskey('1'))
    links << menu_link(menu_label('me', '3'), link_user(auth.name), accesskey('3'))
    links << menu_link(menu_label('lists', '7'), link_list(:list => u(v(user_lists(auth.name).first, 'nickname'))), accesskey('7')) {
      !ctx.list
    }
    links << menu_link(menu_label('rooms', '9'), link_list(:room => '*'), accesskey('9')) {
      ctx.room != '*'
    }
    links << menu_link(icon_tag(:next), list_opt(ctx.link_opt(:start => start + num, :num => num)), accesskey('6')) { !no_page }
    links << archive_button
    links.join(' ')
  end

  def bottom_menu_link
    if cell_phone? and ctx.inbox
      label = '8.menu'
      link_to(h("[#{label}]"), '#bottom', accesskey('8'))
    end
  end

  def archive_button
    if ctx.inbox
      label = 'mark as read'
      label = '5.' + label if cell_phone?
      submit_tag(label, accesskey('5'))
    end
  end

  def user_page_links(user)
    links = []
    links << menu_link(menu_label("self"), link_user(user)) {
      ctx.friends or ctx.like or ctx.comment
    }
    if user_id(user) != user
      links << menu_link(menu_label('friends'), link_list(:friends => user)) {
        !ctx.friends
      }
      links << menu_link(menu_label('likes'), link_list(:like => 'likes', :user => ctx.user_for)) {
        ctx.like != 'likes'
      }
      links << menu_link(menu_label('comments'), link_list(:comment => 'comments', :user => ctx.user_for)) {
        ctx.comment != 'comments'
      }
    end
    links << menu_link(menu_label('liked'), link_list(:like => 'liked', :user => ctx.user_for)) {
      ctx.like != 'liked'
    }
    links << menu_link(menu_label('commented'), link_list(:comment => 'commented', :user => ctx.user_for)) {
      ctx.comment != 'commented'
    }
    'filter: ' + links.join(' ')
  end

  def menu_label(label, accesskey = nil)
    if accesskey and cell_phone?
      label = accesskey + '.' + label
    end
    h("[#{label}]")
  end

  def menu_link(label, opt, html_opt = {}, &block)
    if block.nil? or block.call
      link_to(label, opt, html_opt)
    else
      label
    end
  end

  def post_comment_link(entry)
    link_to(icon_tag(:comment_add, 'comment'), link_show(entry.id))
  end

  def url_link(entry)
    if ctx.single? or ctx.query
      link = entry.link if with_link?(v(entry, 'service'))
      link ||= v(entry, VIEW_LINKS_TAG, 0)
      url_link_to(link)
    end
  end

  def comment_url_link(comment)
    if ctx.single?
      link = v(comment, VIEW_LINKS_TAG, 0)
      url_link_to(link)
    end
  end

  def url_link_to(link)
    if link and ctx.link != link
      link_to(icon_tag(:url, 'related'), link_list(:link => link))
    end
  end

  def delete_link(entry)
    if ctx.single? and entry.nickname == auth.name
      link_to(icon_tag(:delete), link_action('delete', :id => u(entry.id)), :confirm => 'Are you sure?')
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
    if ctx.single?
      if comment.nickname == auth.name or auth.name == comment.entry.nickname
        link_to(icon_tag(:comment_edit, 'edit'), link_action('edit', :id => u(comment.entry.id), :comment => u(comment.id)))
      end
    end
  end

  def delete_comment_link(comment)
    if ctx.single?
      if comment.nickname == auth.name or auth.name == comment.entry.nickname
        link_to(icon_tag(:delete), link_action('delete', :id => u(comment.entry.id), :comment => u(comment.id)), :confirm => 'Are you sure?')
      end
    end
  end

  def like_link(entry)
    if entry.nickname != auth.name or (entry.room and entry.service_id != 'internal')
      unless liked?(entry)
        link_to(icon_tag(:like), link_action('like', :id => u(entry.id)))
      end
    end
  end

  def reshare_link(entry)
    if (ctx.inbox or ctx.single? or entry.view_pinned) and
        entry.link and entry.nickname != auth.name
      link_to(icon_tag(:reshare), link_action('reshare', :eid => u(entry.id)))
    end
  end

  def liked?(entry)
    entry.likes.find { |like| v(like, 'user', 'nickname') == auth.name }
  end

  def list_opt(hash = {})
    ctx.list_opt.merge(hash)
  end

  def search_opt(hash = {})
    search_opt = list_opt(hash)
    search_opt[:friends] = 'me' if ctx.home
    search_opt[:room] = nil if search_opt[:room] == '*'
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

    def user_id
      nil
    end

    def service_identity
      nil
    end
  end

  def fold_entries(entries)
    if ctx.fold
      fold_items(entries.first.id, entries)
    else
      entries.dup
    end
  end

  def fold_comments(comments)
    if ctx.fold
      fold_items(comments.first.entry.id, comments)
    else
      comments.dup
    end
  end

  def fold_items(entry_id, items)
    if items.size > setting.entries_in_thread
      head_size = 1
      result = items[0, head_size]
      result << Fold.new(entry_id, items.size - (setting.entries_in_thread - 1))
      last_size = setting.entries_in_thread - 2
      result += items[-last_size, last_size]
      result
    else
      items.dup
    end
  end

  def comment_inline?(entry)
    ctx.list? and entry.self_comment_only?
  end

  def twitter_username(entry)
    if entry.service_id == 'twitter'
      (v(entry, 'service', 'profileUrl') || '').sub(/\A.*\//, '')
    end
  end

  def gps_link(*arg)
    if jpmobile?
      str = get_position_link_to(*arg)
      str = nil if str.empty?
      str
    end
  end
end
