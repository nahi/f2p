class AddOauthSupport < ActiveRecord::Migration
  def self.up
    add_column :users, :oauth_access_token, :string
    add_column :users, :oauth_access_token_secret, :string
    add_column :users, :oauth_access_token_generated, :timestamp
  end

  def self.down
    remove_column :users, :oauth_access_token
    remove_column :users, :oauth_access_token_secret
    remove_column :users, :oauth_access_token_generated
  end
end
