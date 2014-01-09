Bundler.require(:default)

# facebook application info
APP_ID, APP_SECRET = File.readlines("fb_app_info.txt").map(&:chomp)

configure do
  enable :sessions
end

before do
  def oauth
    @oauth ||= Koala::Facebook::OAuth.new(APP_ID, APP_SECRET)
  end
end

get '/login' do
  session[:oauth] = Koala::Facebook::OAuth.new(APP_ID, APP_SECRET, "#{request.base_url}/callback")
  redirect session[:oauth].url_for_oauth_code
end

get '/info' do
  { id: session[:fbid] }.to_json
end

get '/logout' do
  session.clear
  redirect request.base_url
end

get '/callback' do
  content_type :json
  
  # get user's facebook graph
  session[:access_token] = session[:oauth].get_access_token(params[:code])
  session[:graph] = Koala::Facebook::API.new(session[:access_token])
  
  # user information
  profile = session[:graph].get_object("me")
  session[:fbid] = profile["id"]

  # store user's friends in session
  session[:friends] = session[:graph].get_connections("me", "friends")

  { id: session[:fbid], name: profile["name"] }.to_json
end

