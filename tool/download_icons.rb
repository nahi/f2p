require 'httpclient'
require 'json'
require 'fileutils'

httpclient = HTTPClient.new

dir = File.expand_path('icons', File.dirname(__FILE__))
FileUtils.mkdir_p(dir)

save_as = proc { |url, basename|
  filename = File.join(dir, basename + '.png')
  File.open(filename, 'wb') do |f|
      f.write(httpclient.get_content(url))
  end
}

# internal.png is not listed on 'about' page.
save_as.call('http://friendfeed.com/static/images/icons/internal.png', 'internal')

JSON.parse(httpclient.get_content('http://friendfeed.com/api/services'))['services'].each do |service|
  url = service['iconUrl']
  #name = service['name']
  name = url.scan(%r[/([^/]+).png])[0][0]
  save_as.call(url, name)
end
