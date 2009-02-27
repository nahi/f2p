require 'google_maps'


class EntryController < ApplicationController
  before_filter :login_required
  after_filter :strip_heading_spaces
  after_filter :compress

  class EntryContext
    attr_accessor :eid
    attr_accessor :query
    attr_accessor :user
    attr_accessor :list
    attr_accessor :room
    attr_accessor :friends
    attr_accessor :like
    attr_accessor :link
    attr_accessor :service
    attr_accessor :start
    attr_accessor :num
    attr_accessor :fold
    attr_accessor :updated
    attr_accessor :home

    def initialize(auth)
      @auth = auth
      @viewname = nil
      @eid = @query = @user = @list = @room = @friends = @like = @link = @service = @start = @num = nil
      @fold = false
      @updated = false
      @home = true
      @param = nil
    end

    def viewname=(viewname)
      @viewname = viewname
    end

    def viewname
      if @eid
        'entry'
      elsif @query
        'search results'
      elsif @like == 'likes'
        "entries #{@user || @auth.name} likes"
      elsif @like == 'liked'
        "#{@user || @auth.name}'s liked entries"
      elsif @user
        "#{@user}'s entries"
      elsif @friends
        "#{@friends}'s friends entries"
      elsif @list
        "'#{@list}' entries"
      elsif @room
        if @room == '*'
          'rooms entries'
        else
          "'#{@room}' entries"
        end
      elsif @link
        'related entries'
      elsif @updated
        'updated entries'
      else
        'home entries'
      end
    end

    def parse(param, setting)
      return unless param
      @param = param
      @eid = param(:id)
      @query = param(:query)
      @user = param(:user)
      @list = param(:list)
      @room = param(:room)
      @friends = param(:friends)
      @like = param(:like)
      @link = param(:link)
      @service = param(:service)
      @start = (param(:start) || '0').to_i
      if param(:num)
        @num = param(:num).to_i
      else
        @num = setting.entries_in_page
      end
      @fold = (!@user and !@service and !@link and param(:fold) != 'no')
      @updated = false
      @home = !(@query or @like or @user or @friends or @list or @room or @link)
    end

    def find_opt
      opt = {
        :auth => @auth,
        :start => @start,
        :num => @num,
        :service => @service
      }
      if @eid
        {:auth => @auth, :id => @eid}
      elsif @query
        opt.merge(:query => @query, :user => @user, :room => @room, :friends => @friends, :service => @service)
      elsif @like
        opt.merge(:like => @like, :user => @user || @auth.name)
      elsif @user
        opt.merge(:user => @user)
      elsif @friends
        opt.merge(:friends => @friends, :merge_service => true)
      elsif @list
        opt.merge(:list => @list, :merge_service => true)
      elsif @room
        opt.merge(:room => @room, :merge_service => true)
      elsif @link
        opt.merge(:link => @link, :merge_service => true)
      elsif @updated
        opt.merge(:updated => true, :merge_service => true)
      else
        opt.merge(:merge_service => true)
      end
    end

    def reset_pagination(setting)
      @eid = nil
      @start = 0
      @num = setting.entries_in_page
    end

    def reset_for_new
      # keep @room
      @eid = @query = @user = @list = @friends = @like = @link = @service = nil
      @fold = true
    end

    def list_opt
      {
        :query => @query,
        :user => @user,
        :list => @list,
        :room => @room,
        :friends => @friends,
        :like => @like,
        :link => @link,
        :service => @service,
        :fold => @fold ? nil : 'no'
      }
    end

    def room_id
      (@room != '*') ? @room : nil
    end

    def redirect_to
      if @eid
        action = 'show'
      elsif @updated
        action = 'updated'
      else
        action = 'list'
      end
      {:action => action}
    end

  private

    def param(key)
      v = @param[key]
      (v and v.respond_to?(:empty?) and v.empty?) ? nil : v
    end
  end

  verify :only => :list,
          :method => [:get, :post],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'list'}

  def list
    @ctx = restore_ctx { |ctx|
      ctx.parse(params, @setting)
    }
    @entries = EntryThread.find(@ctx.find_opt) || []
  end

  def index
    redirect_to_list
  end

  verify :only => :updated,
          :method => [:get, :post],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'list'}

  def updated
    @ctx = restore_ctx { |ctx|
      if param(:num)
        ctx.num = param(:num).to_i
      else
        ctx.num = @setting.entries_in_page
      end
      ctx.updated = true
    }
    store = session[:checked] ||= {}
    unless flash[:redirect]
      EntryThread.update_checked_modified(@auth, store)
      store = session[:checked] = {}
    end
    @entries = EntryThread.find(@ctx.find_opt) || []
    @entries.each do |t|
      t.entries.each do |e|
        store[e.id] = e[EntryThread::MODEL_LAST_MODIFIED_TAG]
      end
    end
    render :action => 'list'
  end

  verify :only => :show,
          :method => :get,
          :params => [:id],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'list'}

  def show
    @ctx = EntryContext.new(@auth)
    @ctx.eid = param(:id)
    @ctx.home = false
    @entries = EntryThread.find(@ctx.find_opt) || []
    render :action => 'list'
  end

  def new
    @ctx = EntryContext.new(@auth)
    @ctx.viewname = 'post new entry'
    @ctx.room = param(:room)
    @body = param(:body)
    @link = param(:link)
    @title = param(:title)
    @lat = param(:lat)
    @long = param(:long)
    @address = param(:address)
    @placemark = nil
    if @title
      geocoder = GoogleMaps::GeocodingJpGeocoder.new(http_client)
      @placemark = geocoder.search(@title)
      if @placemark and !@placemark.ambiguous?
        @address = @placemark.address
        @lat = @placemark.lat
        @long = @placemark.long
      end
    end
  end

  def reshare
    @ctx = EntryContext.new(@auth)
    @ctx.viewname = 'reshare entry'
    @ctx.room = param(:room)
    eid = param(:eid)
    opt = create_opt(:id => eid)
    t = EntryThread.find(opt).first
    if t.nil?
      redirect_to_list
      return
    end
    entry = t.root
    if entry.nil?
      redirect_to_list
      return
    end
    @link = entry.link
    @link_title = entry.title
  end

  def search
    @ctx = EntryContext.new(@auth)
    @ctx.viewname = 'search entries'
    @ctx.parse(params, @setting)
  end

  verify :only => :add,
          :method => :post,
          :params => [:body],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'list'}

  def add
    @body = param(:body)
    link_title = param(:link_title)
    @link = param(:link)
    @room = param(:room)
    file = param(:file)
    @lat = param(:lat)
    @long = param(:long)
    @title = param(:title)
    @address = param(:address)
    opt = create_opt(:room => @room)
    if @lat and @long and @address
      generator = GoogleMaps::URLGenerator.new
      image_url = generator.staticmap_url(F2P::Config.google_maps_maptype, @lat, @long, :zoom => F2P::Config.google_maps_zoom, :width => F2P::Config.google_maps_width, :height => F2P::Config.google_maps_height)
      image_link = generator.link_url(@lat, @long, @address)
      (opt[:images] ||= []) << [image_url, image_link]
      @body += " ([map] #{@address})"
    end
    if @link
      link_title ||= capture_title(@link)
      opt[:body] = link_title
      opt[:link] = @link
      opt[:comment] = @body
    elsif @body
      opt[:body] = @body
    end
    if file
      if !file.content_type or /\Aimage\//i !~ file.content_type
        render :action => 'new'
        return
      end
      (opt[:files] ||= []) << [file]
    end
    unless opt[:body]
      render :action => 'new'
      return
    end
    Entry.create(opt)
    flash[:keep_ctx] = true
    if session[:ctx]
      session[:ctx].reset_for_new
    end
    redirect_to_list
  end

  verify :only => :delete,
          :method => :get,
          :params => [:id],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'list'}

  def delete
    id = param(:id)
    comment = param(:comment)
    do_delete(id, comment, false)
    flash[:deleted_id] = id
    flash[:deleted_comment] = comment
    flash[:keep_ctx] = true
    redirect_to_list
  end

  verify :only => :undelete,
          :method => :get,
          :params => [:id],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'list'}

  def undelete
    id = param(:id)
    comment = param(:comment)
    do_delete(id, comment, true)
    flash[:keep_ctx] = true
    redirect_to_list
  end

  verify :only => :add_comment,
          :method => :post,
          :params => [:id, :body],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'list'}

  def add_comment
    id = param(:id)
    body = param(:body)
    if id and body
      Entry.add_comment(create_opt(:id => id, :body => body))
    end
    flash[:keep_ctx] = true
    redirect_to_list
  end

  verify :only => :like,
          :method => :get,
          :params => [:id],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'list'}

  def like
    id = param(:id)
    if id
      Entry.add_like(create_opt(:id => id))
    end
    flash[:keep_ctx] = true
    redirect_to_list
  end

  verify :only => :unlike,
          :method => :get,
          :params => [:id],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'list'}

  def unlike
    id = param(:id)
    if id
      Entry.delete_like(create_opt(:id => id))
    end
    flash[:keep_ctx] = true
    redirect_to_list
  end

private

  def capture_title(url)
    begin
      buf = ''
      http_client.get_content(url) do |str|
        buf += str.tr("\r\n", '')
        if match = buf.match(/<title[^>]*>([^<]*)</i)
          return NKF.nkf('-wm0', match.captures[0])
        end
      end
    rescue Exception
      # ignore
    end
    '(unknown)'
  end

  def create_opt(hash = {})
    {
      :auth => @auth
    }.merge(hash)
  end

  def do_delete(id, comment = nil, undelete = false)
    if comment and !comment.empty?
      Entry.delete_comment(create_opt(:id => id, :comment => comment, :undelete => undelete))
    else
      Entry.delete(create_opt(:id => id, :undelete => undelete))
    end
  end

  def restore_ctx
    if flash[:keep_ctx] and session[:ctx]
      ctx = session[:ctx]
      ctx.reset_pagination(@setting)
    else
      ctx = EntryContext.new(@auth)
      yield(ctx)
      session[:ctx] = ctx
    end
    ctx
  end

  def redirect_to_list
    flash[:redirect] = true
    if ctx = @ctx || session[:ctx]
      redirect_to ctx.redirect_to
    else
      redirect_to :action => 'list'
    end
  end
end
