helpers do
  def error_check(params = {captures: []})
    valid_pre_login = !(session.nil? or session[:oauth].nil?)
    valid_post_login = !(session.nil? or session[:fbid].nil? \
      or session[:friends].nil? or session[:graph].nil? or session[:api].nil?)
    return false unless valid_pre_login or valid_post_login
    true
  end

  def error(data = {})
    return { success: false, data: data }.to_json
  end

  def success(data = {})
    return { success: true, data: data }.to_json
  end

  def jpg_path(term, id)
    File.expand_path("#{term}/#{id}.jpg", settings.schedules)
  end

  def html_path(term, id)
    File.expand_path("#{term}/#{id}.html", settings.schedules)
  end

  def no_image_path
    File.expand_path("not_available.jpg", settings.schedules)
  end
end
