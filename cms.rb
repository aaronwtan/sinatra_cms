require 'sinatra'
require 'sinatra/reloader'
require 'tilt/erubi'
require 'redcarpet'
require 'yaml'
require 'bcrypt'

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

def signed_in?
  session.key?(:username)
end

def require_signed_in_user
  return if signed_in?

  session[:error] = "You must be signed in to do that."
  redirect '/'
end

def load_user_credentials
  credentials_path = if ENV['RACK_ENV'] == 'test'
                       File.expand_path('../test/users.yml', __FILE__)
                     else
                       File.expand_path('../users.yml', __FILE__)
                     end

  YAML.load_file(credentials_path)
end

def valid_credentials?(username, password)
  credentials = load_user_credentials

  if credentials.key?(username)
    bcrypt_password = BCrypt::Password.new(credentials[username])
    return bcrypt_password == password
  end

  false
end

# View index page
get '/' do
  @files = Dir.glob('*', base: data_path)
  erb :index
end

# Render page to signin
get '/users/signin' do
  erb :signin
end

# Verify user credentials and signin
post '/users/signin' do
  username = params[:username]
  password = params[:password]

  if valid_credentials?(username, password)
    session[:username] = params[:username]
    session[:success] = "Welcome!"
    redirect '/'
  end

  session[:error] = "Invalid credentials"
  status 422
  erb :signin
end

# Signout
post '/users/signout' do
  session.delete(:username)
  session[:success] = "You have been signed out."
  redirect '/'
end

# Render page to create new document
get '/new' do
  require_signed_in_user

  erb :new
end

# Create new document
post '/create' do
  require_signed_in_user

  file_name = params[:file_name]

  if file_name.empty?
    session[:error] = "A name is required."
    status 422
    erb :new
  else
    file_path = File.join(data_path, file_name)
    File.write(file_path, '')

    session[:success] = "#{file_name} was created."
    redirect '/'
  end
end

# View document
get '/:file_name' do
  file_name = params[:file_name]
  file_path = File.join(data_path, File.basename(file_name))

  unless File.file?(file_path)
    session[:error] = "#{file_name} does not exist."
    redirect '/'
  end

  load_file_content(file_path)
end

# Render page for editing document
get '/:file_name/edit' do
  require_signed_in_user

  @file_name = params[:file_name]
  file_path = File.join(data_path, @file_name)
  @file_content = File.read(file_path)

  erb :edit
end

# Submit request with changes to edit document
post '/:file_name' do
  require_signed_in_user

  file_name = params[:file_name]
  file_path = File.join(data_path, file_name)
  content = params[:content]

  File.write(file_path, content)

  session[:success] = "#{file_name} has been updated."
  redirect '/'
end

# Delete a document
post '/:file_name/delete' do
  require_signed_in_user

  file_name = params[:file_name]
  file_path = File.join(data_path, file_name)

  File.delete(file_path)

  session[:success] = "#{file_name} has been deleted."
  redirect '/'
end
