require 'sinatra'
require 'sinatra/reloader'
require 'tilt/erubi'
require 'redcarpet'

configure do
  enable :sessions
  set :session_secret, SecureRandom.hex(32)
end

def render_markdown(text)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(text)
end

def data_path
  if ENV['RACK_ENV'] == 'test'
    File.expand_path('../test/data', __FILE__)
  else
    File.expand_path('../data', __FILE__)
  end
end

def load_file_content(path)
  content = File.read(path)

  case File.extname(path)
  when '.txt'
    headers['Content-Type'] = 'text/plain'
    content
  when '.md'
    erb render_markdown(content)
  end
end

# View index page
get '/' do
  @files = Dir.glob('*', base: data_path)
  erb :index
end

# View document
get '/:file_name' do
  file_name = params[:file_name]
  file_path = File.join(data_path, file_name)

  unless File.file?(file_path)
    session[:error] = "#{file_name} does not exist."
    redirect '/'
  end

  load_file_content(file_path)
end

# Render page for editing document
get '/:file_name/edit' do
  @file_name = params[:file_name]
  file_path = File.join(data_path, @file_name)
  @file_content = File.read(file_path)

  erb :edit_doc
end

# Submit request with changes to edit document
post '/:file_name' do
  file_name = params[:file_name]
  file_path = File.join(data_path, file_name)
  content = params[:content]

  File.write(file_path, content)

  session[:success] = "#{file_name} has been updated."

  redirect '/'
end
