require 'user'


class CreateProfiles < ActiveRecord::Migration
  def self.up
    create_table :profiles do |t|
      t.integer :font_size
      t.integer :entries_in_page
      t.integer :text_folding_size
      t.timestamps
    end
  end

  def self.down
    drop_table :profiles
  end
end
