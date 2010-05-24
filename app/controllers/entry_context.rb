class EntryContext
  attr_accessor :service_source

  attr_accessor :eid
  attr_accessor :eids
  attr_accessor :query
  attr_accessor :user
  attr_accessor :feed
  attr_accessor :room
  attr_accessor :friends
  attr_accessor :like
  attr_accessor :comment
  attr_accessor :link
  attr_accessor :label
  attr_accessor :service
  attr_accessor :start
  attr_accessor :num
  attr_accessor :max_id
  attr_accessor :with_likes
  attr_accessor :with_comments
  attr_accessor :with_like
  attr_accessor :with_comment
  attr_accessor :fold
  attr_accessor :inbox
  attr_accessor :home
  attr_accessor :moderate

  attr_accessor :in_reply_to_service_user
  attr_accessor :in_reply_to_screen_name
  attr_accessor :in_reply_to_status_id

  attr_accessor :viewname

  def initialize(auth)
    @service_source = nil
    @auth = auth
    @viewname = nil
    @eid = @eids = @query = @user = @feed = @room = @friends = @like = @comment = @link = @label = @service = @start = @num = @max_id = @with_likes = @with_comments = @with_like = @with_comment = nil
    @fold = false
    @inbox = false
    @home = true
    @moderate = nil
    @param = nil
    @in_reply_to_service_user = @in_reply_to_screen_name = @in_reply_to_status_id = nil
  end

  def parse(param, setting)
    return unless param
    @param = param
    @eid = param(:eid)
    @eids = param(:eids).split(',') if param(:eids)
    @query = @param[:query]
    @user = param(:user)
    @feed = param(:feed)
    @room = param(:room)
    @friends = param(:friends)
    if @friends == 'checked'
      @friends = @user
      @user = nil
    end
    @like = param(:like)
    @comment = param(:comment)
    @link = param(:link)
    @label = param(:label)
    @service = param(:service)
    @start = (param(:start) || '0').to_i
    @num = intparam(:num) || setting.entries_in_page
    @max_id = param(:max_id)
    @with_likes = intparam(:with_likes)
    @with_comments = intparam(:with_comments)
    @with_like = (param(:with_like) == 'checked')
    @with_comment = (param(:with_comment) == 'checked')
    @in_reply_to_service_user = param(:in_reply_to_service_user)
    @in_reply_to_screen_name = param(:in_reply_to_screen_name)
    @in_reply_to_status_id = param(:in_reply_to_status_id)
    @fold = param(:fold) != 'no'
    @inbox = false
    @home = !(@eid or @eids or @inbox or @query or @like or @comment or @user or @friends or @feed or @room or @link or @label)
  end

  def single?
    !!@eid
  end

  def list?
    !single?
  end

  def feedid
    user_for || room_for || feed || 'home'
  end

  def profile_for
    user_for || room_for
  end

  def direct_message?
    feedid == 'filter/direct'
  end

  def user_only?
    @user and !@like and !@comment
  end

  def friend_view?
    user_only? and @user != @auth.name
  end

  def find_opt
    opt = {
      :auth => @auth,
      :start => @start,
      :num => @num,
      :service => @service,
      :label => @label,
      :merge_entry => true,
      # works only merge_entry == true
      :merge_service => true
    }
    if @eid
      opt.merge(:eid => @eid)
    elsif @eids
      opt.merge(:eids => @eids)
    elsif @link
      opt.merge(:link => @link, :query => @query)
    elsif @query or @service
      opt.merge(:query => @query, :with_likes => @with_likes, :with_comments => @with_comments, :with_like => @with_like, :with_comment => @with_comment, :user => @user, :room => @room, :friends => @friends, :service => @service, :merge_entry => (@query.nil? or @query.empty?))
    elsif @like
      opt.merge(:like => @like, :user => @user || @auth.name)
    elsif @user
      opt.merge(:user => @user, :merge_entry => false)
    elsif @feed
      if @feed == 'filter/direct'
        opt.merge(:feed => @feed, :merge_entry => false, :merge_service => false)
      else
        opt.merge(:feed => @feed)
      end
    elsif @room
      opt.merge(:room => @room, :merge_entry => (@room != '*'))
    elsif @inbox
      opt.merge(:inbox => true, :merge_service => true)
    else
      opt.merge(:merge_service => true)
    end
  end

  def reset_for_new
    @eid = @comment = nil
  end

  def back_opt
    list_opt.merge(:controller => :entry, :action => default_action, :start => @start, :num => @num, :max_id => @max_id)
  end

  def list_opt
    {
      :query => @query,
      :with_likes => @with_likes,
      :with_comments => @with_comments,
      :with_like => @with_like ? 'checked' : nil,
      :with_comment => @with_comment ? 'checked' : nil,
      :user => @user,
      :feed => @feed,
      :room => @room,
      :friends => @friends,
      :like => @like,
      :comment => @comment,
      :link => @link,
      :label => @label,
      :service => @service,
      :fold => @fold ? nil : 'no'
    }
  end

  def room_for
    (@room != '*') ? @room : nil
  end

  def user_for
    return nil if tweets?
    user = @user || @friends
    user != 'me' ? user : nil
  end

  def list_for
    if /\Alist\b/ =~ @feed or /\Asummary\b/ =~ @feed
      @feed
    elsif self.home
      'home'
    end
  end

  def list_base?
    @home or (/\Alist\b/ =~ @feed and /\/summary\/\d+\z/ !~ @feed)
  end

  def is_summary?
    /\Asummary\b/ =~ @feed or /\/summary\/\d+\z/ =~ @feed
  end

  def ff?
    @service_source.nil?
  end

  def tweets?
    @service_source == 'twitter'
  end

  def buzz?
    @service_source == 'buzz'
  end

  def link_opt(opt = {})
    opt.merge(:action => default_action, :eid => @eid)
  end

private

  def param(key)
    ApplicationController.param(@param, key)
  end

  def intparam(key)
    ApplicationController.intparam(@param, key)
  end

  def default_action
    if @eid
      'show'
    elsif @inbox
      'inbox'
    elsif tweets?
      'tweets'
    elsif buzz?
      'buzz'
    else
      'list'
    end
  end
end
