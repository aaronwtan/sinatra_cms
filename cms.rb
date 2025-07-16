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

def load_file_content(path)
  content = File.read(path)

  case File.extname(path)
  when '.txt'
    headers['Content-Type'] = 'text/plain'
    content
  when '.md'
    render_markdown(content)
  end
end

root = File.expand_path('..', __FILE__)

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

  load_file_content(file_path)
end
