class CreatePins < ActiveRecord::Migration
  def self.up
    create_table :pins do |t|
      t.integer 'user_id', :null => false
      t.string 'eid', :null => false
      t.timestamps
    end
  end

  def self.down
    drop_table :pins
  end
end
