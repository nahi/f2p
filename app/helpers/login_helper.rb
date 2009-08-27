module LoginHelper
  def oauth_message
    if F2P::Config.friendfeed_api_oauth_consumer_key
    <<__EOM__
<p>
Click the banner for granting access to FriendFeed by f2p.
You don't have to register your credential to f2p site.
(You're redirected to FriendFeed Web site. It's easy to follow 1 or 2 steps.)<br />
#{oauth_image_tag}<br />
(NOTE: When it doesn't work for your cell phones please use remote key described below.)
</p>
<p>
You can remove the grant anytime from #{link_to('http://friendfeed.com/settings/applications', 'http://friendfeed.com/settings/applications')}.
</p>

<p align="center">
........ OR ........
</p>
__EOM__
    end
  end
end
