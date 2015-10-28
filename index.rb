require 'sinatra'
require 'active_support/core_ext/time'
require 'haml'
require 'kramdown'
require 'yaml'
require 'timedcache'
require 'unirest'
require_relative 'lib/worldpay'

configure do
  # HAML should output with double vs single quotes for html attrs
  set :haml, :attr_wrapper => '"'

  # crude session handling, pid as secret, give each request a sequential id
  # store session objects in timed cache
  enable :sessions
  set :session_secret, Process.pid.to_s
  set :request_counter, 0
  set :session_data_cache, TimedCache.new

  # cache static assets for a day
  set :static_cache_control, [:public, max_age: 60 * 60 * 24]
  
  # read in installations on startup only
  # note, no validation here yet, so get the config right
  installations = Hash.new
  YAML.load_file('conf/installations.yaml').each do |installation|
    installations[installation['id'].to_s] = installation
  end
  set :installations, installations
end

helpers do
  def handle_user_timeout auth_valid_to
    if (Time.now.to_f * 1000.0).to_i > auth_valid_to
      @error_message = 'The time limit on completing your payment has expired.'
      halt haml :error
    end
  end
end

# basic handle that serves the readme
get '/' do
  @readme = File.read 'README.md'
  haml :index, :layout => false
end

# main handler for transaction post data
post '/fakepay-transaction' do
  # clear up any session data on the way in
  session.clear

  # store params as instance variable for the template
  @params = params

  # get installation and validate md5 hash
  installation_id = params['instId']
  @installation = settings.installations[installation_id]

  # check the installation matches something we have in the config
  if @installation.nil?
    @error_message = 'An invalid installation id was provided on the payment request.'
    halt haml :error
  end

  # check that the md5 hash matches what we expect it to
  md5_hash_valid = WorldPay.validate_md5_hash(params, @installation['md5_key'])
  if not md5_hash_valid
    @error_message = 'The payment request was invalid. Please check the MD5 keys match.'
    halt haml :error
  end

  # handle user timeout if necessary
  handle_user_timeout @params['authValidTo'].to_i

  # work out how long it is until the payment is no longer valid, only cache for that long
  cache_timeout = (@params['authValidTo'].to_i - Time.now.utc.to_i * 1000.0) / 1000

  # if we have a valid hash, store everything we know in a cheesy session data cache
  request_id = session[:request_id] = settings.request_counter += 1
  settings.session_data_cache.put(request_id, {:params => @params, :installation_id => installation_id}, cache_timeout)

  haml :make_payment_or_cancel
end

# handlers for completing or cancelling (the two user options)
# initiates the callback to the installation callback_url and
# serves the response page (if successful) or an error page
['/complete-payment', '/cancel-payment'].each do |path|
  get path do
    # retrieve stored data based on the request id
    request_id = session[:request_id]
    session_data_hash = settings.session_data_cache.get request_id

    if session_data_hash.nil?
      @error_message = 'Your session has timed out, please try again.'
      halt haml :error
    end

    @params = session_data_hash[:params]
    installation_id = session_data_hash[:installation_id]
    @installation = settings.installations[installation_id]

    # handle user timeout if necessary
    handle_user_timeout @params['authValidTo'].to_i

    # retain special "M_" parameters that were passed in from the original request
    callback_params = @params.clone.keep_if {|k,_| k.start_with? 'M_'}

    # add "auth" parameters
    callback_params['callbackPW'] = @installation['callback_password']
    if (path === '/complete-payment')
      callback_params['authAmount'] = @params['amount']
      callback_params['authCurrency'] = @params['currency']
      callback_params['transId'] = Time.now.utc.to_i # same number of digits as WorldPay transaction ids
      callback_params['transStatus'] = 'Y'
    else
      callback_params['transStatus'] = 'C'
    end

    # call back to the installation specified url
    begin
      response = Unirest.post @installation['callback_url'], parameters: callback_params
    rescue Exception => e
      @error_message = "Callback to #{@installation['callback_url']} failed, reason: '#{e.message}'."
      halt haml :error
    end

    if response.code != 200
      @error_message = "Callback to #{@installation['callback_url']} failed.<br>Status code '#{response.code}'."
      @error_detailed_content = response.raw_body
      halt haml :error
    end

    # tidy up after ourselves
    session.clear

    # serve out the response we were given (note that WorldPay performs arbitrary sanitisation which we're not doing)
    response.raw_body
  end
end

# dummy endpoint for testing the completion/cancel callbacks
post '/dump-params' do
  params.each do |k,v|
    puts "#{k} = #{v}"
  end
  'Hello, this is a callback response page.'
end

# service indicator
get '/service-status' do
  content_type 'text/plain'
  "Up and running: #{Time.now.to_formatted_s :db}" 
end
