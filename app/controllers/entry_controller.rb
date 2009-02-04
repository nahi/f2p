require 'google_maps'


class EntryController < ApplicationController
  before_filter :login_required

  NUM_DEFAULT = '30'

  class DebugLogger
    def initialize(logger)
      @logger = logger
    end

    def <<(str)
      @logger.info(str)
    end
  end

  verify :only => :list,
          :method => [:get, :post],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'list'}

  def list
    @eid = nil
    @query = param(:query)
    @user = param(:user)
    @room = param(:room)
    @friends = param(:friends)
    @likes = param(:likes)
    @service = param(:service)
    @start = (param(:start) || '0').to_i
    @num = (param(:num) || NUM_DEFAULT).to_i
    @entry_fold = (!@user and !@service and param(:fold) != 'no')
    opt = {
      :name => @auth.name,
      :remote_key => @auth.remote_key,
      :start => @start,
      :num => @num,
      :service => @service
    }
    logger.info([:query, @query].inspect)
    if @query
      @entries = EntryThread.find(opt.merge(:query => @query, :user => @user, :room => @room, :friends => @friends, :service => @service))
    elsif @user
      @entries = EntryThread.find(opt.merge(:user => @user))
    elsif @friends
      @entries = EntryThread.find(opt.merge(:friends => @friends))
    elsif @room
      @entries = EntryThread.find(opt.merge(:room => @room))
    elsif @likes == 'only'
      @entries = EntryThread.find(opt.merge(:likes => true))
    else
      @friends = @auth.name # for search by myself
      @entries = EntryThread.find(opt.merge(:merge_service => true))
    end
    @compact = true
    @search = !!@query
    @post = !@search
    @post_comment = false
    @entries ||= []
  end

  def index
    redirect_to :action => 'list'
  end

  verify :only => :show,
          :method => :get,
          :params => [:id],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'list'}

  def show
    @eid = param(:id)
    @query = nil
    @user = nil
    @room = nil
    @friends = nil
    @likes = nil
    @service = nil
    @start = 0
    @num = 0
    @entry_fold = false
    opt = {
      :name => @auth.name,
      :remote_key => @auth.remote_key,
      :id => @eid
    }
    @entries = EntryThread.find(opt)
    @compact = false
    @search = false
    @post = false
    @post_comment = true
    @entries ||= []
    render :action => 'list'
  end

  def new
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

  def search
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
    body = param(:body)
    link = param(:link)
    room = param(:room)
    lat = param(:lat)
    long = param(:long)
    title = param(:title)
    address = param(:address)
    images = nil
    if lat and long and address
      generator = GoogleMaps::URLGenerator.new
      maptype = 'mobile'
      zoom = 13
      width = 160
      height = 80
      image_url = generator.staticmap_url(maptype, lat, long, :zoom => zoom, :width => width, :height => height)
      image_link = generator.link_url(lat, long, address)
      images = [[image_url, image_link]]
    end
    if link
      title = capture_title(link)
      ff_client.post(@auth.name, @auth.remote_key, title, link, body, nil, nil, room)
    elsif body
      ff_client.post(@auth.name, @auth.remote_key, body, link, nil, images, nil, room)
    end
    redirect_to :action => 'list', :room => room
  end

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

  def do_delete(id, comment = nil, undelete = false)
    if comment and !comment.empty?
      ff_client.delete_comment(@auth.name, @auth.remote_key, id, comment, undelete)
    else
      ff_client.delete(@auth.name, @auth.remote_key, id, undelete)
    end
  end

  verify :only => :add_comment,
          :method => :post,
          :params => [:id, :body],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'list'}

  def add_comment
    eid = param(:id)
    body = param(:body)
    if eid and body
      ff_client.post_comment(@auth.name, @auth.remote_key, eid, body)
    end
    redirect_to :action => 'list'
  end

  verify :only => :like,
          :method => :get,
          :params => [:id],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'list'}

  def like
    eid = param(:id)
    if eid
      ff_client.like(@auth.name, @auth.remote_key, eid)
    end
    redirect_to :action => 'list'
  end

  verify :only => :unlike,
          :method => :get,
          :params => [:id],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'list'}

  def unlike
    eid = param(:id)
    if eid
      ff_client.unlike(@auth.name, @auth.remote_key, eid)
    end
    redirect_to :action => 'list'
  end
end
