class CreateCheckedModifieds < ActiveRecord::Migration
  def self.up
    create_table :checked_modifieds do |t|
      t.integer 'user_id', :null => false
      t.integer 'last_modified_id', :null => false
      t.timestamp 'checked'
      t.timestamps
    end
  end

  def self.down
    drop_table :checked_modifieds
  end
end
