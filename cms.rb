require 'sinatra'
require 'sinatra/reloader'
require 'tilt/erubi'

root = File.expand_path('..', __FILE__)

get '/' do
  @files = Dir.glob('*', base: File.join(root, 'data'))

  erb :index
end

get '/:file_name' do
  file = params[:file_name]
  file_path = "#{root}/data/#{file}"

  headers['Content-Type'] = 'text/plain'
  File.read(file_path)
end
