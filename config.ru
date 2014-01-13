require 'rubygems'
require 'bundler'

Bundler.require

require './lib/app'
require './lib/db'
require './lib/helpers'

# store session data for 1 day
use Rack::Session::Pool, :expire_after => 86400

run SocialSchedulerController