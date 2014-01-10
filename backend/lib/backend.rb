require 'set'

class SocialSchedulerBackend < Sinatra::Application
  # for storing session data
  use Rack::Session::Pool, :expire_after => 86400

  # root path
  set :root, File.expand_path('../', __FILE__)

  # facebook application info
  APP_ID, APP_SECRET = File.readlines("#{settings.root}/fb_app_info.txt").map(&:chomp)

  before do
    content_type :json
  end

  get '/' do
    redirect 'https://chrome.google.com/webstore/detail/umd-social-scheduler/lfmeffacphnlmfphjjbkmcecacolhabp?hl=en'
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
    if session.nil? or session[:oauth].nil?
      error
    else
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
  end

  # accepts html for user's schedule and renders an image
  get '/render_schedule/:html' do
    if session.nil? or session[:fbid].nil? or params[:html].nil?
      error
    else
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
      { success: true }.to_json
    end
  end

  # posts a user's schedule to facebook
  get '/post_schedule' do
    if session.nil? or session[:graph].nil? or session[:schedule_img].nil?
      error
    else
      # post schedule image to facebook
      session[:graph].put_picture(session[:schedule_img], { :message => "Shared with UMD Social Scheduler. Download at www.umdsocialscheduler.com."}, "me")
      { success: true }.to_json
    end
  end

  helpers do
    def error
      return { success: false }.to_json
    end
  end
end
