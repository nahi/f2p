class SettingController < ApplicationController
  before_filter :login_required
  after_filter :strip_heading_spaces
  after_filter :compress

  def index
    @font_size = param(:font_size) || @auth.profile.font_size
    @entries_in_page = param(:entries_in_page) || @auth.profile.entries_in_page
    @text_folding_size = param(:text_folding_size) || @auth.profile.text_folding_size
  end

  def update
    updated = false
    original_value = {}
    [:font_size, :entries_in_page, :text_folding_size].each do |key|
      if param(key)
        instance_variable_set('@' + key.to_s, param(key))
        original_value[key] = @auth.profile.send(key)
        @auth.profile.send(key.to_s + '=', param(key))
        updated = true
      end
    end
    if updated
      unless @auth.profile.save
        original_value.each do |key, value|
          @auth.profile.send(key.to_s + '=', value)
        end
        @profile = @auth.profile
        flash[:error] = 'Settings error'
        render :action => 'index'
        return
      end
    end
    flash[:message] = 'Settings updated.'
    redirect_to :controller => 'entry', :action => 'list'
  end
end
