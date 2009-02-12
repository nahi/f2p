class AddEntriesInThreadToProfile < ActiveRecord::Migration
  def self.up
    add_column :profiles, :entries_in_thread, :integer
    Profile.find(:all).each do |profile|
      profile.entries_in_thread = F2P::Config.entries_in_thread
      profile.save
    end
  end

  def self.down
    remove_column :profiles, :entries_in_thread
  end
end
