class CheckedModified < ActiveRecord::Base
  belongs_to :user
  belongs_to :last_modified
end
