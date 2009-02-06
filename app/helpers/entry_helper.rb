module EntryHelper
  FF_ICON_URL_BASE = 'http://friendfeed.com/static/images/'
  ICON_NAME = {
    'like' => 'smile.png',
    'comment' => 'comment-friend.png',
    'comment_add' => 'email-pencil.png',
    'delete' => 'delete-g.png',
    'more' => 'add.png',
    # not used
    'link' => 'world-link.png',
    'check' => 'check.png',
    'check_disabled' => 'check-disabled.png',
    'comment_lighter' => 'comment-lighter.png',
  }

  COMMENT_MAXLEN = 140
  TUMBLR_TEXT_MAXLEN = 140
  LIKES_THRESHOLD = 3
  FOLD_THRESHOLD = 5
  GOOGLEMAP_MAPTYPE = 'mobile'
  GOOGLEMAP_ZOOM = 13
  GOOGLEMAP_WIDTH = 160
  GOOGLEMAP_HEIGHT = 80

  def icon(entry)
    service_icon(v(entry, 'service'), entry.link)
  end

  def service(entry)
    service_id = entry.service_id
    if service_id == 'internal' and entry.room
      room(entry.room)
    else
      name = v(entry, 'service', 'name')
      if name and service_id
        link_to(h(name), :controller => 'entry', :action => 'list', :user => u(entry.nickname || entry.user_id), :service => u(service_id))
      end
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
    link = entry.link
    if link and with_link?(v(entry, 'service'))
      content = link_content(title, link, entry)
    else
      content = q(escape_with_link(title))
    end
    if !entry.medias.empty?
      # entries from Hatena contains 'enclosure' but no title and link for now.
      with_media = content_with_media(entry)
      content += "<br/>\n" + with_media unless with_media.empty?
    end
    content
  end

  def link_content(title, link, entry)
    if with_domain_mark?(link, entry)
      q(h(title) + ' ' + link_to(h("(#{URI.parse(link).host})"), link))
    else
      q(link_to(h(title), link))
    end
  end

  def uri(str)
    URI.parse(str) rescue nil
  end

  def with_domain_mark?(link, entry)
    link_url = uri(link)
    profile_url = uri(v(entry, 'service', 'profileUrl'))
    if profile_url and link_url
      (profile_url.host.downcase != link_url.host.downcase) or
        ['blog', 'feed'].include?(entry.service_id)
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
          safe_content = image_tag(tb_url,
            :alt => h(title), :size => image_size(tb_width, tb_height))
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

  def google_maps_link(point)
    generator = GoogleMaps::URLGenerator.new(FFP::Config.google_maps_api_key)
    lat = point.lat
    long = point.long
    address = point.address
    tb = generator.staticmap_url(GOOGLEMAP_MAPTYPE, lat, long, :zoom => GOOGLEMAP_ZOOM, :width => GOOGLEMAP_WIDTH, :height => GOOGLEMAP_HEIGHT)
    link = generator.link_url(lat, long, address)
    link_to(image_tag(tb, :alt => h(address), :size => image_size(GOOGLEMAP_WIDTH, GOOGLEMAP_HEIGHT)), link)
  end

  def brightkite_content(common, entry)
    lat = v(entry, 'geo', 'lat')
    long = v(entry, 'geo', 'long')
    if lat and long
      point = GoogleMaps::Point.new(entry.title, lat, long)
      content = google_maps_link(point)
      if !entry.medias.empty?
        common + ' ' + content
      else
        common + "<br/>\n" + content
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
    link = entry.link
    fold = fold_length(title, TUMBLR_TEXT_MAXLEN - 3)
    if @entry_fold and entry.medias.empty? and fold != title
      link_content(fold + '...', link, entry)
    else
      common
    end
  end

  def escape_with_link(content)
    if content
      str = ''
      m = nil
      while content.match(URI.regexp)
        m = $~
        str += h(m.pre_match)
        uri = uri(m[0])
        # trailing '...' means folding.
        if uri.nil? or !uri.is_a?(URI::HTTP) or m[0][-3, 3] == '...'
          str += m[0]
        else
          str += link_to(h(m[0]), m[0])
        end
        content = m.post_match
      end
      str += h(content)
      str
    end
  end

  def via(entry)
    super(v(entry, 'via'))
  end

  def likes(entry, compact)
    me, rest = entry.likes.partition { |e| v(e, 'user', 'nickname') == @auth.name }
    likes = me + rest
    if !likes.empty?
      if compact and likes.size > LIKES_THRESHOLD + 1
        msg = "... #{likes.size - LIKES_THRESHOLD} more likes"
        icon_tag(:like) + likes[0, LIKES_THRESHOLD].collect { |like| user(like) }.join(' ') +
          ' ' + link_to(h(msg), :action => 'show', :id => u(entry.id))
      else
        icon_tag(:like) + likes.collect { |like| user(like) }.join(' ')
      end
    end
  end

  def updated(entry, compact)
    date(entry.thread_date, compact)
  end

  def published(entry, compact)
    published = v(entry, 'published')
    date(published, compact)
  end

  def user(entry)
    super(v(entry, 'user'))
  end

  def icon_tag(name, alt = nil)
    name = name.to_s
    url = FF_ICON_URL_BASE + ICON_NAME[name]
    image_tag(url, :alt => alt || name)
  end

  def comment(eid, comment)
    body = v(comment, 'body')
    if @entry_fold
      fold = fold_length(body, COMMENT_MAXLEN - 3)
      if body != fold
        return escape_with_link(fold + '...') + link_to(icon_tag(:more), :action => 'show', :id => u(eid))
      end
    end
    escape_with_link(body)
  end

  def search_form
    str = ''
    room = (@room != '*') ? @room : nil
    if room
      str += hidden_field_tag('room', room)
    end
    if @user
      str += hidden_field_tag('user', @user)
    end
    if @service
      str += hidden_field_tag('service', @service)
    end
    str += text_field_tag('query', @query) + submit_tag('search')
    str += ' ' + link_to(h('[search]'), list_opt.merge(:action => 'search'))
    str
  end

  def post_entry_form
    str = ''
    room = (@room != '*') ? @room : nil
    if room
      str += hidden_field_tag('room', room) + h(room) + ': '
    end
    str += text_field_tag('body') + submit_tag('post')
    str += ' ' + link_to(h('[extended]'), :action => 'new', :room => u(room))
    search_opt = list_opt.merge(:action => 'search')
    search_opt[:friends] = 'me' if @home
    search_opt[:room] = nil if search_opt[:room] == '*'
    str += ' ' + link_to(h('[search]'), search_opt)
    str
  end

  def post_comment_form
    text_field_tag('body') + submit_tag('post')
  end

  def fold_link(entry)
    msg = " (#{entry.fold_entries} more entries)"
    link_to(icon_tag(:more), list_opt(:action => 'list', :start => @start, :num => @num, :fold => 'no')) + h(msg)
  end

  def fold_comment_link(entry, comment)
    msg = " (#{comment.fold_entries} more comments)"
    link_to(icon_tag(:more), :action => 'show', :id => u(entry.id)) + h(msg)
  end

  def logout_link
    link_to(h('[logout]'), :controller => 'login', :action => 'clear')
  end

  def service_links(user)
    arg = {
      :name => @auth.name,
      :remote_key => @auth.remote_key,
      :user => user
    }
    map = User.services(arg).inject({}) { |r, e|
      r[v(e, 'id')] = v(e, 'name')
      r
    }
    links_if_exists('services: ', map.to_a.sort_by { |k, v| k }) { |id, name|
      label = "[#{name}]"
      link_to(h(label), list_opt(:action => 'list', :user => user, :service => id))
    }
  end

  def room_links(user)
    arg = {
      :name => @auth.name,
      :remote_key => @auth.remote_key,
      :user => user
    }
    links_if_exists('rooms: ', User.rooms(arg)) { |room|
      label = "[#{v(room, 'name')}]"
      nickname = v(room, 'nickname')
      link_to(h(label), list_opt(:action => 'list', :room => nickname))
    }
  end

  def links_if_exists(label, enum, &block)
    str = enum.collect { |v| yield(v) }.join(' ')
    str = h(label) + str unless str.empty?
    str
  end

  def page_links
    no_page = @start.nil?
    links = []
    label = '[<]'
    unless no_page
      if @start - @num >= 0
        links << link_to(h(label), list_opt(:action => 'list', :start => @start - @num, :num => @num))
      else
        links << h(label)
      end
    end
    label = '[home]'
    links << link_to(h(label), :action => 'list')
    if @user and @user != @auth.name
      label = '[friends]'
      if @friends
        links << h(label)
      else
        links << link_to(h(label), :action => 'list', :friends => @user)
      end
    end
    label = '[rooms]'
    if (@user and @auth.name != @user) or @room == '*'
      links << h(label)
    else
      links << link_to(h(label), :action => 'list', :room => '*')
    end
    label = '[likes]'
    if @likes == 'only'
      links << h(label)
    else
      links << link_to(h(label), :action => 'list', :likes => 'only', :user => @user)
    end
    label = '[>]'
    unless no_page
      links << link_to(h(label), list_opt(:action => 'list', :start => @start + @num, :num => @num))
    end
    links.join(' ')
  end

  def post_comment_link(entry)
    link_to(icon_tag(:comment_add, 'comment'), :action => 'show', :id => u(entry.id))
  end

  def delete_link(entry)
    if entry.nickname == @auth.name
      link_to(icon_tag(:delete), {:action => 'delete', :id => u(entry.id)}, :confirm => 'Are you sure?')
    end
  end

  def undelete_link(id, comment)
    link_to(h('Deleted.  UNDO?'), :action => 'undelete', :id => u(id), :comment => u(comment))
  end

  def delete_comment_link(entry, comment)
    cid = v(comment, 'id')
    name = v(comment, 'user', 'nickname')
    if name == @auth.name or @auth.name == entry.nickname
      link_to(icon_tag(:delete), {:action => 'delete', :id => u(entry.id), :comment => u(cid)}, :confirm => 'Are you sure?')
    end
  end

  def like_link(entry)
    if entry.nickname != @auth.name
      if entry.likes.find { |like| v(like, 'user', 'nickname') == @auth.name }
        link_to(h('[un-like]'), :action => 'unlike', :id => u(entry.id))
      else
        link_to(h('[like]'), :action => 'like', :id => u(entry.id))
      end
    end
  end

  def list_opt(hash = {})
    {
      :query => @query,
      :user => @user,
      :room => @room,
      :friends => @friends,
      :likes => @likes,
      :service => @service
    }.merge(hash)
  end

  class Fold < Hash
    attr_accessor :fold_entries

    def initialize(fold_entries)
      super()
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
    if @entry_fold
      fold_items(entries)
    else
      entries.dup
    end
  end

  def fold_comments(comments)
    if @compact
      fold_items(comments)
    else
      comments.dup
    end
  end

  def fold_items(items)
    if items.size > FOLD_THRESHOLD
      result = []
      result << items.first
      result << Fold.new(items.size - (FOLD_THRESHOLD - 1))
      last_size = FOLD_THRESHOLD - 2
      result += items[-last_size, last_size]
      result
    else
      items.dup
    end
  end
end
