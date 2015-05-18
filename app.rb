require 'sinatra'
require 'sinatra/activerecord'
require 'twilio-ruby'
require 'sendgrid-ruby'
require 'phonelib'
require 'csv'
require 'uri'
require 'will_paginate'
require 'will_paginate/active_record'
require 'cgi'

configure do 
  enable :sessions
  set :session_secret, 'nick is the man'
  Phonelib.default_country = "US"
  set :routing_logic, 'alphabetical'
end

configure :development do
  set :database, 'sqlite3:fsr.db'
  set :show_exceptions, true
  set :sendgrid_api_user, 'caseyclegg'
  set :sendgrid_api_key, 'tigerdude48'
  set :twilio_account_sid, 'AC0b9cb4818d124709a2828ee2ae6350be'
  set :twilio_auth_token, 'fac4836991adeb182ab32146a6204aae'
  set :base_url, 'http://caseyclegg.ngrok.com'
  set :email_from, 'casey@twilio.com'
  set :calls_sms_from, '+14156399429'
end

configure :production do
	db = URI.parse(ENV['DATABASE_URL'] || 'postgres:///localhost/mydb')

	ActiveRecord::Base.establish_connection(
		:adapter  => db.scheme == 'postgres' ? 'postgresql' : db.scheme,
		:host     => db.host,
		:username => db.user,
		:password => db.password,
		:database => db.path[1..-1],
		:encoding => 'utf8'
	)
  set :sendgrid_api_user, ENV['SENDGRID_API_USER']
  set :sendgrid_api_key, ENV['SENDGRID_API_KEY']
  set :twilio_account_sid, ENV['TWILIO_ACCOUNT_SID']
  set :twilio_auth_token, ENV['TWILIO_AUTH_TOKEN']
  set :base_url, ENV['BASE_URL']
  set :email_from, ENV['EMAILS_FROM']
  set :calls_sms_from, ENV['CALLS_SMS_FROM']
end

class Submission < ActiveRecord::Base
  belongs_to :recipient

  before_create do
    self.invalid_entry = self.email ? false : true
    self.invalid_entry = true if self.invalid_entry || (not Submission.where(emailAddress: self.emailAddress).where('created_at > ?', Time.now - 24.hours).empty?)
  end

  self.per_page = 20

  def name
    return URI.unescape(self.firstName)+' '+URI.unescape(self.lastName)
  end

  def email
    if self.emailAddress && /\A[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}+(\.[A-Z]{2,4})?\z/.match(URI.unescape(self.emailAddress))
      return URI.unescape(self.emailAddress || '').downcase
    else
      return nil
    end
  end

  def company_name
    return URI.unescape(self.company || '')
  end

  def description
    return URI.unescape(self.description1 || '')
  end

  def message
    if self.invalid_entry
      the_message = 'There is a duplicate FSR submission'
    else
      the_message = 'You have a new FSR submission, please reach out '
      the_message += self.recipient.work_hours? ? 'within the next hour.' : 'as soon as possible.'
    end
    return the_message
  end

  def email_message 
    the_message = self.message+' Here is the info:
    Company: '+self.company_name+'
    Name: '+self.name+'
    Email: '+(self.email || '')+'
    Phone: '+(self.phone || '')+'
    Description: '+self.description
    return the_message
  end

  def sms_message
    the_message = self.message+' Name: '+self.name+', Company: '+self.company_name+', Phone: '+self.phone
    return the_message
  end

  def twilio_gather_url
    return Sinatra::Application.settings.base_url+'/call_to_recipient?submission_id='+self.id.to_s
  end

  def phone
    if Phonelib.valid?(self.busPhone)
      return Phonelib.parse(URI.unescape(self.busPhone)).e164
    else
      return nil
    end
  end

  def assigned_recipient(routing_logic)
    if routing_logic == 'geographic'
      if self.country == 'United States'
        submitted_sub_country = self.usStates
      elsif self.country == 'Canada'
        submitted_sub_country = self.caTerritories
      else
        submitted_sub_country = ''
      end

      if Geo.find_by(country: self.country, sub_country: submitted_sub_country, zip_code: self.postal1)
        recipient = Geo.find_by(country: self.country, sub_country: submitted_sub_country, zip_code: self.postal1).recipient
        territory = Geo.find_by(country: self.country, sub_country: submitted_sub_country, zip_code: self.postal1).territory.name
      elsif Geo.find_by(country: self.country, sub_country: submitted_sub_country)
        recipient = Geo.find_by(country: self.country, sub_country: submitted_sub_country).recipient
        territory = Geo.find_by(country: self.country, sub_country: submitted_sub_country).territory.name
      elsif Geo.find_by(country: @submission.country)
        recipient = Geo.find_by(country: self.country).recipient
        territory = Geo.find_by(country: self.country).territory.name
      else
        recipient = Geo.find_by(country: '').recipient
        territory = 'none found'
      end
    elsif routing_logic == 'alphabetical'
      first_email_letter = self.email[0]
      if Geo.find_by(starting_letter: first_email_letter)
        recipient = Geo.find_by(starting_letter: first_email_letter).recipient
        territory = Geo.find_by(starting_letter: first_email_letter).territory.name
      else
        recipient = Geo.find_by(starting_letter: '').recipient
        territory = Geo.find_by(starting_letter: '').territory.name
      end
    end
    return recipient, territory
  end

