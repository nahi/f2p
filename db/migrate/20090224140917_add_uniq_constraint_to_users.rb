class AddUniqConstraintToUsers < ActiveRecord::Migration
  def self.up
    sql = 'select * from users a where a.created_at != (select max(b.created_at) from users b where a.name = b.name)'
    user_ids = User.find_by_sql([sql]).map { |user|
      mod_ids = CheckedModified.find_all_by_user_id(user.id).map { |checked|
        LastModified.delete_all(:id => checked.last_modified_id)
        checked.id
      }
      CheckedModified.delete_all(:id => mod_ids)
      user.id
    }
    User.delete_all(:id => user_ids)
    add_index :users, :name, :unique => true
    add_index :last_modifieds, :eid, :unique => true
  end

  def self.down
    remove_index :users, :name
    remove_index :last_modifieds, :eid
  end
end
