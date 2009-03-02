module EntryHelper
  VIEW_LINKS_TAG = '__view_links'

  def viewname
    ctx.viewname
  end

  def ctx
    @ctx
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
    opt = {
      :controller => 'entry',
      :action => 'list',
      :user => u(user),
      :room => u(room),
      :service => u(service_id)
    }
    service_icon(v(entry, 'service'), opt)
  end

  def media_tag(entry, url, *rest)
    if entry and ctx.list? and !setting.list_view_media_rendering
      link_to(icon_tag(:media_disabled) + '[media disabled by setting]', :action => 'show', :id => u(entry.id))
    else
      image_tag(url, *rest)
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
      content = link_content_without_link(title, entry)
    else
      fold, str, links = escape_text(title, ctx.fold ? setting.text_folding_size : nil)
      entry[VIEW_LINKS_TAG] = links
      if fold
        str += link_to(icon_tag(:more), :action => 'show', :id => u(entry.id))
      end
      content = q(str)
    end
    if !entry.medias.empty?
      # entries from Hatena contains 'enclosure' but no title and link for now.
      with_media = content_with_media(entry)
      content += "<br/>\n&nbsp;&nbsp;&nbsp;" + with_media unless with_media.empty?
    end
    content
  end

  def author_link(entry, show_user, show_service)
    user_str = service_str = ''
    if show_user
      user_str += user(entry)
    end
    if show_service
      if ctx.room_for
        name = v(entry, 'service', 'name')
      else
        if entry.room
          name = entry.room.nickname
        elsif ['blog', 'feed'].include?(entry.service_id)
          name = v(entry, 'service', 'name')
        end
      end
      if name
        service_str = h("(#{name})")
      end
    end
    str = user_str + service_str
    str += ':' unless str.empty?
    str
  end

  def original_link(entry)
    if entry.link
      if with_link?(v(entry, 'service')) and unknown_where_to_go?(entry)
        link_content = icon_tag(:go) + h("(#{URI.parse(entry.link).host})")
      else
        link_content = icon_tag(:go)
      end
      link_to(link_content, entry.link)
    end
  end

  def link_content(title, entry)
    link = entry.link
    if unknown_where_to_go?(entry)
      q(h(title) + ' ' + link_to(h("(#{URI.parse(link).host})"), link))
    else
      q(link_to(h(title), link))
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
      (profile_url.host.downcase != link_url.host.downcase) or
        ['internal', 'blog', 'feed'].include?(entry.service_id)
    end
  end

  def with_link?(service)
    service_id = v(service, 'id')
    entry_type = v(service, 'entryType')
    entry_type != 'message' and !['twitter'].include?(service_id)
  end

  def content_with_media(entry)
    medias = entry.medias
    medias.collect { |media|
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

  def google_maps_link(point, entry = nil)
    generator = GoogleMaps::URLGenerator.new(F2P::Config.google_maps_api_key)
    lat = point.lat
    long = point.long
    address = point.address
    tb = generator.staticmap_url(F2P::Config.google_maps_maptype, lat, long, :zoom => F2P::Config.google_maps_zoom, :width => F2P::Config.google_maps_width, :height => F2P::Config.google_maps_height)
    link = generator.link_url(lat, long, address)
    link_to(media_tag(entry, tb, :alt => h(address), :title => h(address), :size => image_size(F2P::Config.google_maps_width, F2P::Config.google_maps_height)), link)
  end

  def brightkite_content(common, entry)
    lat = v(entry, 'geo', 'lat')
    long = v(entry, 'geo', 'long')
    if lat and long
      point = GoogleMaps::Point.new(entry.title, lat, long)
      content = google_maps_link(point, entry)
      if !entry.medias.empty?
        common + ' ' + content
      else
        common + "<br/>\n&nbsp;&nbsp;&nbsp;" + content
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
      link_content_without_link(fold + '...', entry) +
        link_to(icon_tag(:more), :action => 'show', :id => u(entry.id))
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
        icon = link_to(icon_tag(:star, 'un-like'), :action => 'unlike', :id => u(entry.id))
      else
        icon = icon_tag(:star)
      end
      if compact and likes.size > F2P::Config.likes_in_page + 1
        msg = "... #{likes.size - F2P::Config.likes_in_page} more likes"
        icon + likes[0, F2P::Config.likes_in_page].collect { |like| user(like) }.join(' ') +
          ' ' + link_to(h(msg), :action => 'show', :id => u(entry.id))
      else
        icon + "#{likes.size.to_s}(#{likes.collect { |like| user(like) }.join(' ')})"
      end
    end
  end

  def comments(entry, compact)
    unless entry.comments.empty?
      link_to(icon_tag(:comment), :action => 'show', :id => u(entry.id)) + entry.comments.size.to_s
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
    super(v(entry, 'user'))
  end

  def comment_icon(by_self = false)
    by_self ? icon_tag(:comment) : icon_tag(:friend_comment)
  end

  def comment(comment)
    fold, str, links = escape_text(comment.body, ctx.fold ? setting.text_folding_size : nil)
    comment[VIEW_LINKS_TAG] = links
    if fold
      str += link_to(icon_tag(:more), :action => 'show', :id => u(comment.entry.id))
    end
    str
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

  def post_comment_form
    text_field_tag('body') + submit_tag('post')
  end

  def fold_link(entry)
    msg = " (#{entry.fold_entries} more entries)"
    link_to(icon_tag(:more), list_opt(ctx.link_opt(:start => ctx.start, :num => ctx.num, :fold => 'no'))) + h(msg)
  end

  def fold_comment_link(fold)
    msg = " (#{fold.fold_entries} more comments)"
    link_to(icon_tag(:more), :action => 'show', :id => u(fold.entry_id)) + h(msg)
  end

  def write_new_link
    link_to(icon_tag(:write), :controller => 'entry', :action => 'new', :room => u(ctx.room_for))
  end

  def search_link
    link_to(icon_tag(:search), search_opt)
  end

  def service_links(user)
    arg = {
      :auth => auth,
      :user => user
    }
    services = (session[:services] ||= {})[user] ||= User.services(arg)
    map = services.inject({}) { |r, e|
      r[v(e, 'id')] = v(e, 'name')
      r
    }
    links_if_exists("#{map.size} services: ", map.to_a.sort_by { |k, v| k }) { |id, name|
      label = "[#{name}]"
      link_to(h(label), list_opt(:action => 'list', :user => u(user), :service => u(id)))
    }
  end

  def list_links
    arg = {
      :auth => auth,
      :user => auth.name
    }
    lists = session[:lists] ||= User.lists(arg)
    links_if_exists('lists: ', lists) { |e|
      label = "[#{v(e, 'name')}]"
      nickname = v(e, 'nickname')
      if ctx.list == nickname
        h(label)
      else
        link_to(h(label), list_opt(:action => 'list', :list => u(nickname)))
      end
    }
  end

  def room_links(user)
    arg = {
      :auth => auth,
      :user => user
    }
    rooms = (session[:rooms] ||= {})[user] ||= User.rooms(arg)
    links_if_exists('rooms: ', rooms) { |e|
      label = "[#{v(e, 'name')}]"
      nickname = v(e, 'nickname')
      link_to(h(label), list_opt(:action => 'list', :room => u(nickname)))
    }
  end

  def user_links(user)
    arg = {
      :auth => auth,
      :user => user
    }
    users = (session[:subscriptions] ||= {})[user] ||= User.subscriptions(arg)
    links_if_exists("#{users.size} subscriptions: ", users) { |e|
      label = "[#{v(e, 'name')}]"
      nickname = v(e, 'nickname')
      if nickname
        link_to(h(label), list_opt(:action => 'list', :user => u(nickname)))
      end
    }
  end

  def member_links(room)
    arg = {
      :auth => auth,
      :room => room
    }
    members = Room.members(arg)
    links_if_exists("(#{members.size} members) ", members) { |e|
      label = "[#{v(e, 'name')}]"
      nickname = v(e, 'nickname')
      if nickname
        link_to(h(label), list_opt(:action => 'list', :user => u(nickname)))
      end
    }
  end

  def links_if_exists(label, enum, &block)
    str = enum.collect { |v| yield(v) }.join(' ')
    str = h(label) + str unless str.empty?
    str
  end

  def page_links(opt = {})
    no_page = ctx.start.nil?
    start = ctx.start || 0
    num = ctx.num || 0
    links = []
    links << menu_link(icon_tag(:previous), list_opt(ctx.link_opt(:start => start - num, :num => num)), :accesskey => '4') {
      !no_page and start - num >= 0
    }
    links << menu_link(menu_label('updated', '0'), {:action => 'updated'}, {:accesskey => '0'})
    links << menu_link(menu_label('home', '1'), {:action => 'list'}, {:accesskey => '1'})
    unless ctx.updated
      links << menu_link(menu_label('me'), :action => 'list', :user => @auth.name)
      if !ctx.user_for or auth.name == ctx.user_for
        links << menu_link(menu_label('lists'), :action => 'list', :list => 'favorite') {
          !ctx.list
        }
        links << menu_link(menu_label('rooms'), :action => 'list', :room => '*') {
          ctx.room != '*'
        }
      end
      links << menu_link(menu_label('likes'), :action => 'list', :like => 'likes', :user => ctx.user_for) {
        ctx.like != 'likes'
      }
      links << menu_link(menu_label('liked'), :action => 'list', :like => 'liked', :user => ctx.user_for) {
        ctx.like != 'liked'
      }
    end
    if opt[:with_top]
      links << menu_link(menu_label('top', '2'), '#top', :accesskey => '2')
    end
    if opt[:with_bottom]
      links << menu_link(menu_label('bottom', '8'), '#bottom', :accesskey => '8')
    end
    links << menu_link(icon_tag(:next), list_opt(ctx.link_opt(:start => start + num, :num => num)), :accesskey => '6') { !no_page }
    str = links.join(' ')
    if ctx.updated
      str += button_to('refresh', {:action => 'updated'}, {:name => 'submit'})
    end
    str
  end

  def user_page_links(user)
    links = []
    if user != auth.name
      name = user_name(user)
      links << menu_link(menu_label("entries of #{name}"), :action => 'list', :user => user)
      links << menu_link(menu_label("entries of #{name} with friends"), :action => 'list', :friends => user)
    end
    links.join(' ')
  end

  def menu_label(label, accesskey = nil)
    if accesskey and setting.link_type == 'gwt'
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
    link_to(icon_tag(:comment_add, 'comment'), :action => 'show', :id => u(entry.id))
  end

  def url_link(entry)
    link = entry.link if with_link?(v(entry, 'service'))
    link ||= v(entry, VIEW_LINKS_TAG, 0)
    url_link_to(link)
  end

  def comment_url_link(comment)
    link = v(comment, VIEW_LINKS_TAG, 0)
    url_link_to(link)
  end

  def url_link_to(link)
    if link and ctx.link != link
      link_to(icon_tag(:url, 'related'), :action => 'list', :link => link)
    end
  end

  def delete_link(entry)
    if ctx.single? and entry.nickname == auth.name
      link_to(icon_tag(:delete), {:action => 'delete', :id => u(entry.id)}, :confirm => 'Are you sure?')
    end
  end

  def undo_delete_link(id, comment)
    link_to(h('Deleted.  UNDO?'), :action => 'undelete', :id => u(id), :comment => u(comment))
  end

  def undo_add_link(id)
    link_to(h('Added.  UNDO?'), :action => 'delete', :id => u(id))
  end

  def undo_add_comment_link(id, comment)
    link_to(h('Added.  UNDO?'), :action => 'delete', :id => u(id), :comment => u(comment))
  end

  def delete_comment_link(comment)
    if ctx.single?
      cid = v(comment, 'id')
      name = v(comment, 'user', 'nickname')
      if name == auth.name or auth.name == comment.entry.nickname
        link_to(icon_tag(:delete), {:action => 'delete', :id => u(comment.entry.id), :comment => u(cid)}, :confirm => 'Are you sure?')
      end
    end
  end

  def like_link(entry)
    if entry.nickname != auth.name or (entry.room and entry.service_id != 'internal')
      unless liked?(entry)
        link_to(icon_tag(:like), :action => 'like', :id => u(entry.id))
      end
    end
  end

  def reshare_link(entry)
    if ctx.single? and entry.link
      opt = {
        :action => 'reshare',
        :eid => u(entry.id),
      }
      link_to(icon_tag(:reshare), opt)
    end
  end

  def liked?(entry)
    entry.likes.find { |like| v(like, 'user', 'nickname') == auth.name }
  end

  def list_opt(hash = {})
    ctx.list_opt.merge(hash)
  end

  def search_opt(hash = {})
    search_opt = list_opt.merge(:controller => 'entry', :action => 'search')
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
end