end

class Geo < ActiveRecord::Base
  belongs_to :territory
  has_one :recipient, :through => :territory
  validates :starting_letter, format: { with: /\A[a-z]?\z/ }
end

class Territory < ActiveRecord::Base
  belongs_to :recipient
  has_many :geos
end

class Recipient < ActiveRecord::Base
  has_many :territories
  has_many :geos, :through => :territories
  has_many :submissions
  validates :phone, phone: true
  before_save { self.phone = Phonelib.parse(self.phone).e164 }

  def work_hours?
    work_hours = false
    offset = case self.hours
      when 'emea' then 0
      when 'et' then -4
      when 'ct' then -5
      when 'mt' then -6
      when 'pt' then -7
      else -7
      end
    now = Time.now.getgm+offset*60*60
    work_hours = true if now >= Time.new(Time.now.year,Time.now.month,Time.now.day,9,0,0,0) && now <= Time.new(Time.now.year,Time.now.month,Time.now.day,17,0,0,0)
    work_hours = false if now.saturday? || now.sunday?
    return work_hours
  end
end

class User < ActiveRecord::Base
  before_save { self.email = email.downcase }
  before_create :create_remember_token
  VALID_EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i
  validates :email, presence: true, format: { with: VALID_EMAIL_REGEX },
                                               uniqueness: { case_sensitive: false }
  validates :password, length: { minimum: 6 }

  def User.new_remember_token
    SecureRandom.urlsafe_base64
  end

  def User.encrypt(token)
    Digest::SHA1.hexdigest(token.to_s)
  end

  private

    def create_remember_token
      self.remember_token = User.encrypt(User.new_remember_token)
    end
end

class String
  def pretty_phone
    the_match = /\A\+1(\d{3})(\d{3})(\d{4})\z/.match(self)
    the_match ? the_match[1]+'-'+the_match[2]+'-'+the_match[3] : nil
  end

  def is_blank?
    self[0].nil? ? true : false
  end

  def intl_phone
    the_match = /\A(\+1|1 ?)?(\()?(\d{3})(\) |\.| |-)?(\d{3})(-|\.| )?(\d{4})\z/.match(self.strip)
    the_match ? '+1'+the_match[3]+the_match[5]+the_match[7] : nil
  end
end

class NilClass
  def is_blank?
    return true
  end
end

helpers do
  def sign_in(user)
    remember_token = User.new_remember_token
    session[:remember_token] = remember_token
    user.update_attribute(:remember_token, User.encrypt(remember_token))
    self.current_user = user
  end

  def signed_in?
    !current_user.nil?
  end

  def current_user=(user)
    @current_user = user
  end

  def current_user
    remember_token = User.encrypt(session[:remember_token])
    @current_user ||= User.find_by(remember_token: remember_token)
  end

  def sign_out
    current_user.update_attribute(:remember_token,
                                  User.encrypt(User.new_remember_token))
    session.clear
    self.current_user = nil
  end
end

