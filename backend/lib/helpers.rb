helpers do
  def error_check(params = {captures: []})
    valid_pre_login = !(session.nil? or session[:oauth].nil?)
    valid_post_login = !(session.nil? or session[:fbid].nil? or session[:friends].nil? or session[:graph].nil?)
    error unless valid_pre_login or valid_post_login
    params[:captures].each { |capture| error if capture.empty? }
  end

  def error
    return { success: false }.to_json
  end

  def success(data = {})
    return { success: true, data: data }.to_json
  end

  def classmates(session, params)
    courses = Course.all(course: params[:course].upcase)
    courses = courses.all(section: params[:section].upcase) unless params[:section].nil? or params[:section].empty?
  end

  def jpg_path(id)
    File.expand_path("#{id}.jpg", settings.schedules)
  end

  def html_path(id)
    File.expand_path("#{id}.html", settings.schedules)
  end
end