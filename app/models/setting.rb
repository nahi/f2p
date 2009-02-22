class Setting
  attr_accessor :font_size
  attr_accessor :entries_in_page
  attr_accessor :entries_in_thread
  attr_accessor :text_folding_size
  attr_accessor :link_open_new_window
  attr_accessor :link_type

  def initialize
    super
    @font_size = F2P::Config.font_size
    @entries_in_page = F2P::Config.entries_in_page
    @entries_in_thread = F2P::Config.entries_in_thread
    @text_folding_size = F2P::Config.text_folding_size
    @link_open_new_window = F2P::Config.link_open_new_window
    @link_type = F2P::Config.link_type
  end

  def validate
    errors = []
    if @font_size < 6
      errors << 'font size must be greater than 6'
    end
    unless (5..100) === @entries_in_page
      errors << 'entries in page must be in 5..100'
    end
    unless (3..100) === @entries_in_thread
      errors << 'entries in thread must be in 3..100'
    end
    unless (20..1000) === @text_folding_size
      errors << 'text folding size must be in 20..1000'
    end
    errors.empty? ? nil : errors
  end
end
