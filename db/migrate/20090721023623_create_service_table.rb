require 'service'
require 'httpclient'


class CreateServiceTable < ActiveRecord::Migration
  def self.up
    create_table :services do |t|
      t.string :service_id, :null => false
      t.string :name, :null => false
      t.string :icon_url, :null => false
    end
    puts 'loading services via V1 API (accessing via HTTP...)'
    res = HTTPClient.get_content('http://friendfeed.com/api/services')
    JSON.parse(res)['services'].each do |service|
      s = Service.new
      s.service_id = service['id']
      s.name = service['name']
      s.icon_url = service['iconUrl']
      s.save!
    end
  end

  def self.down
    drop_table :services
  end
end
