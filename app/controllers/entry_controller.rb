require 'google_maps'


class EntryController < ApplicationController
  before_filter :login_required
  after_filter :strip_heading_spaces
  after_filter :compress

  def initialize
    super
    @viewname = 'entries'
  end

  verify :only => :list,
          :method => [:get, :post],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'list'}

  def list
    @viewname = 'entries'
    @eid = nil
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
      @num = @setting.entries_in_page
    end
    @fold = (!@user and !@service and !@link and param(:fold) != 'no')
    @home = false
    opt = create_opt(
      :start => @start,
      :num => @num,
      :service => @service
    )
    if @query
      @entries = EntryThread.find(opt.merge(:query => @query, :user => @user, :room => @room, :friends => @friends, :service => @service))
    elsif @like
      user = @user || @auth.name
      @entries = EntryThread.find(opt.merge(:like => @like, :user => user))
    elsif @user
      @entries = EntryThread.find(opt.merge(:user => @user))
    elsif @friends
      @entries = EntryThread.find(opt.merge(:friends => @friends, :merge_service => true))
    elsif @list
      @entries = EntryThread.find(opt.merge(:list => @list, :merge_service => true))
    elsif @room
      @entries = EntryThread.find(opt.merge(:room => @room, :merge_service => true))
    elsif @link
      @entries = EntryThread.find(opt.merge(:link => @link, :merge_service => true))
    else
      @home = true
      @entries = EntryThread.find(opt.merge(:merge_service => true))
    end
    @updated = false
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
    @viewname = 'updated entries'
    @eid = nil
    @query = nil
    @user = nil
    @list = nil
    @room = nil
    @friends = nil
    @like = nil
    @link = nil
    @service = nil
    @start = nil
    if param(:num)
      @num = param(:num).to_i
    else
      @num = @setting.entries_in_page
    end
    @fold = false
    @home = true
    opt = create_opt(
      :start => @start,
      :num => @num
    )
    @entries = EntryThread.find(opt.merge(:updated => true, :merge_service => true))
    @updated = true
    @entries ||= []
    render :action => 'list'
  end

  verify :only => :show,
          :method => :get,
          :params => [:id],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'list'}

  def show
    @viewname = 'entry'
    @eid = param(:id)
    @query = nil
    @user = nil
    @list = nil
    @room = nil
    @friends = nil
    @like = nil
    @link = nil
    @service = nil
    @start = nil
    @num = nil
    @fold = false
    @home = false
    opt = create_opt(:id => @eid)
    @entries = EntryThread.find(opt)
    @updated = false
    @entries ||= []
    render :action => 'list'
  end

  def new
    @viewname = 'post new entry'
    @body = param(:body)
    @link = param(:link)
    @room = param(:room)
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
    @viewname = 'reshare entry'
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
    @viewname = 'search entries'
    @query = param(:query)
    @user = param(:user)
    @room = param(:room)
    @friends = param(:friends)
    @service = param(:service)
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
