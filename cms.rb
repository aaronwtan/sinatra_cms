require 'sinatra'
require 'sinatra/reloader'

# Enable ERB templating
require 'tilt/erubi'

# Enable Markdown conversion to HTML
require 'redcarpet'

require 'yaml'

# Enable hash encryption using BCrypt
require 'bcrypt'

require 'pry'
configure do
  enable :sessions
  set :session_secret, SecureRandom.hex(32)
end

VALID_FILE_EXT = %w(.txt .md .jpg).freeze

def render_markdown(text)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(text)
end

def root_path
  if ENV['RACK_ENV'] == 'test'
    File.expand_path('../test', __FILE__)
  else
    File.expand_path('..', __FILE__)
  end
end

def users_path
  File.join(root_path, 'users.yml')
end

def data_path
  if ENV['RACK_ENV'] == 'test'
    File.expand_path('../test/data', __FILE__)
  else
    File.expand_path('../data', __FILE__)
  end
end

def load_file_content(path)
  @content = File.read(path)

  case File.extname(path)
  when '.txt'
    erb :content
  when '.md'
    erb render_markdown(@content)
  end
end

def valid_file_ext?(file_name)
  VALID_FILE_EXT.include?(File.extname(file_name))
end

def file_name_error(file_name)
  if file_name.empty?
    "A name is required."
  elsif !valid_file_ext?(file_name)
    "Invalid file extension. Supported extensions are #{VALID_FILE_EXT.join(', ')}"
  elsif File.exist?(File.join(data_path, file_name))
    "'#{file_name}' already exists."
  end
end

def validate_file_name(file_name)
  error = file_name_error(file_name)

  return unless error

  session[:error] = error
  status 422
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
  YAML.load_file(users_path)
end

def load_signed_in_user_credentials(username)
  current_user = load_user_credentials[username]
  session[:username] = username
  session[:phone] = current_user['phone']
  session[:email] = current_user['email']
  session[:nickname] = current_user['nickname']
end

def valid_credentials?(username, password, credentials)
  if credentials.key?(username)
    bcrypt_password = BCrypt::Password.new(credentials[username]['password'])
    return bcrypt_password == password
  end

  false
end

def new_credentials_error
  credentials = load_user_credentials

  username = params[:username].downcase
  password = params[:password]
  confirm_password = params[:confirm_password]
  signup_code = params[:signup_code].to_i

  error = []

  error << "'#{username}' already taken. Please choose a different username." if credentials.key?(username)
  error << 'Passwords do not match.' if password != confirm_password
  error << 'Invalid signup code.' if signup_code != credentials['SIGNUP_CODE']

  error
end

def save_optional_field(field)
  (params[field].nil? || params[field].empty?) ? nil : params[field]
end

def save_new_credentials
  credentials = load_user_credentials
  credentials_path = if ENV['RACK_ENV'] == 'test'
                       File.expand_path('../test/users.yml', __FILE__)
                     else
                       File.expand_path('../users.yml', __FILE__)
                     end

  credentials[params[:username].downcase] = {
    'password' => BCrypt::Password.create(params[:password]).to_s,
    'phone' => save_optional_field(:phone),
    'email' => save_optional_field(:email),
    'nickname' => save_optional_field(:nickname)
  }

  File.write(credentials_path, YAML.dump(credentials))
end

helpers do
  def display_name
    session[:nickname] || session[:username]
  end

  def display_flash_messages(type, &view_block)
    if block_given?
      if session[type].is_a?(Array)
        session[type].each(&view_block)
        session[type] = nil
      else
        yield session.delete(type)
      end
    else
      session.delete(type)
    end
  end
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
  credentials = load_user_credentials
  username = params[:username].strip.downcase
  password = params[:password]

  if valid_credentials?(username, password, credentials)
    load_signed_in_user_credentials(username)
    session[:success] = "Welcome #{username}!"
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

# Render page to signup
get '/users/signup' do
  erb :signup
end

# Signup for a new account
post '/users/signup' do
  username = params[:username].downcase
  error = new_credentials_error

  if error.empty?
    save_new_credentials
    load_signed_in_user_credentials(username)
    session[:success] = "Welcome #{display_name}! Your account has been successfully created."
    redirect '/'
  end

  session[:error] = error
  status 422
  erb :signup
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
  validate_file_name(file_name)

  unless status == 422
    file_path = File.join(data_path, file_name)
    File.write(file_path, '')

    session[:success] = "'#{file_name}' was created."
    redirect '/'
  end

  erb :new
end

# View document
get '/:file_name' do
  file_name = params[:file_name]
  file_path = File.join(data_path, File.basename(file_name))

  unless File.file?(file_path)
    session[:error] = "'#{file_name}' does not exist."
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

  session[:success] = "'#{file_name}' has been updated."
  redirect '/'
end

# Copy an existing document to a new document
post '/:file_name/copy' do
  require_signed_in_user

  old_file_name = params[:file_name]
  old_file_path = File.join(data_path, old_file_name)
  old_file_content = File.read(old_file_path)

  new_file_name = old_file_name.dup.insert(old_file_name.rindex('.'), ' copy')

  validate_file_name(new_file_name)

  redirect '/' if status == 422

  new_file_path = File.join(data_path, new_file_name)
  File.write(new_file_path, old_file_content)

  session[:success] = "'#{old_file_name}' has been copied to '#{new_file_name}'."
  redirect '/'
end

# Delete a document
post '/:file_name/delete' do
  require_signed_in_user

  file_name = params[:file_name]
  file_path = File.join(data_path, file_name)

  File.delete(file_path)

  session[:success] = "'#{file_name}' has been deleted."
  redirect '/'
end
