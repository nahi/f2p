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
    elsif ctx.pin?
      'Star'
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
    elsif list_ctx and list_ctx.pin?
      label += ' to Star'
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
    return if ctx.ff? and ctx.user_only?
    if setting.list_view_profile_picture
      if entry.from.profile_image_url
        name = entry.from.name
        profile_image_tag(entry.from.profile_image_url, name, name)
      elsif id = entry.origin_id
        picture(id)
      end
    end
  end

  def to_picture(to)
    if ctx.single? or setting.list_view_profile_picture
      if to.profile_image_url
        profile_image_tag(to.profile_image_url, to.name, to.name)
      else
        picture(to.id)
      end
    end
  end

  def profile_picture(user)
    if user.profile_image_url
      profile_image_tag(user.profile_image_url, user.name, user.name)
    else
      picture(user.id)
    end
  end

  def pin_link(entry)
    if ajax?
      eid = entry.id
      if entry.service_source
        eid = [eid, entry.service_source, entry.service_user].join('_')
      end
      pin_link_remote(eid, entry.view_pinned)
    else
      pin_link_plain(entry)
    end
  end

  def pin_link_remote(eid, pinned)
    span_id = 'pin_' + eid
    if pinned
      content = inline_icon_tag(:pinned, 'delete')
      link = link_action('pin_remote', :eid => eid, :pinned => 1)
    else
      content = inline_icon_tag(:pin, 'star')
      link = link_action('pin_remote', :eid => eid)
    end
    content_tag('span', link_to_remote(content, :update => span_id, :url => link), :id => span_id)
  end

  def pin_link_plain(entry)
    eid = entry.id
    if entry.service_source
      eid = [eid, entry.service_source, entry.service_user].join('_')
    end
    if entry.view_pinned
      link_to(inline_icon_tag(:pinned, 'delete'), link_action('unpin', :eid => eid))
    else
      link_to(inline_icon_tag(:pin, 'star'), link_action('pin', :eid => eid))
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
        ary = []
        ary << to_picture(to)
        if entry.tweet?
          ary << service_user_link('tweets', to)
        elsif entry.graph?
          ary << service_user_link('graph', to)
        else
          if to.id == auth.name
            name = self_feed_label
          else
            name = to.name
          end
          if entry.from_id != to.id
            name = 'DM:' + name
          end
          ary << link_to(h(name), link_user(to.id))
        end
        ary << lock_icon(to)
        ary.join
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
    if entry.tweet?
      content = twitter_content(entry)
      if ctx.tweets? and !entry.unread?
        content = span(content, 'archived')
      end
    elsif entry.buzz?
      content = buzz_content(entry)
      if ctx.buzz? and !entry.unread?
        content = span(content, 'archived')
      end
    else
      content = friendfeed_content(entry)
      if ctx.inbox and !entry.unread?
        content = span(content, 'archived')
      end
    end
    scan_media_from_link(entry)
    unless entry.view_medias.empty?
      content += "<br />\n"
      content += entry.view_medias.map { |uri| media_tag(entry, uri) }.join(' ')
      content += "<br />\n"
    end
    content
  end

  def friendfeed_content(entry)
    body = entry.body
    return '' unless body
    fold, content, links = escape_text(body, ctx.fold ? setting.text_folding_size : nil)
    entry.view_links = links
    if entry.via and entry.via.twitter?
      content = link_filter_twitter_username(content)
    end
    if fold
      msg = '(more)'
      content += link_to(h(msg), link_show(entry.id))
    end
    if link_entry?(entry)
      link = entry.link
      content += ' - ' + link_to(h(summary_uri(link)), link)
    end
    if with_attachment = attachment_content(entry)
      content += with_attachment
    end
    # entries from Hatena contains 'enclosure' but no title and link for now.
    with_media = media_content(entry)
    with_geo = geo_content(entry)
    ext = [with_media, with_geo].join(' ')
    unless ext.strip.empty?
      content += "<br />\n" + ext + "<br />\n"
    end
    content
  end

  def twitter_content(entry)
    body = entry.body
    return '' unless body
    fold, content, links = escape_text(body)
    entry.view_links = links
    content = filter_twitter_username(content, entry)
    with_media = media_content(entry)
    with_geo = geo_content(entry)
    ext = [with_media, with_geo].join(' ')
    unless ext.strip.empty?
      content += "<br />\n" + ext + "<br />\n"
    end
    content
  end

  def buzz_content(entry)
    body = entry.raw_body
    return '' unless body
    fold, content, links = escape_text(body, ctx.fold ? setting.text_folding_size : nil)
    entry.view_links = links
    content = link_filter_twitter_username(content)
    content.gsub!(/\n/, "<br />\n")
    if with_attachment = attachment_content(entry)
      content += with_attachment
    end
    if link_entry?(entry)
      link = entry.link
      content += ' - ' + link_to(h(summary_uri(link)), link)
    end
    with_media = media_content(entry)
    with_geo = geo_content(entry)
    ext = [with_media, with_geo].join(' ')
    unless ext.strip.empty?
      content += "<br />\n" + ext + "<br />\n"
    end
    content
  end

  def filter_buzz_comment(content)
    content.
      gsub(%r|<br\s*/>\s*(?:<br\s*/>\s*)+|m, '<br />'). # compact <br/>
      gsub(%r|</?b>|, '') # remove <b>
  end

  def geo_content(entry)
    if entry.geo and !entry.view_map
      point = GoogleMaps::Point.new(entry.body, entry.geo.lat, entry.geo.long)
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
      google_maps_link(point, entry, zoom, width, height)
    end
  end

  def link_entry?(entry)
    entry.link and
      !(entry.via and entry.via.twitter?) and
      !entry.view_links.include?(entry.link)
  end

  def scan_media_from_link(entry)
    if entry.thumbnails.empty? and entry.view_links and entry.view_medias.empty?
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

  def service_user_link(action, user)
    link_to(h(user.name), link_action(action, :feed => 'user', :user => user.id))
  end

  def author_link(entry, with_picture = true)
    return unless entry.from
    if entry.from.group?
      from = link_to(h(entry.from.name), link_list(:room => entry.from.id))
    elsif ctx.room_for
      # filter by group + user
      from = user(entry, link_list(:query => '', :room => ctx.room_for, :user => entry.from_id))
    elsif entry.tweet?
      from = service_user_link('tweets', entry.from)
    else
      from = user(entry)
    end
    ary = []
    if with_picture
      ary << author_picture(entry)
    end
    ary << from
    ary << lock_icon(entry.from)
    if link = twitter_retweeted_by(entry)
      ary << link
    end
    ary.join
  end

  def twitter_reply_to(entry)
    if url = entry.twitter_in_reply_to_url
      link_to(h(' reply to ' + entry.twitter_reply_to), url, :class => 'hlink')
    end
  end

  def twitter_retweeted_by(entry)
    if url = entry.twitter_retweeted_by_url
      link_to(h(' retweeted by ' + entry.twitter_retweeted_by), url, :class => 'hlink')
    end
  end

  def service_icon(entry)
    return unless entry.ff?
    if via = entry.via
      if via.service_icon_url
        if ctx.ff?
          link_to(service_icon_tag(via.service_icon_url, via.name, via.name),
                  search_opt(:action => :list, :query => '', :service => via.service_id))
        end
      end
    end
  end

  def comment_author_link(comment)
    unless comment.posted_with_entry?
      h('by ') + user(comment)
    end
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

  def attachment_content(entry)
    if !entry.files.empty?
      entry.files.map { |file|
        case file.type
        when 'article'
          str = "<br />" + link_to(inline_icon_tag(:url) + file.name, file.url)
        else
          label = file.type
          icon = image_tag(file.icon, :alt => h(label), :title => h(label), :size => '16x16')
          str = "<br />\n" + link_to(icon + h(file.name), file.url)
          str += h(" (#{file.size} bytes)") if file.size
        end
        str
      }.join(', ')
    end
  end

  def media_content(entry)
    medias = entry.thumbnails
    return nil if medias.nil? or medias.empty?
    if ctx.single?
      display = medias
    else
      display = medias[0, F2P::Config.medias_in_thread]
    end
    str = display.collect { |tb|
      link = tb.link
      label = '[media]'
      opt = {:alt => h(label), :title => h(label)}
      if tb.width and tb.height
        opt[:size] = image_size(tb.width, tb.height)
      else
        opt[:style] = image_max_style()
      end
      safe_content = media_tag(entry, tb.url || icon_url(:images), opt)
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

  def filter_twitter_username(common, entry)
    common.gsub(/@([a-zA-Z0-9_]+)/) {
      user = $1
      if user == entry.twitter_reply_to
        link = entry.twitter_in_reply_to_url
      else
        link = link_action('tweets', :feed => 'user', :user => user)
      end
      '@' + link_to(h(user), link, :class => 'twname')
    }
  end

  def link_filter_twitter_username(common)
    common.gsub(/@([a-zA-Z0-9_]+)/) {
      '@' + link_to($1, "http://twitter.com/#{$1}", :class => 'twname')
    }
  end

  URI_REGEXP = URI.regexp(['http', 'https'])
  def escape_text(content, fold_size = nil)
    str = ''
    fold_size ||= content.length
    org_size = 0
    m = nil
    links = []
    while content.match(URI_REGEXP)
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
        if ctx.tweets?
          link = link_to(h(m[0]), :action => :tweets, :query => m[0])
        else
          link = link_to(h(m[0]), search_opt(:action => :list, :query => m[0]))
        end
        ary << span(link, 'hashtag')
      else
        ary << h(m[0])
      end
      str = m.post_match
    end
    ary << h(str)
    ary.join
  end

  def via(entry_or_comment)
    label = 'from'
    if !entry_or_comment.respond_to?(:comments) or entry_or_comment.tweet? or entry_or_comment.graph?
      label = 'via'
    end
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
      icon = icon_tag(:liked) + h(likes.size.to_s)
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
      icon = inline_icon_tag(:liked)
      unless entry.tweet?
        size = entry.likes_size
        if size != likes.size
          icon += link_to(h(size.to_s), link_show(entry.id))
        end
        if !likes.empty?
          members = likes.collect { |like|
            if need_unread_mgmt? and like.unread?
              emphasize_as_unread(user(like))
            else
              user(like)
            end
          }.join(' ')
          icon += '(' + members + ')'
        end
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
        '<div class="comment-fold">' +
          fold_comment_link(comment, div_id) +
          '</div>'
      else
        date = comment_date(comment, true) unless comment.posted_with_entry?
        str = '<div class="comment-body">' +
          comment_icon(comment) + comment(comment)
        [str, comment_author_link(comment), via(comment), date, comment_link(comment)].join(' ') +
          '</div>'
      end
    }.join("\n")
    str + "</div>\n"
  end

  def updated(entry, compact)
    date(entry.modified, compact)
  end

  def emphasize_as_unread(str)
    span(str, 'inbox')
  end

  def published(entry, compact = false)
    str = date(entry.date_at, compact)
    if need_unread_mgmt? and entry.unread?
      str = emphasize_as_unread(str)
    end
    if entry.url
      link_to(str, entry.url, :class => 'hlink')
    else
      str
    end
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
    # TODO: already marked up in buzz...
    if comment.buzz?
      str = filter_buzz_comment(comment.body)
    else
      fold, str, links = escape_text(comment.body, ctx.fold ? setting.text_folding_size : nil)
      comment.view_links = links
      if fold
        msg = '(more)'
        str += link_to(h(msg), link_show(comment.entry.id))
      end
      if comment.entry and comment.entry.via and comment.entry.via.twitter?
        str = link_filter_twitter_username(str)
      end
    end
    if need_unread_mgmt? and !comment.unread?
      str = span(str, 'archived')
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

  def search_action
    if ctx.ff?
      action = 'list'
    elsif ctx.tweets?
      action = 'tweets'
    elsif ctx.buzz?
      action = 'buzz'
    elsif ctx.graph?
      action = 'graph'
    end
    { :controller => :entry, :action => action }
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
    return if ctx.direct_message? and !ctx.dm_to
    ary = []
    body = @body
    ary << hidden_field_tag('to_lines', '1')
    if ctx.user_for and ctx.user_for != auth.name
      if @feedinfo and @feedinfo.commands.include?('dm')
        ary << hidden_field_tag('to_0', ctx.user_for) + h(feed_name) + ': '
      elsif ctx.tweets? and !ctx.in_reply_to_screen_name and @profile and @profile.name != @service_user_screen_name
        ary << hidden_field_tag('to_0', @profile.name) + h(@profile.name) + ': '
      end
    elsif ctx.dm_to
      ary << hidden_field_tag('to_0', ctx.dm_to) + h(ctx.dm_to) + ': '
    end
    ary << hidden_field_tag('service_source', @service_source) if @service_source
    ary << hidden_field_tag('service_user', @service_user) if @service_user
    if ctx.in_reply_to_screen_name
      ary << hidden_field_tag('in_reply_to_status_id', ctx.in_reply_to_status_id)
      ary << hidden_field_tag('in_reply_to_screen_name', ctx.in_reply_to_screen_name)
      body ||= '@' + ctx.in_reply_to_screen_name + ' '
    end
    if ctx.room_for and @feedinfo.commands.include?('post')
      ary << hidden_field_tag('to_0', ctx.room_for) + h(feed_name) + ': '
    end
    case @service_source
    when 'twitter'
      ary << twitter_icon_tag
      if ctx.query and ctx.query[0] == ?#
        body ||= ' ' + ctx.query
      end
    when 'buzz'
      ary << buzz_icon_tag
    when 'graph'
      ary << facebook_icon_tag
    else
      ary << friendfeed_icon_tag
    end
    ary << text_field_tag('body', body, :placeholder => 'post')
    ary << submit_tag('post')
    # TODO: we can support rich buzz posting in the future.
    if ctx.ff?
      ary << write_new_link
    end
    ary.join
  end

  def post_comment_form(entry)
    if entry.commands.include?('comment')
      if entry.ff? and entry.via and setting.twitter_comment_hack and entry.via.twitter?
        default = entry.twitter_username
        unless default.empty?
          default = "@#{default} "
        end
      end
      ary = []
      ary << hidden_field_tag('service_source', @service_source) if @service_source
      ary << hidden_field_tag('service_user', @service_user) if @service_user
      ary << text_field_tag('body', default, :placeholder => 'comment')
      ary << submit_tag('post')
      ary.join
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
    if fold.fold_entries > 0
      msg = "(#{fold.fold_entries} more comments)"
    else
      msg = "(more comments)"
    end
    if ajax? and remote_update_id
      link_to_remote(msg, :update => remote_update_id, :url => link_action('comments_remote', :eid => fold.entry_id))
    else
      link_to(msg, link_show(fold.entry_id))
    end
  end

  # override
  def pinned_link(pin_label = 'Star')
    if @threads and @threads.pins and @threads.pins > 0
      pin_label += "(#{@threads.pins})"
    end
    link_to(h(pin_label), link_list(:label => 'pin'), accesskey('9'))
  end

  def write_new_link
    link_to(h('more'), link_action('new', :room => ctx.room_for))
  end

  # override
  def common_menu(*arg)
    [
      profile_link(auth.name),
      search_link,
      settings_link,
      logout_link,
      help_link,
      to_top_menu
    ].compact.join(' ')
  end

  def profile_text(profile)
    ary = []
    ary << link_to(profile_picture(profile), profile.profile_url)
    if ctx.tweets?
      ary << link_to(h(profile.name), link_action('tweets', :feed => 'user', :user => profile.name))
    elsif ctx.buzz?
      ary << link_to(h(profile.name), link_action('buzz', :feed => 'user', :user => profile.id))
    end
    ary << lock_icon(profile)
    ary << ' '
    ary << profile.display_name
    ary.join
  end

  def profile_link(id)
    if ctx.ff?
      menu_link(menu_label('profile'), :controller => :profile, :action => :show, :id => id)
    end
  end

  def search_link
    if ctx.ff?
      menu_link(menu_label('search'), search_opt(link_action('search')))
    end
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
    start = ctx.start || 0
    num = ctx.num || 0
    links = []
    if ctx.list? and !ctx.is_summary?
      key = accesskey('6')
      if ctx.tweets?
        links << menu_link(menu_label('show more...', '6'), {:action => 'tweets', :feed => ctx.feed, :user => ctx.user, :query => ctx.query, :num => num, :max_id => @threads.max_id}, key)
      elsif ctx.buzz?
        links << menu_link(menu_label('show more...', '6'), {:action => 'buzz', :feed => ctx.feed, :user => ctx.user, :num => num, :max_id => @buzz_c_tag}, key)
      elsif ctx.graph?
        links << menu_link(menu_label('show more...', '6'), {:action => 'graph', :feed => ctx.feed, :user => ctx.user, :num => num, :max_id => @threads.from_modified}, key)
      elsif ctx.pin?
        links << menu_link(menu_label('show more...', '6'), list_opt(ctx.link_opt(:start => @cont, :num => num)), key)
      elsif ctx.ff?
        links << menu_link(menu_label('show more...', '6'), list_opt(ctx.link_opt(:start => start + num, :num => num)), key)
      end
    end
    links.join(' ')
  end

  def find_show_entry(threads)
    if thread = threads.first
      thread.root
    end
  end

  def list_range_notation
    if ctx.start != 0
      page = (ctx.start / ctx.num) + 1
      h("(page #{page})")
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
      menu_link(h('>>>'), link_show(comment.entry.id))
    end
  end

  def post_comment_link(entry, opt = {})
    if entry.tweet?
      return if entry.service_user == entry.from_id
      tid = Entry.if_service_id(entry.id)
      if ctx.feed == 'direct'
        str = inline_menu_label(:dm, 'DM')
        link = list_opt(
          :dm_to => entry.from.name
        )
      else
        str = inline_menu_label(:reply, 'reply')
        link = list_opt(
          :in_reply_to_service_user => entry.service_user,
          :in_reply_to_screen_name => entry.from.name,
          :in_reply_to_status_id => tid
        )
      end
    elsif !entry.comments.empty? and !comment_inline?(entry)
      if entry.comments_size == 1
        str = ">>>#{entry.comments_size}"
      else
        str = ">>>#{entry.comments_size}"
      end
      str = latest(entry.modified_at, str)
      if need_unread_mgmt? and entry.unread?
        str = emphasize_as_unread(str)
      end
      link = link_show(entry.id)
    else
      str = h('>>>')
      link = link_show(entry.id)
    end
    menu_link(str, link)
  end

  def comment_date(comment, compact = true)
    str = date(comment.date, compact)
    if need_unread_mgmt? and comment.unread?
      str = emphasize_as_unread(str)
    end
    str
  end

  def delete_link(entry)
    if entry.commands.include?('delete')
      link_opt = {:eid => entry.id}
      if entry.service_source
        link_opt[:service_source] = entry.service_source
        link_opt[:service_user] = entry.service_user
      end
      menu_link(inline_menu_label(:delete, 'delete'), link_action('delete', link_opt), :confirm => 'Delete?')
    end
  end

  def undo_delete_link(id, comment)
    link_to(h('Deleted.  UNDO?'), link_action('undelete', :eid => id, :comment => comment), :confirm => 'Undo?')
  end

  def undo_add_link(id)
    if /\At_/ =~ id
      h('Tweet added.')
    else
      link_to(h('Added.  UNDO?'), link_action('delete', :eid => id), :confirm => 'Undo?')
    end
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
    label = entry.tweet? ? 'fav' : 'like'
    link_opt = {:eid => eid, :single => 1}
    unless entry.ff?
      link_opt[:service_source] = entry.service_source
      link_opt[:service_user] = entry.service_user
    end
    span_id = 'like_' + eid
    if entry.commands.include?('like')
      content = inline_menu_label(:like, label)
      link = link_action('like_remote', link_opt)
    elsif !entry.ff? or entry.likes.any? { |e| e.from_id == auth.name }
      content = inline_menu_label(:unlike, 'un-' + label)
      link = link_action('like_remote', link_opt.merge(:liked => 1))
    else
      content = nil
    end
    if content
      opt = {:update => span_id, :url => link}
      html_opt = {:class => 'menu-link'}
      link_to_remote(content, opt, html_opt)
    else
      ''
    end
  end

  def like_link_plain(entry)
    eid = entry.id
    label = entry.tweet? ? 'fav' : 'like'
    link_opt = {:eid => eid}
    unless entry.ff?
      link_opt[:service_source] = entry.service_source
      link_opt[:service_user] = entry.service_user
    end
    if entry.commands.include?('like')
      menu_link(inline_menu_label(:like, label), link_action('like', link_opt))
    elsif !entry.ff? or entry.likes.any? { |e| e.from_id == auth.name }
      menu_link(inline_menu_label(:unlike, 'un-' + label), link_action('unlike', link_opt))
    else
      ''
    end
  end

  def hide_link(entry)
    if entry.ff?
      link_opt = {:eid => entry.id}
      menu_link(inline_menu_label(:hide, 'hide'), link_action('hide', link_opt), :confirm => 'Hide?')
    elsif entry.buzz?
      link_opt = {:eid => entry.id}
      link_opt[:service_source] = entry.service_source
      link_opt[:service_user] = entry.service_user
      menu_link(inline_menu_label(:hide, 'mute'), link_action('hide', link_opt), :confirm => 'Mute?')
    end
  end

  def reshare_link(entry)
    if entry.ff? and (ctx.single? or entry.view_pinned)
      menu_link(inline_menu_label(:reshare, 'reshare'), link_action('reshare', :reshared_from => entry.id))
    end
  end

  def retweet_link(entry)
    if entry.commands.include?('retweet')
      link_opt = {:id => entry.id}
      unless entry.ff?
        link_opt[:service_source] = entry.service_source
        link_opt[:service_user] = entry.service_user
      end
      menu_link(inline_menu_label(:reshare, 'RT'), link_action('retweet', link_opt), :confirm => 'Retweet?')
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
