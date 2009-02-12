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
        if @user
          user = entry.nickname || entry.user_id
        end
        opt = {
          :controller => 'entry',
          :action => 'list',
          :user => u(user),
          :service => u(service_id)
        }
        link_to(h(name), opt)
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
      fold, str = escape_text(title, @entry_fold ? profile_text_folding_size : nil)
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
    str = ''
    if show_user
      str += user(entry)
    end
    if show_service and !@room
      str += '@' unless str.empty?
      str += service(entry)
    end
    str += ':' unless str.empty?
    str
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
    generator = GoogleMaps::URLGenerator.new(F2P::Config.google_maps_api_key)
    lat = point.lat
    long = point.long
    address = point.address
    tb = generator.staticmap_url(F2P::Config.google_maps_maptype, lat, long, :zoom => F2P::Config.google_maps_zoom, :width => F2P::Config.google_maps_width, :height => F2P::Config.google_maps_height)
    link = generator.link_url(lat, long, address)
    link_to(image_tag(tb, :alt => h(address), :size => image_size(F2P::Config.google_maps_width, F2P::Config.google_maps_height)), link)
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
    fold = fold_length(title, profile_text_folding_size - 3)
    if @entry_fold and entry.medias.empty? and fold != title
      link_content(fold + '...', entry.link, entry) +
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
    while content.match(URI.regexp)
      m = $~
      added, part = fold_concat(m.pre_match, fold_size - org_size)
      str += h(part)
      if added
        org_size += added
      else
        return true, str
      end
      uri = uri(m[0])
      added, part = fold_concat(m[0], fold_size - org_size)
      if uri.nil? or !uri.is_a?(URI::HTTP)
        str += h(part)
        if added
          org_size += added
        else
          return true, str
        end
      else
        if added
          str += link_to(h(m[0]), m[0])
          org_size += added
        else
          str += link_to(h(part), m[0])
          return true, str
        end
      end
      content = m.post_match
    end
    added, part = fold_concat(content, fold_size - org_size)
    str += h(part)
    unless added
      return true, str
    end
    return false, str
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
    me, rest = entry.likes.partition { |e| v(e, 'user', 'nickname') == @auth.name }
    likes = me + rest
    if !likes.empty?
      if compact and likes.size > F2P::Config.likes_in_page + 1
        msg = "... #{likes.size - F2P::Config.likes_in_page} more likes"
        icon_tag(:like) + likes[0, F2P::Config.likes_in_page].collect { |like| user(like) }.join(' ') +
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

  def comment(comment)
    fold, str = escape_text(comment.body, @entry_fold ? profile_text_folding_size : nil)
    if fold
      str += link_to(icon_tag(:more), :action => 'show', :id => u(comment.entry.id))
    end
    str
  end

  def search_form
    str = ''
    str += hidden_field_tag('user', @user) if @user
    str += hidden_field_tag('list', @list) if @list
    room = (@room != '*') ? @room : nil
    str += hidden_field_tag('room', room) if room
    str += hidden_field_tag('friends', @friends) if @friends
    if @service
      str += hidden_field_tag('service', @service)
    end
    str += text_field_tag('query', @query, :accesskey => '2') + submit_tag('search')
    str += ' ' + link_to(h('[search]'), search_opt)
    str
  end

  def post_entry_form
    str = ''
    room = (@room != '*') ? @room : nil
    if room
      str += hidden_field_tag('room', room) + h(room) + ': '
    end
    str += text_field_tag('body', nil, :accesskey => '2') + submit_tag('post')
    str += ' ' + link_to(h('[extended]'), :action => 'new', :room => u(room))
    str += ' ' + link_to(h('[search]'), search_opt)
    str
  end

  def post_comment_form
    text_field_tag('body', nil, :accesskey => '8') + submit_tag('post')
  end

  def fold_link(entry)
    msg = " (#{entry.fold_entries} more entries)"
    link_to(icon_tag(:more), list_opt(:action => 'list', :start => @start, :num => @num, :fold => 'no')) + h(msg)
  end

  def fold_comment_link(entry, comment)
    msg = " (#{comment.fold_entries} more comments)"
    link_to(icon_tag(:more), :action => 'show', :id => u(entry.id)) + h(msg)
  end

  def settings_link
    link_to(h('[settings]'), :controller => 'setting', :action => 'index')
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
      link_to(h(label), list_opt(:action => 'list', :user => u(user), :service => u(id)))
    }
  end

  def list_links
    arg = {
      :name => @auth.name,
      :remote_key => @auth.remote_key,
      :user => @auth.name
    }
    links_if_exists('lists: ', User.lists(arg)) { |e|
      label = "[#{v(e, 'name')}]"
      nickname = v(e, 'nickname')
      if @list == nickname
        h(label)
      else
        link_to(h(label), list_opt(:action => 'list', :list => u(nickname)))
      end
    }
  end

  def room_links(user)
    arg = {
      :name => @auth.name,
      :remote_key => @auth.remote_key,
      :user => user
    }
    links_if_exists('rooms: ', User.rooms(arg)) { |e|
      label = "[#{v(e, 'name')}]"
      nickname = v(e, 'nickname')
      link_to(h(label), list_opt(:action => 'list', :room => u(nickname)))
    }
  end

  def user_links(user)
    arg = {
      :name => @auth.name,
      :remote_key => @auth.remote_key,
      :user => user
    }
    users = User.subscriptions(arg)
    links_if_exists("(#{users.size} subscriptions) ", users) { |e|
      label = "[#{v(e, 'name')}]"
      nickname = v(e, 'nickname')
      if nickname
        link_to(h(label), list_opt(:action => 'list', :user => u(nickname)))
      end
    }
  end

  def member_links(room)
    arg = {
      :name => @auth.name,
      :remote_key => @auth.remote_key,
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

  def page_links
    no_page = @start.nil?
    links = []
    unless no_page
      links << menu_link('[<]', list_opt(:action => 'list', :start => @start - @num, :num => @num), :accesskey => '4') {
        @start - @num >= 0
      }
    end
    links << menu_link('[home]', :action => 'list')
    if @user and @user != @auth.name
      links << menu_link('[friends]', :action => 'list', :friends => @user) {
        !@friends
      }
    end
    links << menu_link('[lists]', :action => 'list', :list => 'favorite') {
      !@list
    }
    links << menu_link('[rooms]', :action => 'list', :room => '*') {
      !(@user and @auth.name != @user) and @room != '*'
    }
    links << menu_link('[likes]', :action => 'list', :likes => 'only', :user => @user) {
      @likes != 'only'
    }
    if @post and @user
      links << menu_link('[subscriptions]', '#subscriptions')
    end
    if @room and @room != '*'
      links << menu_link('[members]', '#members')
    end
    unless no_page
      links << menu_link('[>]', list_opt(:action => 'list', :start => @start + @num, :num => @num), :accesskey => '6')
    end
    links.join(' ')
  end

  def menu_link(label, opt, html_opt = {}, &block)
    if block.nil? or block.call
      link_to(h(label), opt, html_opt)
    else
      h(label)
    end
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

  def delete_comment_link(comment)
    unless @compact
      cid = v(comment, 'id')
      name = v(comment, 'user', 'nickname')
      if name == @auth.name or @auth.name == comment.entry.nickname
        link_to(icon_tag(:delete), {:action => 'delete', :id => u(comment.entry.id), :comment => u(cid)}, :confirm => 'Are you sure?')
      end
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
      :list => @list,
      :room => @room,
      :friends => @friends,
      :likes => @likes,
      :service => @service,
      :fold => @entry_fold ? nil : 'no'
    }.merge(hash)
  end

  def search_opt(hash = {})
    search_opt = list_opt.merge(:action => 'search')
    search_opt[:friends] = 'me' if @home
    search_opt[:room] = nil if search_opt[:room] == '*'
    search_opt
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
    if items.size > profile_entries_in_thread
      result = []
      result << items.first
      result << Fold.new(items.size - (profile_entries_in_thread - 1))
      last_size = profile_entries_in_thread - 2
      result += items[-last_size, last_size]
      result
    else
      items.dup
    end
  end
end