post '/submissions' do 
  @submission = Submission.create(
    all_params: URI.escape(params.to_s),
    busPhone: URI.escape(params[:busPhone] || ''),
    caTerritories: URI.escape(params[:caTerritories] || ''),
    company: URI.escape(params[:company] || ''),
    country: URI.escape(params[:country] || ''),
    description1: URI.escape(params[:paragraphText2] || ''),
    emailAddress: URI.escape(params[:emailAddress] || ''),
    firstName: URI.escape(params[:firstName] || ''),
    jobRole: URI.escape(params[:jobRole] || ''),
    lastName: URI.escape(params[:lastName] || ''),
    postal1: URI.escape(params[:postal1] || ''),
    ukBoroughs: URI.escape(params[:ukBoroughs] || ''),
    usStates: URI.escape(params[:usStates] || ''),
    status: '')

  if @submission.invalid_entry
    if @submission.email
      @submission.status += 'duplicate entry'
      recipient, territory = @submission.assigned_recipient(settings.routing_logic)
      @submission.recipient_id = recipient.id
      email_subject = 'Duplicate FSR Submission in last 24 hours - '+@submission.company
  
      begin
        @sendgrid_client = SendGrid::Client.new(api_user: settings.sendgrid_api_user, api_key: settings.sendgrid_api_key)
        @sendgrid_client.send(SendGrid::Mail.new(to: [@submission.recipient.email, 'emerald@twilio.com'], from: settings.email_from, subject: email_subject, text: @submission.email_message))
        @submission.status += ', sent email'
      rescue Exception => e
        @submission.status += ', error on sending email, '+e.to_s
      end
    else
      @submission.status += 'email address invalid, lead not assigned'
    end
    @submission.save
  else
    recipient, territory = @submission.assigned_recipient(settings.routing_logic)

    @submission.recipient_id = recipient.id
    @submission.status += 'territory: '+territory+'! recipient: '+@submission.recipient.name+' - '+@submission.recipient.email
    @submission.status += recipient.work_hours? ? '! during work hours' : '! outside of work hours'
    @submission.save

    email_subject = 'New FSR Submission - '+@submission.company
  
    begin 
      @sendgrid_client = SendGrid::Client.new(api_user: settings.sendgrid_api_user, api_key: settings.sendgrid_api_key)
      @sendgrid_client.send(SendGrid::Mail.new(to: @submission.recipient.email, from: settings.email_from, subject: email_subject, text: @submission.email_message))
      @submission.status += '! sent email'
    rescue Exception => e
      @submission.status += '! error on sending email, '+e.to_s
    end
    @submission.save

    if recipient.work_hours?
      if @submission.phone.nil?
        @submission.status += '! no call made because phone number was blank or invalid'
      else
        sleep(5.minutes)
        @twilio_client = Twilio::REST::Client.new settings.twilio_account_sid, settings.twilio_auth_token
        begin
          @call = @twilio_client.calls.create(
            from: settings.calls_sms_from,
            to: @submission.recipient.work_phone,
            url: @submission.twilio_gather_url,
            method: 'GET'
          ) 
          @submission.status += '! call made to bdr' 
        rescue Exception => e
          @submission.status += '! error on making call, '+e.to_s
        end
      end
      @submission.save
    end
  end
end

get '/call_to_recipient' do
  if params[:submission_id] 
    @submission = Submission.find(params[:submission_id].to_i)

    if params[:Digits].nil? || params[:Digits] == '2'
      erb :'twiml/call', :layout => false
    elsif params[:Digits] == '1'
      @submission.status += ', connected call with client'
      @submission.save
      @recipient = @submission.recipient
      erb :'twiml/connect_call', :layout => false
    else
      begin
        @twilio_client = Twilio::REST::Client.new settings.twilio_account_sid, settings.twilio_auth_token
        @twilio_client.messages.create(
          from: settings.calls_sms_from,
          to: @submission.recipient.phone,
          body: @submission.sms_message
        )
        @submission.status += '! sent sms message'
        @submission.save
      rescue Exception => e
        @submission.status += '! error on sending sms, '+e.to_s
        @submission.save
      end
      erb :'twiml/end_call', :layout => false
    end
  end
end

get '/sign_in' do 
  @title = 'Sign in'
  erb :sign_in
end

