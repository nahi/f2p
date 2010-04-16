class AddTokenTable < ActiveRecord::Migration
  def self.up
    create_table :tokens do |t|
      t.integer 'user_id', :null => false
      t.string 'service', :null => false
      t.string 'service_user', :null => false
      t.string 'token', :null => false
      t.string 'secret', :null => false
      t.string 'params', :null => true
      t.timestamps
    end
    # Keep FriendFeed tokens in Users table as before.
  end

  def self.down
    drop_table :tokens
  end
end
