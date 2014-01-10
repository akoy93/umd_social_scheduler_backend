require 'rubygems'
require 'bundler'

Bundler.require

require './lib/app'
require './lib/db'
require './lib/helpers'

run SocialSchedulerController