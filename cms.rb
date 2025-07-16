require 'sinatra'
require 'sinatra/reloader'
require 'tilt/erubi'

root = File.expand_path('..', __FILE__)

configure do
  enable :sessions
  set :session_secret, SecureRandom.hex(32)
end

before do
  @files = Dir.glob('*', base: File.join(root, 'data'))
end

get '/' do
  erb :index
end

get '/:file_name' do
  file = params[:file_name]
  file_path = "#{root}/data/#{file}"

  unless File.file?(file_path)
    session[:error] = "#{file} does not exist."
    redirect '/'
  end

  headers['Content-Type'] = 'text/plain'
  File.read(file_path)
end
