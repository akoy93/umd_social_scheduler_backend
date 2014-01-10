require 'set'

class SocialSchedulerBackend < Sinatra::Application
  # store session data for 1 day
  use Rack::Session::Pool, :expire_after => 86400

  # store directory paths
  set :root, File.expand_path('../../', __FILE__)
  set :schedules, File.expand_path("schedules", settings.root)

  APP_ID, APP_SECRET, REDIRECT, PASSWORD = File.readlines("#{settings.root}/app_data.txt").map(&:chomp)

  before do
    content_type :json
  end

  get '/' do
    redirect REDIRECT
  end

  # facebook server side login
  get '/login' do
    session[:oauth] = Koala::Facebook::OAuth.new(APP_ID, APP_SECRET, "#{request.base_url}/callback")
    redirect session[:oauth].url_for_oauth_code
  end

  # facebook logout
  get '/logout' do
    session.clear
    success
  end

  # login callback. stores user data in session hash.
  get '/callback' do
    error_check

    # get user's facebook graph object
    session[:access_token] = session[:oauth].get_access_token(params[:code])
    session[:graph] = Koala::Facebook::API.new(session[:access_token])
    
    # access_token and oauth no longer needed
    session[:access_token] = nil
    session[:oauth] = nil

    # user information
    profile = session[:graph].get_object("me")
    session[:fbid] = profile["id"]

    # store user's friends in session hash
    session[:friends] = session[:graph].get_connections("me", "friends").map { |friend| friend["id"] }.to_set

    success({ fbid: session[:fbid], name: profile["name"] })
  end

  # accepts html for user's schedule and renders an image
  get '/render_schedule/:html' do
    error_check params

    # generate html file
    File.open(html_path(session[:fbid]), "w+") do |f|
      f.puts "<html><body><center>"
      f.puts params[:html]
      f.puts "<h2>www.umdsocialscheduler.com</h2></center></body></html>"
    end

    # run shell commands to create schedule image
    status = system("#{settings.root}/wkhtmltoimage --crop-x 150 --crop-w 724 #{html_path session[:fbid]} #{jpg_path session[:fbid]}")
    status &&= system("rm #{html_path session[:fbid]}")

    error unless status
    session[:schedule_img] = jpg_path session[:fbid]

    success
  end

  # posts a user's schedule to facebook
  get '/post_schedule' do
    error_check
    error if session[:schedule_img].nil?

    # post schedule image to facebook
    session[:graph].put_picture(session[:schedule_img], 
      { :message => "Shared with UMD Social Scheduler. Download at www.umdsocialscheduler.com."}, "me")

    success
  end

  # saves user's schedule information to a database. expects (COURSE,SECTION)|(COURSE,SECTION)
  post '/add_schedule' do
    error_check params

    # remove existing course entries
    Course.all(:fbid => session[:fbid]).each { |course_entry| course_entry.destroy! }

    # parse request parameters and add new course entries
    params[:schedule].split('|').each do |course_data|
      course, section = course_data.split(',')
      course_entry = Course.new({ fbid: session[:fbid].to_i, course: course.upcase, section: section.upcase })
      error unless course_entry.save
    end

    success
  end

  get '/schedules' do
    error_check
    success({ count: Course.count })
  end

  get '/friends/:course/?:section?' do
    error_check params
    courses = classmates(session, params)
    # return json of friend ids in requested course/section
    success courses.map(&:fbid).select { |classmate| session[:friends].include? classmate }.shuffle
  end

  get '/friendsoffriends/:course/?:section?' do
    error_check params
    courses = classmates(session, params)
    mutual_counts = {}

    courses.map(&:fbid).each do |classmate| 
      mutual_counts[classmate] = session[:graph].get_connections("me", "mutualfriends/#{classmate}").size
    end

    # returns json of friend of friend ids in requested course/section
    success mutual_counts.reject! { |classmate, v| session[:friends].include? classmate }
      .sort_by { |k, mutuals| mutuals }.reverse
  end

  get '/schedule/:user_id' do
    error_check params
    file_path = jpg_path params[:user_id]

    unless File.exists?(file_path) && (params[:user_id] == session[:fbid] || session[:friends].include?(params[:user_id]))
      error
    end

    send_file file_path, type: :jpg
  end

  error do
    error
  end
end
