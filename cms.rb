require 'sinatra'
require 'sinatra/reloader'
require 'tilt/erubi'

root = File.expand_path('..', __FILE__)

get '/' do
  @files = Dir.glob('*', base: File.join(root, 'data'))

  erb :index
end
