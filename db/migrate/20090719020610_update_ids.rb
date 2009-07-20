class UpdateIds < ActiveRecord::Migration
  # CAUTION:
  #   you need to run db:migrate first.
  #   if you get 'eid is not unique' error, delete 'e/%' entries and run
  #   the migration script again.
  #   sqlite> delete from last_modifieds where eid like 'e/%';
  def self.up
    execute(%q(update pins set eid = 'e/' || replace(eid, '-', '') where eid not like 'e/%'))
    execute(%q(update last_modifieds set eid = 'e/' || replace(eid, '-', '') where eid not like 'e/%'))
  end

  def self.down
  end
end
