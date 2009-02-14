class CreateLastModifieds < ActiveRecord::Migration
  def self.up
    create_table :last_modifieds do |t|
      t.string 'eid', :null => false, :unique => true
      t.timestamp 'date', :null => false
      t.timestamps
    end
  end

  def self.down
    drop_table :last_modifieds
  end
end
