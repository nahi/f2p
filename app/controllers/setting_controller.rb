class SettingController < ApplicationController
  before_filter :login_required
  after_filter :strip_heading_spaces
  after_filter :compress

  def initialize
    super
  end

  def index
    @timezone = param(:timezone) || @setting.timezone || timezone_from_request_ip || F2P::Config.timezone
    @font_size = (param(:font_size) || @setting.font_size).to_i
    @entries_in_page = (param(:entries_in_page) || @setting.entries_in_page).to_i
    @entries_in_thread = (param(:entries_in_thread) || @setting.entries_in_thread).to_i
    @text_folding_size = (param(:text_folding_size) || @setting.text_folding_size).to_i
    @twitter_comment_hack = param(:twitter_comment_hack) || @setting.twitter_comment_hack
    @disable_fof = param(:disable_fof) || @setting.disable_fof
    @list_view_media_rendering = param(:list_view_media_rendering) || @setting.list_view_media_rendering
    @list_view_profile_picture = param(:list_view_profile_picture) || @setting.list_view_profile_picture
    @link_open_new_window = param(:link_open_new_window) || @setting.link_open_new_window
    @link_type = param(:link_type) || @setting.link_type
    @google_maps_geocoding_lang = param(:google_maps_geocoding_lang) || @setting.google_maps_geocoding_lang
    @reload_list_in_minutes = param(:reload_list_in_minutes) || @setting.reload_list_in_minutes
  end

  def update
    original_value = {}
    [
      :timezone,
      :font_size,
      :entries_in_page,
      :entries_in_thread,
      :text_folding_size,
      :twitter_comment_hack,
      :disable_fof,
      :list_view_media_rendering,
      :list_view_profile_picture,
      :link_open_new_window,
      :link_type,
      :google_maps_geocoding_lang,
      :reload_list_in_minutes
    ].each do |key|
      original_value[key] = @setting.send(key)
    end
    # int settings
    [:font_size, :entries_in_page, :entries_in_thread, :text_folding_size].each do |key|
      if param(key)
        instance_variable_set('@' + key.to_s, param(key))
        @setting.send(key.to_s + '=', param(key).to_i)
      end
    end
    # bool settings
    [:twitter_comment_hack, :disable_fof, :list_view_media_rendering, :list_view_profile_picture, :link_open_new_window].each do |key|
      instance_variable_set('@' + key.to_s, param(key) == 'checked')
      @setting.send(key.to_s + '=', param(key) == 'checked')
    end
    @setting.timezone = param(:timezone)
    @setting.link_type = nil
    if param(:link_type_gwt) == 'checked'
      @setting.link_type = 'gwt'
    end
    @setting.google_maps_geocoding_lang = param(:google_maps_geocoding_lang)
    @setting.google_maps_zoom ||= F2P::Config.google_maps_zoom
    if str = param(:reload_list_in_minutes)
      @setting.reload_list_in_minutes = str.to_i
    else
      @setting.reload_list_in_minutes = nil
    end
    if errors = @setting.validate
      original_value.each do |key, value|
        @setting.send(key.to_s + '=', value)
      end
      flash[:error] = 'Settings error: ' + errors.join(", ")
      render :action => 'index'
    else
      flash[:message] = 'Settings updated.'
      redirect_to_entry_list
    end
  end
end
