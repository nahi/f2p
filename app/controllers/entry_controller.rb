require 'google_maps'


class EntryController < ApplicationController
  before_filter :login_required
  after_filter :strip_heading_spaces
  after_filter :compress

  class EntryContext
    attr_accessor :viewname
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

    def initialize
      @viewname = 'entries'
      @eid = @query = @user = @list = @room = @friends = @like = @link = @service = @start = @num = nil
      @fold = false
      @updated = false
      @home = true
      @param = nil
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

    def opt
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
    @ctx = EntryContext.new
    @ctx.parse(params, @setting)
    opt = create_opt(
      :start => @ctx.start,
      :num => @ctx.num,
      :service => @ctx.service
    )
    if @ctx.query
      @entries = EntryThread.find(opt.merge(:query => @ctx.query, :user => @ctx.user, :room => @ctx.room, :friends => @ctx.friends, :service => @ctx.service))
    elsif @ctx.like
      user = @ctx.user || @auth.name
      @entries = EntryThread.find(opt.merge(:like => @ctx.like, :user => user))
    elsif @ctx.user
      @entries = EntryThread.find(opt.merge(:user => @ctx.user))
    elsif @ctx.friends
      @entries = EntryThread.find(opt.merge(:friends => @ctx.friends, :merge_service => true))
    elsif @ctx.list
      @entries = EntryThread.find(opt.merge(:list => @ctx.list, :merge_service => true))
    elsif @ctx.room
      @entries = EntryThread.find(opt.merge(:room => @ctx.room, :merge_service => true))
    elsif @ctx.link
      @entries = EntryThread.find(opt.merge(:link => @ctx.link, :merge_service => true))
    else
      @entries = EntryThread.find(opt.merge(:merge_service => true))
    end
    @entries ||= []
  end

  def index
    redirect_to :action => 'list'
  end

  verify :only => :updated,
          :method => [:get, :post],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'list'}

  def updated
    @ctx = EntryContext.new
    @ctx.viewname = 'updated entries'
    if param(:num)
      @ctx.num = param(:num).to_i
    else
      @ctx.num = @setting.entries_in_page
    end
    @ctx.updated = true
    opt = create_opt(
      :start => @ctx.start,
      :num => @ctx.num
    )
    @entries = EntryThread.find(opt.merge(:updated => true, :merge_service => true))
    @entries ||= []
    render :action => 'list'
  end

  verify :only => :show,
          :method => :get,
          :params => [:id],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'list'}

  def show
    @ctx = EntryContext.new
    @ctx.viewname = 'entry'
    @ctx.eid = param(:id)
    @ctx.home = false
    opt = create_opt(:id => @ctx.eid)
    @entries = EntryThread.find(opt)
    @entries ||= []
    render :action => 'list'
  end

  def new
    @ctx = EntryContext.new
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
    @ctx = EntryContext.new
    @ctx.viewname = 'reshare entry'
    @ctx.room = param(:room)
    eid = param(:eid)
    opt = create_opt(:id => eid)
    t = EntryThread.find(opt).first
    if t.nil?
      redirect_to :action => 'list'
      return
    end
    entry = t.root
    if entry.nil?
      redirect_to :action => 'list'
      return
    end
    @link = entry.link
    @link_title = entry.title
  end

  def search
    @ctx = EntryContext.new
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
    back_to = param(:back_to) || 'list'
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
    redirect_to :action => back_to, :room => @room
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
    redirect_to :action => 'list'
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
    redirect_to :action => 'list'
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
    redirect_to :action => 'list'
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
    redirect_to :action => 'list'
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
    redirect_to :action => 'list'
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
end