post '/session' do 
  user = User.find_by(email: params[:email].downcase)
  if user && user.password == params[:password]
    sign_in user
    redirect to('/')
  else
    @alert = 'invalid email/password combination'
    redirect to('sign_in')
  end
end 

delete '/session' do
  session.clear
  redirect to('/')
end

#changes need to have the correct permissions
error 403 do
  'Access forbidden'
end

post %r{.*} do
  403 unless signed_in?
  pass
end

get %r{.*} do 
  redirect to('/sign_in') unless signed_in?
  pass
end

get '/' do 
  redirect to('/submissions')
end

get '/recipients' do
  @recipients = Recipient.all.order('name')
  @active_area = 'recipients'
  erb :recipients
end

get '/recipients/:id/edit' do
  @recipient = Recipient.find(params[:id])
  @active_area = 'recipients'
  erb :recipient_edit
end

get '/recipients/new' do
  @recipient = Recipient.new
  @active_area = 'recipients'
  erb :recipient_new
end

put '/recipients/:id' do
  @recipient = Recipient.find(params[:id])
  @recipient.name = params[:name]
  @recipient.email = params[:email]
  @recipient.phone = params[:phone].intl_phone
  @recipient.work_phone = params[:work_phone].intl_phone
  @recipient.hours = params[:hours]
  @recipient.save
  redirect to('/recipients')
end

delete '/recipients/:id' do
  @recipient = Recipient.find(params[:id])
  @recipient.destroy
  redirect to('/recipients')
end

post '/recipients' do
  @recipient = Recipient.new
  @recipient.name = params[:name]
  @recipient.email = params[:email]
  @recipient.phone = params[:phone].intl_phone
  @recipient.work_phone = params[:work_phone].intl_phone
  @recipient.hours = params[:hours]
  @recipient.save
  redirect to('/recipients')
end

get '/territories' do
  @territories = Territory.where(routing_type: settings.routing_logic).order('name')
  @active_area = 'territories'
  erb :territories
end

get '/territories/new' do
  @territory = Territory.new
  @recipients = Recipient.all
  @active_area = 'territories'
  erb :territory_new
end

get '/territories/:id/edit' do
  @territory = Territory.find(params[:id])
  @recipients = Recipient.all
  @active_area = 'territories'
  erb :territory_edit
end

put '/territories/:id' do
  @territory = Territory.find(params[:id])
  @territory.name = params[:name]
  @territory.recipient_id = params[:recipient_id]
  @territory.save
  redirect to('/territories')
end

post '/territories' do
  @territory = Territory.new
  @territory.name = params[:name]
  @territory.recipient_id = params[:recipient_id]
  @territory.routing_type = settings.routing_logic
  @territory.save
  redirect to('/territories')
end

get '/geos' do
  if settings.routing_logic == 'geographic'
    @geos = Geo.where(starting_letter: nil).order('area, country, sub_country, zip_code')
  else
    @geos = Geo.where.not(starting_letter: nil).order('starting_letter')
  end
  @territories = Territory.where(routing_type: settings.routing_logic)
  @active_area = 'geos'
  erb :geos
end

put '/geos/:id' do
  @geo = Geo.find(params[:id])
  @geo.territory_id = params[:territory_id]
  @geo.save
  redirect to('/geos')
end

get '/submissions/?:invalid?.?:format?' do
  if params[:invalid] == 'invalid'
    @submissions = Submission.where(invalid_entry: true)
    @active_area = 'invalid_submissions'
  else
    @submissions = Submission.where.not(invalid_entry: true)
    @active_area = 'submissions'
  end

  if params[:format]=='csv'
    days_ago = params[:days_ago] =~ /\A\d+\Z/ ? params[:days_ago].to_i : nil
    if days_ago
      @submissions = @submissions.where(created_at: Time.now.midnight - days_ago.days..Time.now.midnight).order('created_at DESC')
    else
      @submissions = @submissions.order('created_at DESC')
    end
    headers \
      'Content-Disposition' => "attachment; filename=\"fsr-submission.csv\"", 
      'Content-Type' =>'text/csv'
    erb :'submission_log_dump.csv', :layout => false
  else
    @submissions = @submissions.page(params[:page]).order('created_at DESC')
    erb :submissions
  end
end

