require 'rubygems'
require 'bundler'

Bundler.require

require './lib/app'
require './lib/db'
require './lib/helpers'

require 'rack/session/moneta'

# use redis for persistent session management
use Rack::Session::Moneta, :store => :Redis

run SocialSchedulerController