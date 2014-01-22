require 'set'

class SocialSchedulerController < Sinatra::Application
  # diable rack protection while in development
  configure :development do
    disable :protection
  end

  configure :production do
    disable :protection
  end

  # store directory paths
  set :root, File.expand_path('../../', __FILE__)
  set :schedules, File.expand_path("schedules", settings.root)

  # read application data
  APP_ID, APP_SECRET, REDIRECT, PASSWORD, AWS_KEY, AWS_SECRET, ASSOCIATE_TAG = 
    File.readlines("#{settings.root}/app_data.txt").map(&:chomp)

  # set up logging
  configure do
    file = File.new("#{settings.root}/log/#{settings.environment}.log", 'a+')
    file.sync = true
    use Rack::CommonLogger, file
  end

  before do
    content_type :json
    response['Access-Control-Allow-Origin'] = '*'
    session[:init] = true # so session is loaded
  end

  get '/' do
    redirect REDIRECT
  end

  # Route for caller to determine if the server is online
  get '/alive' do
    success
  end

  # Parameters: None
  # facebook server side login
  get '/login' do
    session[:oauth] = Koala::Facebook::OAuth
      .new(APP_ID, APP_SECRET, "#{request.base_url}/callback")
    redirect session[:oauth].url_for_oauth_code
  end

  # Parameters: access_token
  # create session with facebook access token. stores user data in session hash.
  get '/access' do
    return error if params[:access_token].nil? or params[:access_token].empty?

    session[:graph] = Koala::Facebook::API.new(params[:access_token])
    session[:api] = Koala::Facebook::API.new(params[:access_token])
    profile = session[:graph].get_object("me")
    session[:fbid] = profile["id"]
    session[:name] = profile["name"]
    session[:friends] = session[:graph]
      .get_connections("me", "friends").map { |friend| friend["id"] }.to_set

    return error unless error_check
    success({share: ((student = Student.get(session[:fbid])).nil? ? true : student.share)})
  end

  # Parameters: None
  # enables sharing for the current user
  get '/enable_sharing' do
    return error unless error_check
    return error if (student = Student.get(session[:fbid])).nil?
    student.enable_sharing
    success
  end

  # Parameters: None
  # disables sharing for the current user
  get '/disable_sharing' do
    return error unless error_check
    return error if (student = Student.get(session[:fbid])).nil?
    student.disable_sharing
    success
  end

  # Parameters: None
  # facebook logout
  get '/logout' do
    session.clear
    success
  end

  # login callback. stores user data in session hash.
  get '/callback' do
    return error unless error_check

    # get user's facebook graph object and api instance
    session[:access_token] = session[:oauth].get_access_token(params[:code])
    session[:graph] = Koala::Facebook::API.new(session[:access_token])
    session[:api] = Koala::Facebook::API.new(session[:access_token])

    # access_token and oauth no longer needed
    session[:access_token] = nil
    session[:oauth] = nil

    # user information
    profile = session[:graph].get_object("me")
    session[:fbid] = profile["id"]
    session[:name] = profile["name"]

    # store user's friends in session hash
    session[:friends] = session[:graph]
      .get_connections("me", "friends").map { |friend| friend["id"] }.to_set

    success({ fbid: session[:fbid], name: session[:name] })
  end

  # Parameters: term, html
  # accepts html for user's schedule and renders an image
  post '/render_schedule' do
    return error unless error_check params
    
    # generate html file
    File.open(html_path(params[:term], session[:fbid]), "w+") do |f|
      f.puts "<html><body><center>"
      f.puts params[:html]
      f.puts "<h2>www.umdsocialscheduler.com</h2></center></body></html>"
    end

    # run shell commands to create schedule image
    status = system("#{settings.root}/wkhtmltoimage --crop-x 150 --crop-w 724"\
        " #{html_path(params[:term], session[:fbid])} #{jpg_path(params[:term], session[:fbid])}")
    status &&= system("rm #{html_path(params[:term], session[:fbid])}")

    return error unless status
    session[:schedule_img] = jpg_path(params[:term], session[:fbid])

    success
  end

  # Parameters: None
  # posts a user's schedule to facebook
  get '/post_schedule' do
    return error unless error_check params
    return error if session[:schedule_img].nil?
    permissions = session[:graph].get_connections('me', 'permissions')

    # check permission to post to wall
    return error unless permissions[0]['publish_actions'].to_i == 1

    # post schedule image to facebook
    session[:graph].put_picture(session[:schedule_img], 
      { :message => "Shared with UMD Social Scheduler."\
        " Download at www.umdsocialscheduler.com."}, "me")

    success
  end

  # Parameters: term, schedule
  # saves user's schedule information to a database. expects COURSE,SEC|COURSE,SEC.
  post '/add_schedule' do
    return error unless error_check params

    # too many classes
    return error if params[:schedule].split('|').size > 15

    # fetch current user
    student = Student.new_student(session[:fbid], session[:name])
    return error if student.nil?

    # remove existing course entries
    return error unless student.delete_schedule(params[:term])

    # parse request parameters and add new course entries
    params[:schedule].split('|').each do |course_data|
      # delete schedule on error
      unless student.add_course(params[:term], *course_data.split(','))
        student.delete_schedule(params[:term])
        return error
      end
    end

    success
  end

  # Parameters: term, course, section (optional)
  # get friends in a class
  get '/friends' do
    return error unless error_check params
    roster = Course.roster(params[:term], params[:course], params[:section])
    # return json of friend ids, names, and sections in requested course/section
    success [] if roster.nil?
    success roster.select { |c| session[:friends].include? c[:fbid] }.sort_by { |c| c[:section] }
  end

  # Parameters: term, course, section (optional)
  # get friends of friends in a class
  get '/friendsoffriends' do
    return error unless error_check params
    roster = Course.roster(params[:term], params[:course], params[:section])
    success [] if roster.nil?

    mutual_counts = []
    # filter classmates to potential friends of friends, slice into chunks of 50, invoke
    # facebook batch requests to get mutual friends quickly, merge results into each hash
    # - chained methods to get around readonly restriction of database
    # - slice classmates into chunks of 50 to comply with facebook batch limits
    roster.reject { |c| c[:fbid] == session[:fbid] or session[:friends].include? c[:fbid] }
      .each_slice(50) do |roster_slice|
        mutuals = session[:api].batch do |batch_api|
          roster_slice.each do |c| 
            batch_api.get_connections("me", "mutualfriends/#{c[:fbid]}")
          end
        end
        mutuals.map!(&:size)
        mutual_counts += roster_slice.each_with_index
          .map { |c, i| c[:num_mutuals] = mutuals[i]; c }
      end

    # returns json of friend of friend ids, names, and sections in requested course/section sorted
    # by num mutual friends
    success mutual_counts.sort_by { |c| c[:num_mutuals] }.reverse
  end

  # Parameters: term, fbid
  # return a json of the user's schedule
  get '/schedule' do
    unless error_check(params) && 
      (params[:fbid] == session[:fbid] || session[:friends].include?(params[:fbid]))
      return error
    end
    success Student.get(params[:fbid]).get_schedule(params[:term])
  end

  # Parameters: term, fbid
  # get an image of a user's schedule (must be friends)
  get '/schedule_image' do
    return error unless error_check params
    file_path = jpg_path(params[:term], params[:fbid])

    # enforce friends condition
    unless File.exists?(file_path) && 
      (params[:fbid] == session[:fbid] || session[:friends].include?(params[:fbid]))
      send_file no_image_path, type: :jpg
    end

    # enforce share condition
    student = Student.get(params[:fbid])
    unless !student.nil? && student.share
      send_file no_image_path, type: :jpg
    end

    send_file file_path, type: :jpg
  end

  # Parameters: isbns (separated by '|')
  # use amazon product advertising api to convert isbns to asins
  get '/get_asin' do
    return error if params[:isbns].nil? or params[:isbns].empty?

    req = Vacuum.new
    req.configure(
      aws_access_key_id: AWS_KEY,
      aws_secret_access_key: AWS_SECRET,
      associate_tag: ASSOCIATE_TAG
    )

    asins = []
    threads = []

    # get asin number for each isbn number and cache data
    params[:isbns].split('|').uniq.each do |isbn|
      threads << Thread.new do # use threads to execute requests concurrently
        amazonParams = { 
          'Operation' => 'ItemLookup',
          'Keywords' => isbn,
          'ItemId' => isbn,
          'IdType' => 'ISBN',
          'SearchIndex' => 'All'
        }

        # look up asin for isbn and cache results
        if ISBN.get(isbn).nil?
          data = req.item_search(amazonParams).to_h
          if data["ItemSearchResponse"] && data["ItemSearchResponse"]["Items"] \
            && data["ItemSearchResponse"]["Items"]["Item"]
            item = data["ItemSearchResponse"]["Items"]["Item"]
            if item.class == Hash
              asin = item["ASIN"]
            elsif item.class == Array
              asin = item.first["ASIN"]
            end
            ISBN.create({isbn: isbn, asin: asin.to_s})
          end
        end
        asins << { isbn: isbn, asin: ((entry = ISBN.get(isbn)).nil? ? nil : entry.asin) }
      end
    end

    threads.each(&:join) # wait for all threads to finish

    success asins
  end

  ########### Testing API ############

  # Parameters: term
  # get the number of users
  get "/#{PASSWORD}/users/:term" do
    { count: Student.all().count }.to_json
  end

  # Parameters: term, fbid
  # get a user's schedule
  get "/#{PASSWORD}/schedule/:term/:fbid" do
    success Student.get(params[:fbid]).get_schedule(params[:term])
  end

  # Parameters: term, fbid
  # get a user's schedule image
  get "/#{PASSWORD}/schedule_image/:term/:fbid" do
    file_path = jpg_path(params[:term], params[:fbid])
    return error unless File.exists? file_path

    send_file file_path, type: :jpg
  end

  # Parameters: term, course, section (optional)
  # get a class roster
  get "/#{PASSWORD}/roster/:term/:course?/:section?" do
    success Course.roster(params[:term], params[:course], params[:section])
  end

  # Parameters: fbid, name, term, schedule
  # saves user's schedule information to a database. expects COURSE,SEC|COURSE,SEC.
  post "/#{PASSWORD}/add_schedule" do
    # fetch current user
    student = Student.new_student(params[:fbid], params[:name])
    return error if student.nil?

    # remove existing course entries
    return error unless student.delete_schedule(params[:term])

    # parse request parameters and add new course entries
    params[:schedule].split('|').each do |course_data|
      # delete schedule on error
      unless student.add_course(params[:term], *course_data.split(','))
        student.delete_schedule(params[:term])
        return error
      end
    end

    success
  end

  # Parameters: term, fbid
  # deletes a user's schedule
  post "/#{PASSWORD}/delete_schedule" do
    student = Student.get(params[:fbid])
    return error unless student.delete_schedule(params[:term])
    success
  end

  # Parameters: fbid
  # enables sharing for the current suer
  get "/#{PASSWORD}/enable_sharing" do
    return error if (student = Student.get(params[:fbid])).nil?
    student.enable_sharing
    success
  end

  # Parameters: fbid
  # disables sharing for the current user
  get "/#{PASSWORD}/disable_sharing" do
    return error if (student = Student.get(params[:fbid])).nil?
    student.disable_sharing
    success
  end

  ########### Error Handling ############

  error do
    return error
  end
end
