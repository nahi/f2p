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
      'Entry'
    elsif ctx.query
      'Search results'
    elsif ctx.user
      feed_name
    elsif ctx.feed
      feed_name
    elsif ctx.room
      feed_name
    elsif ctx.link
      'Related entries'
    elsif ctx.label == 'pin'
      'Pin'
    elsif ctx.inbox
      'Inbox'
    else
      feed_name
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

  def link_back(label, opt = {})
    list_ctx = session[:ctx]
    if list_ctx and list_ctx.inbox
      label += ' to Inbox'
    elsif list_ctx and list_ctx.label == 'pin'
      label += ' to Pin list'
    elsif @original_feed and @original_feed.name
      label += ' to ' + @original_feed.name
    end
    if list_ctx
      list_ctx = list_ctx.dup
      list_ctx.eid = nil
      link_to(h(label), list_ctx.back_opt.merge(opt))
    else
      link_to(h(label), opt.merge(:controller => :entry))
    end
  end

  def author_picture(entry)
    return if ctx.user_only?
    if setting.list_view_profile_picture
      if id = entry.origin_id
        picture(id)
      end
    end
  end

  def to_picture(to)
    if ctx.single? or setting.list_view_profile_picture
      picture(to.id)
    end
  end

  def pin_link(entry)
    if ajax?
      pin_link_remote(entry.id, entry.view_pinned)
    else
      pin_link_plain(entry)
    end
  end

  def pin_link_remote(eid, pinned)
    span_id = 'pin_' + eid
    if pinned
      content = inline_icon_tag(:pinned, 'unpin')
      link = link_action('pin_remote', :eid => eid, :pinned => 1)
    else
      content = inline_icon_tag(:pin)
      link = link_action('pin_remote', :eid => eid)
    end
    content_tag('span', link_to_remote(content, :update => span_id, :url => link), :id => span_id)
  end

  def pin_link_plain(entry)
    if entry.view_pinned
      link_to(inline_icon_tag(:pinned, 'unpin'), link_action('unpin', :eid => entry.id))
    else
      link_to(inline_icon_tag(:pin), link_action('pin', :eid => entry.id))
    end
  end

  def to(entry)
    links = entry.to.map { |to|
      name = to.name
      if to.group?
        opt = { :room => to.id }
        link = link_list(opt)
        [to_picture(to), link_to(h(name), link), lock_icon(to)].join
      else
        if to.id == auth.name
          name = self_label
        else
          name = to.name
        end
        if entry.from_id != to.id
          name = 'DM:' + name
        end
        [to_picture(to), link_to(h(name), link_user(to.id)), lock_icon(to)].join
      end
    }.compact
    unless links.empty?
      'to ' + links.join(', ')
    end
  end

  def lock_icon(from)
    if from and from.private
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
      content = twitter_content(content)
    end
    scan_media_from_link(entry)
    unless entry.view_medias.empty?
      content += "<br />\n"
      content += entry.view_medias.map { |uri| media_tag(entry, uri) }.join(' ')
      content += "<br />\n"
    end
    content
  end

  def common_content(entry)
    body = entry.body
    return '' unless body
    fold, content, links = escape_text(body, ctx.fold ? setting.text_folding_size : nil)
    entry.view_links = links
    if fold
      msg = '(more)'
      content += link_to(h(msg), link_show(entry.id))
    end
    if link_entry?(entry)
      link = entry.link
      content += ' - ' + link_to(h(summary_uri(link)), link)
    end
    if !entry.files.empty?
      content += entry.files.map { |file|
        label = file.type
        icon = image_tag(file.icon, :alt => h(label), :title => h(label), :size => '16x16')
        str = "<br />\n" + link_to(icon + h(file.name), file.url)
        str += h(" (#{file.size} bytes)") if file.size
        str
      }.join(', ')
    end
    with_media = with_geo = nil
    if !entry.thumbnails.empty?
      # entries from Hatena contains 'enclosure' but no title and link for now.
      with_media = content_with_media(entry)
    end
    if entry.geo and !entry.view_map
      point = GoogleMaps::Point.new(body, entry.geo.lat, entry.geo.long)
      zoom = F2P::Config.google_maps_zoom
      width = F2P::Config.google_maps_width
      height = F2P::Config.google_maps_height
      unless entry.thumbnails.empty?
        max = entry.thumbnails.map { |t| t.height || 0 }.max
        if max > 0
          width = height = max
        end
      end
      if entry.via and entry.via.brightkite?
        if !entry.thumbnails.empty?
          zoom = BRIGHTKITE_MAP_ZOOM
          width = BRIGHTKITE_MAP_WIDTH
          height = BRIGHTKITE_MAP_HEIGHT
        end
      end
      with_geo = google_maps_link(point, entry, zoom, width, height)
    end
    ext = [with_media, with_geo].join(' ')
    unless ext.strip.empty?
      content += "<br />\n" + ext + "<br />\n"
    end
    content
  end

  def link_entry?(entry)
    entry.link and !(entry.via and entry.via.twitter?)
  end

  def scan_media_from_link(entry)
    if entry.view_links and entry.view_medias.empty?
      entry.view_links.each do |link|
        case link
        # via gotoken
        when /\bmovapic.com\/pic\/([a-z0-9]+)/
          uri = "http://image.movapic.com/pic/t_#{$1}.jpeg"
          entry.view_medias << uri
        when /\bf\.hatena\.ne\.jp\/(\w+?)\/(\d+?)$/
          service = $1
          full_date = $2
          tag = service[0, 1]
          date = full_date[0, 8]
          uri = "http://img.f.hatena.ne.jp/images/fotolife/#{tag}/#{service}/#{date}/#{full_date}_120.jpg"
          entry.view_medias << uri
        end
      end
    end
  end

  def friend_of(entry)
    if entry.fof_type
      case entry.fof_type
      when 'like'
        action = 'liked this'
      when 'comment'
        action = 'commented on this'
      else
        action = ''
      end
      h(" (#{entry.fof.name} #{action})")
    end
  end

  def author_link(entry, with_picture = true)
    if entry.from.group?
      from = link_to(h(entry.from.name), link_list(:room => entry.from.id))
    elsif ctx.room_for
      # filter by group + user
      from = user(entry, link_list(:query => '', :room => ctx.room_for, :user => entry.from_id))
    else
      from = user(entry)
    end
    ary = []
    if with_picture
      ary << author_picture(entry)
    end
    ary << from << lock_icon(entry.from) << friend_of(entry)
    ary.join
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
    need_unread_mgmt? and entry_or_comment.emphasize?
  end

  def original_link(entry)
    link = entry.url
    link_content = "See original (#{uri_domain(link)})"
    link_to(h(link_content), link)
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

  def summary_uri(str)
    uri = uri(str)
    if uri
      added, part = fold_concat(uri.request_uri, 17)
      uri.scheme + '://' + uri.host + part
    else
      str
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
      label = '[media]'
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

  def twitter_content(common)
    common.gsub(/@([a-zA-Z0-9_]+)/) {
      '@' + link_to($1, "http://twitter.com/#{$1}", :class => 'twname')
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
      str += markup_sentence(part)
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
        str += markup_sentence(part)
        if added
          org_size += added
        else
          return true, str, links
        end
      else
        links << target
        if added
          str += link_to(markup_sentence(target), target)
          org_size += added
        else
          str += link_to(markup_sentence(part), target)
          return true, str, links
        end
      end
    end
    added, part = fold_concat(content, fold_size - org_size)
    str += markup_sentence(part)
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

  def markup_sentence(str)
    ary = []
    while str.match(/#[a-zA-Z0-9\-_\.+:=]{2,}/)
      m = $~
      ary << h(m.pre_match)
      if m.pre_match.empty? or /\s\z/ =~ m.pre_match
        link = link_to(h(m[0]), search_opt(:action => :list, :query => m[0]))
        ary << content_tag('span', link, :class => 'hashtag')
      else
        ary << h(m[0])
      end
      str = m.post_match
    end
    ary << h(str)
    ary.join
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
      icon = icon_tag(:star) + h(likes.size.to_s)
      max = F2P::Config.max_friend_list_num
      if likes.size > max + 1
        msg = "... #{likes.size - max} more likes"
        members = likes[0, max].collect { |like| user(like) }.join(' ') + ' ' + h(msg)
      else
        members = likes.collect { |like| user(like) }.join(' ')
      end
      icon + '(' + members + ') ' + like_link(entry)
    else
      like_link(entry)
    end
  end

  def friends_likes(entry)
    if !entry.likes.empty?
      likes = entry.likes.find_all { |e| e.from and e.from.friend? }
      icon = inline_icon_tag(:star)
      size = entry.likes_size
      if size != likes.size
        icon += link_to(h(size.to_s), link_show(entry.id))
      end
      if !likes.empty?
        members = likes.collect { |like|
          if need_unread_mgmt? and like.emphasize?
            emphasize_as_unread(user(like))
          else
            user(like)
          end
        }.join(' ')
        icon += '(' + members + ')'
      end
      icon += ' '
    else
      icon = ''
    end
    span_id = 'like_' + entry.id
    content = icon + like_link(entry)
    content_tag('span', content, :id => span_id)
  end

  def comments(eid, comments)
    div_id = 'c_' + eid
    str = %Q[<div class="comment-block" id="#{div_id}">\n]
    str += comments.map { |comment|
      if comment.respond_to?(:fold_entries)
        '<div class="comment comment-fold">' +
          fold_comment_link(comment, div_id) +
          '</div>'
      else
        date = comment_date(comment, true) unless comment.posted_with_entry?
        str = '<div class="comment comment-body">' +
          comment_icon(comment) + comment(comment)
        [str, comment_author_link(comment), via(comment), date, comment_url_link(comment), comment_link(comment)].join(' ') +
          '</div>'
      end
    }.join("\n")
    str + "</div>\n"
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

  def user(entry_or_comment, opt = nil)
    unless entry_or_comment.respond_to?(:service)
      return super(entry_or_comment.from, opt)
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
          return link_to(h(name), opt || link_user(id))
        end
      end
    end
    super(entry.user, opt)
  end

  def comment_icon(comment = nil)
    if comment
      by_friend = (comment.from and comment.from.friend?)
    else
      by_friend = true
    end
    label = 'comment'
    by_friend ? inline_icon_tag(:friend_comment, label) : inline_icon_tag(:comment, label)
  end

  def comment(comment)
    fold, str, links = escape_text(comment.body, ctx.fold ? setting.text_folding_size : nil)
    comment.view_links = links
    if fold
      msg = '(more)'
      str += link_to(h(msg), link_show(comment.entry.id))
    end
    if comment.entry.via and comment.entry.via.twitter?
      str = twitter_content(str)
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
    search_opt.map { |key, value|
      if key != :query
        hidden_field_tag(key.to_s, value.to_s)
      end
    }.compact.join("\n") +
      text_field_tag('query', ctx.query, :placeholder => 'search') +
      submit_tag('search')
  end

  def search_drilldown_links
    opt = search_opt
    links = []
    with_likes = opt[:with_likes].to_i + 1
    links << menu_link(h("[likes >= #{with_likes}]"), opt.merge(:with_likes => with_likes))
    with_comments = opt[:with_comments].to_i + 1
    links << menu_link(h("[comments >= #{with_comments}]"), opt.merge(:with_comments => with_comments))
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
    return if ctx.direct_message?
    str = ''
    str += hidden_field_tag('to_lines', '1')
    if ctx.user_for
      if @feedinfo.commands.include?('dm')
        str += hidden_field_tag('to_0', ctx.user_for) + h(feed_name) + ': '
      else
        return
      end
    end
    if ctx.room_for and @feedinfo.commands.include?('post')
      str += hidden_field_tag('to_0', ctx.room_for) + h(feed_name) + ': '
    end
    str +
      text_field_tag('body', nil, :placeholder => 'post') +
      submit_tag('post') +
      write_new_link
  end

  def post_comment_form(entry)
    if entry.commands.include?('comment')
      if entry.via and setting.twitter_comment_hack and entry.via.twitter?
        default = entry.twitter_username
        unless default.empty?
          default = "@#{default} "
        end
      end
      text_field_tag('body', default, :placeholder => 'comment') +
        submit_tag('post')
    else
      h('(comment disabled)')
    end
  end

  def edit_entry_form(entry, body = nil)
    if entry.commands.include?('edit')
      default = body || entry.body
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

  def fold_comment_link(fold, remote_update_id = nil)
    msg = "(#{fold.fold_entries} more comments)"
    if ajax? and remote_update_id
      link_to_remote(msg, :update => remote_update_id, :url => link_action('comments_remote', :eid => fold.entry_id))
    else
      link_to(msg, link_show(fold.entry_id))
    end
  end

  # override
  def pinned_link
    pin_label = 'Pin'
    if @threads and @threads.pins and @threads.pins > 0
      pin_label += "(#{@threads.pins})"
    end
    link_to(h(pin_label), link_list(:label => 'pin'), accesskey('9'))
  end

  def write_new_link
    link_to(h('more'), link_action('new', :room => ctx.room_for))
  end

  # override
  def search_link
    menu_link(menu_label('search'), search_opt(link_action('search')))
  end

  def zoom_select_tag(varname, default)
    candidates = (0..19).map { |e| [e, e] }
    select_tag(varname, options_for_select(candidates, default))
  end

  def to_select_tag(varname, default)
    user = auth.name
    candidates = @feedinfo.subscriptions.find_all { |e| e.group? and e.commands.include?('post') }.map { |e| [e.name, e.id] }
    candidates += @feedinfo.subscriptions.find_all { |e| e.user? and e.commands.include?('dm') }.map { |e| [e.name, e.id] }
    candidates.unshift([nil, nil])
    if candidates.size >= F2P::Config.max_select_num
      text_field_tag(varname, default)
    else
      select_tag(varname, options_for_select(candidates, default))
    end
  end

  def service_select_tag(varname, default)
    candidates = Service.find(:all).map { |s| [s.name, s.service_id] }
    candidates.unshift([nil, nil])
    if candidates.size >= F2P::Config.max_select_num
      text_field_tag(varname, default)
    else
      select_tag(varname, options_for_select(candidates, default))
    end
  end

  def group_select_tag(varname, default)
    user = auth.name
    feeds = @feedinfo.subscriptions.find_all { |e| e.group? }
    candidates = feeds.map { |e| [e.name, e.id] }
    candidates.unshift([nil, nil])
    if candidates.size >= F2P::Config.max_select_num
      text_field_tag(varname, default)
    else
      select_tag(varname, options_for_select(candidates, default))
    end
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
    if ctx.list? and !ctx.is_summary?
      links << menu_link(menu_label('<', '4', true), list_opt(ctx.link_opt(:start => start - num, :num => num, :direction => 'rewind')), accesskey('4')) {
        !no_page and start - num >= 0
      }
    end
    if ctx.list? and threads = opt[:threads] and opt[:for_top]
      if entry = find_show_entry(threads)
        links << menu_link(menu_label('show first', '1'), link_show(entry.id), accesskey('1'))
      else
        links << menu_label('from the top')
      end
    end
    if opt[:for_bottom]
      if ctx.inbox
        links << archive_link
        links << all_link
      else
        links << inbox_link
      end
    end
    if ctx.list? and !ctx.is_summary?
      links << menu_link(menu_label('>', '6'), list_opt(ctx.link_opt(:start => start + num, :num => num)), accesskey('6')) { !no_page }
      if threads = opt[:threads] and opt[:for_top]
        links << list_range_notation(threads)
      end
    end
    links.join(' ')
  end

  def all_link
    menu_link(menu_label('show all', '7'), list_opt(:action => :list, :start => ctx.start, :num => ctx.num), accesskey('7'))
  end

  def find_show_entry(threads)
    if thread = threads.first
      thread.root
    end
  end

  def list_range_notation(threads)
    if threads.from_modified and threads.to_modified
      from = ago(threads.from_modified)
      if ctx.start != 0
        to = ago(threads.to_modified)
        if from == to
          h("(#{to} ago)")
        else
          h("(~ #{to} ago)")
        end
      end
    end
  end

  def next_entry(entry)
    return if entry.nil? or @original_feed.nil?
    entries = @original_feed.entries.map { |thread| thread.entries }.flatten
    # need to find the entry from cache; view_nextid is set only in thread.
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

  def link_opt_for_next_page
    if list_ctx = session[:ctx]
      unless list_ctx.is_summary?
        list_ctx = list_ctx.dup
        list_ctx.eid = nil
        start = list_ctx.start || 0
        num = list_ctx.num || 0
        list_ctx.list_opt.merge(
          list_ctx.link_opt(
            :start => start + num,
            :num => num,
            :show_first => 1
          )
        )
      end
    end
  end

  def archive_link
    menu_link(menu_label('archive all', '5'), link_action('archive'), accesskey('5'))
  end

  def best_of_links(listid)
    if listid == 'home' or %r(\Asummary/) =~ listid
      listid = 'home'
      summary = 'summary/'
    elsif %r(/summary/) =~ listid
      c = listid.split('/')
      listid = c[0, c.size - 2].join('/')
      summary = listid + '/summary/'
    else
      summary = listid + '/summary/'
    end
    links = []
    feedid = summary + '1'
    links << link_to(h('a day'), link_feed(feedid))
    feedid = summary + '3'
    links << link_to(h('3 days'), link_feed(feedid))
    feedid = summary + '7'
    links << link_to(h('7 days'), link_feed(feedid))
    feedid = listid
    links << link_to(h('Show all'), link_feed(feedid))
    links.join(' ')
  end

  def comment_link(comment)
    if comment.last?
      link_to(h('>>>'), link_show(comment.entry.id))
    end
  end

  def post_comment_link(entry, opt = {})
    if !entry.comments.empty? and !comment_inline?(entry)
      if entry.comments_size == 1
        str = ">>>#{entry.comments_size}"
      else
        str = ">>>#{entry.comments_size}"
      end
      str = latest(entry.modified_at, str)
      if emphasize_as_unread?(entry)
        str = emphasize_as_unread(str)
      end
    #elsif entry.commands.include?('comment')
    else
      str = h('>>>')
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
      menu_link(inline_menu_label(:url, 'search link'), link_list(:link => link, :query => query))
    end
  end

  def delete_link(entry)
    if entry.commands.include?('delete')
      menu_link(inline_menu_label(:delete, 'delete'), link_action('delete', :eid => entry.id), :confirm => 'Delete?')
    end
  end

  def undo_delete_link(id, comment)
    link_to(h('Deleted.  UNDO?'), link_action('undelete', :eid => id, :comment => comment), :confirm => 'Undo?')
  end

  def undo_add_link(id)
    link_to(h('Added.  UNDO?'), link_action('delete', :eid => id), :confirm => 'Undo?')
  end

  def undo_add_comment_link(id, comment)
    link_to(h('Added.  UNDO?'), link_action('delete', :eid => id, :comment => comment), :confirm => 'Undo?')
  end

  def moderate_link(entry)
    if !ctx.moderate and editable?(entry)
      menu_link(inline_menu_label(:comment_edit, 'edit'),
              link_action('show', :eid => entry.id, :moderate => true))
    end
  end

  def locate_link(entry)
    if false #!ctx.moderate and editable?(entry)
      menu_link(inline_menu_label(:comment_edit, 'locate'),
              link_action('show', :eid => entry.id, :moderate => 'geo'))
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
    # when you like old icons...
    # inline_icon_tag(icon, label)
    menu_label(label || icon.to_s)
  end

  def like_link(entry)
    if ctx.list? and ajax?
      like_link_remote(entry)
    else
      like_link_plain(entry)
    end
  end

  def like_link_remote(entry)
    eid = entry.id
    span_id = 'like_' + eid
    if entry.commands.include?('like')
      content = inline_menu_label(:like, 'like')
      link = link_action('like_remote', :eid => eid, :single => 1)
    elsif entry.likes.any? { |e| e.from_id == auth.name }
      content = inline_menu_label(:unlike, 'un-like')
      link = link_action('like_remote', :eid => eid, :single => 1, :liked => 1)
    else
      content = nil
    end
    if content
      link_to_remote(content, :update => span_id, :url => link)
    else
      ''
    end
  end

  def like_link_plain(entry)
    if entry.commands.include?('like')
      menu_link(inline_menu_label(:like, 'like'), link_action('like', :eid => entry.id))
    elsif entry.likes.any? { |e| e.from_id == auth.name }
      menu_link(inline_menu_label(:unlike, 'un-like'), link_action('unlike', :eid => entry.id))
    else
      ''
    end
  end

  def hide_link(entry)
    #if entry.commands.include?('hide')
      menu_link(inline_menu_label(:hide, 'hide'), link_action('hide', :eid => entry.id), :confirm => 'Hide?')
    #end
  end

  def reshare_link(entry)
    if ctx.single? or entry.view_pinned
      menu_link(inline_menu_label(:reshare, 'reshare'), link_action('reshare', :reshared_from => entry.id))
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
    if setting.entries_in_thread == 0
      if comments.empty?
        []
      else
        e = comments.first.entry
        [Fold.new(e.id, e.comments_size)]
      end
    else
      comments.map { |comment|
        if comment.placeholder
          Fold.new(comment.entry.id, comment.num)
        else
          comment
        end
      }
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
