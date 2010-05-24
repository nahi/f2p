module LoginHelper
  def oauth_message
    if F2P::Config.friendfeed_api_oauth_consumer_key
    <<__EOM__
<p>
Click one of the link from followings to start using 'm.ctor.org'. You can add other services afterward.
</p>
<ul>
<li>#{ link_to(h('FriendFeed'), :controller => :login, :action => :initiate_oauth_login) }</li>
<li>#{ link_to(h('Twitter'), :controller => :login, :action => :initiate_twitter_oauth_login) } [experimental]</li>
<li>#{ link_to(h('Google buzz'), :controller => :login, :action => :initiate_buzz_oauth_login) } [experimental]</li>
</ul>
<p>
Above links are for granting access to FriendFeed, Twitter or Google buzz by 'm.ctor.org'.
You don't have to register your credential to 'm.ctor.org' site.
(NOTE: When it doesn't work for your cell phones please use remote key described below.)
</p>

<p align="center">
........ OR ........
</p>
__EOM__
    end
  end
end
