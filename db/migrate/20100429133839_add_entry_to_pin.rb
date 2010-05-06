class AddEntryToPin < ActiveRecord::Migration
  def self.up
    add_column :pins, :source, :string
    add_column :pins, :entry, :string
  end

  def self.down
    remove_column :pins, :source
    remove_column :pins, :entry
  end
end
