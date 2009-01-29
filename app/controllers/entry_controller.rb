class EntryController < ApplicationController
  before_filter :login_required

  NUM_DEFAULT = '40'

  class DebugLogger
    def initialize(logger)
      @logger = logger
    end

    def <<(str)
      @logger.info(str)
    end
  end

  verify :only => :list,
          :method => :get,
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'list'}

  def list
    @room = params[:room]
    @user = params[:user]
    @likes = params[:likes]
    @service = params[:service]
    @start = (params[:start] || '0').to_i
    @num = (params[:num] || NUM_DEFAULT).to_i
    @entry_fold = (!@user and !@service and params[:fold] != 'no')
    opt = {
      :name => @auth.name,
      :remote_key => @auth.remote_key,
      :start => @start,
      :num => @num,
      :service => @service
    }
    if @user
      @entries = Entry.find(opt.merge(:user => @user))
    elsif @room
      @entries = Entry.find(opt.merge(:room => @room))
    elsif @likes == 'only'
      @entries = Entry.find(opt.merge(:likes => true))
    else
      @entries = Entry.find(opt)
    end
    @compact = true
    @post = true
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
    @eid = params[:id]
    opt = {
      :name => @auth.name,
      :remote_key => @auth.remote_key,
      :id => @eid
    }
    @entries = Entry.find(opt)
    @compact = false
    @post = false
    @post_comment = true
    @entries ||= []
    render :action => 'list'
  end

  def new
    @room = params[:room]
  end

  verify :only => :add,
          :method => :post,
          :params => [:body],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:action => 'list'}

  def add
    body = params[:body]
    link = params[:link]
    room = params[:room]
    link = nil if link and link.empty?
    room = nil if room and room.empty?
    if link
      title = capture_title(link)
      ff_client.post(@auth.name, @auth.remote_key,
        title, link, body, nil, nil, room)
    elsif body
      ff_client.post(@auth.name, @auth.remote_key,
        body, link, nil, nil, nil, room)
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
    id = params[:id]
    comment = params[:comment]
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
    id = params[:id]
    comment = params[:comment]
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
    eid = params[:id]
    body = params[:body]
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
    eid = params[:id]
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
    eid = params[:id]
    if eid
      ff_client.unlike(@auth.name, @auth.remote_key, eid)
    end
    redirect_to :action => 'list'
  end
end
