class User < ActiveRecord::Base
  TEXT_MAXLEN = 255
  validates_length_of :name, :in => 1..TEXT_MAXLEN
  validates_length_of :remote_key, :in => 1..TEXT_MAXLEN
end
