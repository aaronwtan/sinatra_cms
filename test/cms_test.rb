ENV['RACK_ENV'] = 'test'
YAML_TEST_STR = {
  "SIGNUP_CODE" => 123456,
  "admin" => { "password" => "$2a$12$VY1pTeZDFgESxZD78CDPdesRobTiMcGPhpa3nSiqFoeg8eGXmDiP2" } 
}

require 'minitest/autorun'
require 'rack/test'
require 'fileutils'
require 'pry'

require_relative '../cms'

class CMSTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    FileUtils.mkdir_p(data_path)
    File.write(users_path, YAML.dump(YAML_TEST_STR))
  end

  def teardown
    FileUtils.rm_rf(data_path)
    FileUtils.remove_file(users_path, force: true)
  end

  def create_document(name, content = '')
    File.open(File.join(data_path, name), 'w') do |file|
      file.write(content)
    end
  end

  def session
    last_request.env['rack.session']
  end

  def admin_session
    { 'rack.session' => { username: 'admin' } }
  end

  def test_index
    create_document 'about.md'
    create_document 'changes.txt'
    create_document 'history.txt'

    get '/'
    assert_equal 200, last_response.status
    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']
    assert_includes last_response.body, 'about.md'
    assert_includes last_response.body, 'changes.txt'
    assert_includes last_response.body, 'history.txt'
  end

  def test_viewing_text_document
    create_document 'history.txt', '2022 - Ruby 3.2 released.'

    get '/history.txt'
    assert_equal 200, last_response.status
    assert_includes last_response.body, '2022 - Ruby 3.2 released.'
  end

  def test_viewing_nonexistent_document
    get '/notafile.ext'
    assert_equal "'notafile.ext' does not exist.", session[:error]
    assert_equal 302, last_response.status
    assert_empty last_response.body
  end

  def test_viewing_markdown_document
    create_document 'about.md', '# Ruby is...
                                A dynamic, open source programming language'

    get '/about.md'
    assert_equal 200, last_response.status
    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']
    assert_includes last_response.body, '<h1>Ruby is...</h1>'
  end

  def test_editing_document
    create_document 'changes.txt'

    get '/changes.txt/edit', {}, admin_session
    assert_equal 200, last_response.status
    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']
    assert_includes last_response.body, '<textarea'
    assert_includes last_response.body, '<button type="submit"'
  end

  def test_editing_document_signed_out
    create_document 'changes.txt'

    get '/changes.txt/edit'
    assert_equal 302, last_response.status
    assert_equal 'You must be signed in to do that.', session[:error]
  end

  def test_updating_document
    post '/changes.txt', { content: 'new content' }, admin_session
    assert_equal "'changes.txt' has been updated.", session[:success]
    assert_equal 302, last_response.status

    get '/changes.txt'
    assert_equal 200, last_response.status
    assert_includes last_response.body, 'new content'
  end

  def test_updating_document_signed_out
    post '/changes.txt', content: 'new content'
    assert_equal 302, last_response.status
    assert_equal 'You must be signed in to do that.', session[:error]
  end

  def test_copying_document
    create_document 'test.txt'
    post '/test.txt', { content: 'test content' }, admin_session

    post '/test.txt/copy', {}, admin_session
    assert_equal "'test.txt' has been copied to 'test copy.txt'.", session[:success]
    assert_equal 302, last_response.status

    get '/'
    assert_includes last_response.body, 'test copy.txt'

    get '/test.txt'
    assert_includes last_response.body, 'test content'

    get '/test%20copy.txt'
    assert_includes last_response.body, 'test content'
  end

  def test_copying_document_signed_out
    create_document 'test.txt'

    post '/test.txt/copy'
    assert_equal 302, last_response.status
    assert_equal 'You must be signed in to do that.', session[:error]
  end

  def test_viewing_new_document_form
    get '/new', {}, admin_session
    assert_equal 200, last_response.status
    assert_includes last_response.body, '<input'
    assert_includes last_response.body, '<button type="submit"'
  end

  def test_viewing_new_document_form_signed_out
    get '/new'
    assert_equal 302, last_response.status
    assert_equal 'You must be signed in to do that.', session[:error]
  end

  def test_creating_new_document
    post '/create', { file_name: 'test.txt' }, admin_session
    assert_equal "'test.txt' was created.", session[:success]
    assert_equal 302, last_response.status

    get '/'
    assert_includes last_response.body, 'test.txt'
  end

  def test_creating_new_document_without_file_name
    post '/create', { file_name: '' }, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, 'A name is required.'
  end

  def test_creating_new_document_without_file_extension
    post '/create', { file_name: 'test' }, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, "Invalid file extension. Supported extensions are #{VALID_FILE_EXT.join(', ')}"
  end

  def test_creating_new_document_with_invalid_file_extension
    post '/create', { file_name: 'test.js' }, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, "Invalid file extension. Supported extensions are #{VALID_FILE_EXT.join(', ')}"
  end

  def test_creating_new_document_signed_out
    post '/create', file_name: 'test.txt'
    assert_equal 302, last_response.status
    assert_equal 'You must be signed in to do that.', session[:error]
  end

  def test_deleting_document
    create_document 'test.txt'

    post '/test.txt/delete', {}, admin_session
    assert_equal "'test.txt' has been deleted.", session[:success]
    assert_equal 302, last_response.status

    get '/'
    refute_includes last_response.body, 'href="test.txt"'
  end

  def test_deleting_document_signed_out
    create_document 'test.txt'

    post 'test.txt/delete'
    assert_equal 302, last_response.status
    assert_equal 'You must be signed in to do that.', session[:error]
  end

  def test_viewing_sign_in_form
    get '/users/signin'
    assert_equal 200, last_response.status
    assert_includes last_response.body, '<input'
    assert_includes last_response.body, '<button type="submit"'
  end

  def test_signin
    post '/users/signin', username: 'admin', password: 'secret'
    assert_equal 'Welcome admin!', session[:success]
    assert_equal 'admin', session[:username]
    assert_equal 302, last_response.status

    get last_response['Location']
    assert_includes last_response.body, 'Signed in as admin.'
  end

  def test_signin_with_invalid_credentials
    post '/users/signin', username: 'test', password: 'notasecret'
    assert_nil session[:username]
    assert_equal 422, last_response.status
    assert_includes last_response.body, 'Invalid credentials'
  end

  def test_signout
    get '/', {}, { 'rack.session' => { username: 'admin' } }
    assert_equal 'admin', session[:username]
    assert_includes last_response.body, 'Signed in as admin.'
    assert_includes last_response.body, 'SIGN OUT'

    post '/users/signout'
    assert_equal 'You have been signed out.', session[:success]
    assert_nil session[:username]
    assert_equal 302, last_response.status

    get last_response['Location']
    assert_nil session[:username]
    assert_includes last_response.body, 'SIGN IN'
  end

  def test_viewing_signup_form
    get '/users/signup'
    assert_equal 200, last_response.status
    assert_includes last_response.body, '<input'
    assert_includes last_response.body, '<button type="submit"'
  end

  def test_signup
    post '/users/signup',
         {
           username: 'dev',
           password: 'password',
           confirm_password: 'password',
           signup_code: 123456,
           phone: '123-456-7890',
           email: 'dev@dev.com',
           nickname: 'Super Dev'
         }
    assert_equal 'Welcome Super Dev! Your account has been successfully created.', session[:success]
    assert_equal 'dev', session[:username]
    assert_equal 'Super Dev', session[:nickname]
    assert_equal '123-456-7890', session[:phone]
    assert_equal 'dev@dev.com', session[:email]
    assert_equal 302, last_response.status

    get last_response['Location']
    assert_includes last_response.body, 'Signed in as Super Dev.'
  end

  def test_signup_with_empty_optional_fields
    post '/users/signup',
         {
           username: 'dev',
           password: 'password',
           confirm_password: 'password',
           signup_code: 123456
         }
    assert_equal 'Welcome dev! Your account has been successfully created.', session[:success]
    assert_equal 'dev', session[:username]
    assert_nil session[:nickname]
    assert_nil session[:phone]
    assert_nil session[:email]
    assert_equal 302, last_response.status

    get last_response['Location']
    assert_includes last_response.body, 'Signed in as dev.'
  end

  def test_signup_with_existing_username
    post '/users/signup',
         {
           username: 'admin',
           password: 'password',
           confirm_password: 'password',
           signup_code: 123456
         }
    assert_includes last_response.body, "'admin' already taken. Please choose a different username."
    assert_equal 422, last_response.status
  end

  def test_signup_with_failed_password_confirmation
    post '/users/signup',
         {
           username: 'dev',
           password: 'password',
           confirm_password: 'notpassword',
           signup_code: 123456
         }
    assert_includes last_response.body, 'Passwords do not match.'
    assert_equal 422, last_response.status
  end

  def test_signup_with_invalid_signup_code
    post '/users/signup',
         {
           username: 'dev',
           password: 'password',
           confirm_password: 'password',
           signup_code: 654321
         }
    assert_includes last_response.body, 'Invalid signup code.'
    assert_equal 422, last_response.status
  end

  def test_signup_with_multiple_validation_errors
    post '/users/signup',
         {
           username: 'admin',
           password: 'password',
           confirm_password: 'notpassword',
           signup_code: 654321
         }
    assert_includes last_response.body, "'admin' already taken. Please choose a different username."
    assert_includes last_response.body, 'Passwords do not match.'
    assert_includes last_response.body, 'Invalid signup code.'
    assert_equal 422, last_response.status
  end
end
