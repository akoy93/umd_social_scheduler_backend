require 'set'

class SocialSchedulerBackend < Sinatra::Application
  DataMapper.setup(:default, ENV['DATABASE_URL]'] || "sqlite3://#{Dir.pwd}/dev.db")

  class Course
    include DataMapper::Resource

    property :id, Serial
    property :fbid, Integer
    property :course, String
    property :section, String

    validates_presence_of :fbid
    validates_presence_of :course
    validates_presence_of :section
    validates_length_of :course, :minimum => 7, :maximum => 8
    validates_length_of :section, :is => 4
  end

  DataMapper.finalize.auto_upgrade!

  # for storing session data
  use Rack::Session::Pool, :expire_after => 86400

  # root path
  set :root, File.expand_path('../', __FILE__)

  # facebook application info
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
  end

  # login callback. stores user data in a session hash
  get '/callback' do
    error if session.nil? or session[:oauth].nil?

    # get user's facebook graph
    session[:access_token] = session[:oauth].get_access_token(params[:code])
    session[:graph] = Koala::Facebook::API.new(session[:access_token])
    
    # oauth no longer needed
    session[:oauth] = nil

    # user information
    profile = session[:graph].get_object("me")
    session[:fbid] = profile["id"]

    # store user's friends in session
    session[:friends] = session[:graph].get_connections("me", "friends").map { |friend| friend["id"] }.to_set

    { success: true, id: session[:fbid], name: profile["name"] }.to_json
  end

  # accepts html for user's schedule and renders an image
  get '/render_schedule/:html' do
    error if session.nil? or session[:fbid].nil? or params[:html].empty?

    schedules_path = File.expand_path("../schedules", settings.root)
    file_name = "#{session[:fbid]}"
    file_path = schedules_path + "/" + file_name

    # generate html file
    File.open("#{file_path}.html", "w+") do |f|
      f.puts "<html><body><center>"
      f.puts params[:html]
      f.puts "<h2>www.umdsocialscheduler.com</h2></center></body></html>"
    end

    # run shell commands to create schedule image
    status = system("#{schedules_path}/../wkhtmltoimage --crop-x 150 --crop-w 724 #{file_path}.html #{file_path}.jpg")
    status &&= system("rm #{file_path}.html")

    error unless status
    session[:schedule_img] = "#{file_path}.jpg"

    success
  end

  # posts a user's schedule to facebook
  get '/post_schedule' do
    error if session.nil? or session[:graph].nil? or session[:schedule_img].nil?

    # post schedule image to facebook
    session[:graph].put_picture(session[:schedule_img], 
      { :message => "Shared with UMD Social Scheduler. Download at www.umdsocialscheduler.com."}, "me")

    success
  end

  # saves user's schedule information to a database. expects (COURSE,SECTION)|(COURSE,SECTION)
  post '/add_schedule' do
    error if session.nil? or session[:fbid].nil? or params[:schedule].empty?

    # remove existing course entries
    Course.all(:fbid => session[:fbid]).each { |course_entry| course_entry.destroy! }

    params[:schedule].split('|').each do |course_data|
      course, section = course_data.split(',')
      course_entry = Course.new({ fbid: session[:fbid].to_i, course: course.upcase, section: section.upcase })
      error unless course_entry.save
    end

    success
  end

  get '/schedules' do
    { count: Course.count }.to_json
  end

  get '/friends/:course/?:section?' do
    error if session.nil? or session[:friends].nil? or params[:course].empty?

    courses = Course.all(course: params[:course].upcase)
    courses = courses.all(section: params[:section].upcase) unless params[:section].nil? or params[:section].empty?

    # return json of friend ids in requested course/section
    courses.map(&:fbid).select { |classmate| session[:friends].include? classmate }.shuffle.to_json
  end

  get '/friendsoffriends/:course/?:section?' do
    error if session.nil? or session[:graph].nil? or session[:friends].nil? or params[:course].empty?

    courses = Course.all(course: params[:course].upcase)
    courses = courses.all(section: params[:section].upcase) unless params[:section].nil? or params[:section].empty?

    mutual_counts = {}

    courses.map(&:fbid).each do |classmate| 
      mutual_counts[classmate] = session[:graph].get_connections("me", "mutualfriends/#{classmate}").size
    end

    # returns json of friend of friend ids in requested course/section
    mutual_counts.reject! { |classmate, v| session[:friends].include? classmate }
      .sort_by { |k, mutuals| mutuals }.reverse.to_json
  end

  error do
    error
  end

  helpers do
    def error
      return { success: false }.to_json
    end

    def success
      return { success: true }.to_json
    end
  end
end
