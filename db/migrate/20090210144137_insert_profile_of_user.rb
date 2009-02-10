class InsertProfileOfUser < ActiveRecord::Migration
  def self.up
    User.find(:all).each do |user|
      if user.profile.nil?
        user.profile = Profile.new
        user.profile.font_size = F2P::Config.default_font_size
        user.profile.entries_in_page = F2P::Config.default_entries_in_page
        user.profile.text_folding_size = F2P::Config.default_text_folding_size
        raise unless user.profile.save
      end
    end
  end

  def self.down
    User.find(:all).each do |user|
      user.profile = nil
      raise unless user.save
    end
  end
end
