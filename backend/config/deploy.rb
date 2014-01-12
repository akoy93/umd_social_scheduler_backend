require 'bundler/capistrano'

server "173.245.5.162:2200", :web, :app, :db, primary: true
set :rack_env, :production

#general info
set :application, "umd-social-scheduler"
set :user, 'root'
set :domain, "www.umdsocialscheduler.com"
set :use_sudo, false

set :scm, 'git'
set :repository, "git@github.com:akoy93/umd-social-scheduler.git"
set :branch, 'master'

role :web, domain                          # Your HTTP server, Apache/etc
role :app, domain                          # This may be the same as your `Web` server
role :db,  domain, :primary => true # This is where Rails migrations will run

#deploy config
set :deploy_to, "/home/umd-social-scheduler"
set :deploy_via, :remote_cache

#addition settings. mostly ssh
ssh_options[:forward_agent] = true
default_run_options[:pty] = true

# After an initial (cold) deploy, symlink the app and restart nginx
after "deploy:cold" do
  admin.nginx_restart
end

# As this isn't a rails app, we don't start and stop the app invidually
namespace :deploy do
  desc "Not starting as we're running passenger."
  task :start do
  end

  desc "Not stopping as we're running passenger."
  task :stop do
  end

  desc "Restart the app."
  task :restart, roles: :app, except: { :no_release => true } do
    run "touch #{File.join(current_path,'tmp','restart.txt')}"
  end

  # This will make sure that Capistrano doesn't try to run rake:migrate (this is not a Rails project!)
  task :cold do
    deploy.update
    deploy.start
  end
end

namespace :admin do
  desc "Restart nginx."
  task :nginx_restart, roles: :app do
    run "#{sudo} /etc/init.d/nginx restart"
  end
end