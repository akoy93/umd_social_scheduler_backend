require 'rubygems'
require 'bundler'

Bundler.require

# store session data for 1 day
use Rack::Session::Pool, :expire_after => 86400

require './lib/app'
require './lib/db'
require './lib/helpers'

run SocialSchedulerController