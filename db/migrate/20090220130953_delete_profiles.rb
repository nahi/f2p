class DeleteProfiles < ActiveRecord::Migration
  def self.up
    drop_table :profiles
  end

  def self.down
    create_table "profiles", :force => true do |t|
      t.integer  "font_size"
      t.integer  "entries_in_page"
      t.integer  "text_folding_size"
      t.datetime "created_at"
      t.datetime "updated_at"
      t.integer  "user_id"
      t.integer  "entries_in_thread"
    end
  end
end
