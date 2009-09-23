class ProfileController < ApplicationController
  before_filter :login_required
  after_filter :strip_heading_spaces
  after_filter :compress

  def initialize
    super
  end

  def index
    redirect_to :action => :show
  end

  verify :only => :inbox,
          :method => [:get],
          :params => [:id],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:controller => 'entry', :action => 'inbox'}

  def show
    @id = param(:id)
    fetch_feedinfo(@id)
  end

  verify :only => :edit,
          :method => [:get],
          :params => [:id],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:controller => 'entry', :action => 'inbox'}

  def edit
    @id = param(:id)
    fetch_feedinfo(@id)
    @subscription = create_subscription_summary(@id)
  end

  verify :only => :update,
          :method => [:post],
          :params => [:id],
          :add_flash => {:error => 'verify failed'},
          :redirect_to => {:controller => 'entry', :action => 'inbox'}

  def update
    id = param(:id)
    fetch_feedinfo(id)
    feedname = @feedinfo.name
    log = []
    subscription = create_subscription_summary(id)
    subscription.each do |listid, name, checked|
      if param(listid) != checked
        case param(listid)
        when 'checked'
          status = User.ff_subscribe(auth, id, listid)
        else
          status = User.ff_unsubscribe(auth, id, listid)
        end
        if status
          log << "#{status['status']} #{feedname} on #{name}."
        else
          log << "Subscription status change failed for #{name}."
        end
      end
    end
    flash[:message] = log.join(' ')
    redirect_to :action => 'edit', :id => id
  end

private

  def create_subscription_summary(id)
    sub = []
    if feedinfo = User.ff_feedinfo(auth, 'home')
      sub[0] = extract_subscription_summary(id, feedinfo)
    end
    if @feedlist
      tasks = []
      @feedlist['lists'].each_with_index do |list, idx|
        tasks << Task.run {
          if feedinfo = User.ff_feedinfo(auth, list.id)
            sub[idx + 1] = extract_subscription_summary(id, feedinfo)
          end
        }
      end
      tasks.each do |task|
        task.result
      end
    end
    sub.compact
  end

  def extract_subscription_summary(id, feedinfo)
    [
      feedinfo.id,
      feedinfo.name,
      feedinfo.feeds.any? { |e| e.id == id } ? 'checked' : nil
    ]
  end
end
