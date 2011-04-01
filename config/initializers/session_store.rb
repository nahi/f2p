ActionController::Base.session = {
  :key => '_f2p_sess',
  :secret => nil
}

ActionController::Base.session_store = :active_record_store
ActionController::Base.session_options[:expire_after] = 2.weeks

