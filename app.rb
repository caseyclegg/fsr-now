require 'sinatra'
require 'sinatra/activerecord'
require 'twilio-ruby'
require 'sendgrid-ruby'

configure :development do
  set :database, 'sqlite3:fsr.db'
  set :show_exceptions, true
  set :sendgrid_api_user, 'caseyclegg'
  set :sendgrid_api_key, 'tigerdude48'
  set :twilio_account_sid, 'AC0b9cb4818d124709a2828ee2ae6350be'
  set :twilio_auth_token, 'fac4836991adeb182ab32146a6204aae'
  set :base_url, 'http://caseyclegg.ngrok.com'
  set :email_from, 'casey@twilio.com'
  set :calls_sms_from, '+14156399428'
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
  set :twilio_account_sid, ENV['TWILIO_ACCOUNT_SID'] ||'ACccf36b345e29dd57b9c0eee6fe1313c6'
  set :twilio_auth_token, ENV['TWILIO_AUTH_TOKEN'] || '1f5de95513ae08c8c6fd4a8babe68457'
  set :base_url, ENV['BASE_URL']
  set :email_from, ENV['EMAILS_FROM']
  set :calls_sms_from, ENV['CALLS_SMS_FROM']
end

class Submission < ActiveRecord::Base
  belongs_to :recipient

  def name
    return self.firstName+' '+self.lastName
  end

  def message
    the_message = 'You have a new FSR submission, please reach out '
    the_message += self.recipient.work_hours? ? 'within the next hour.' : 'as soon as possible.'
    return the_message
  end

  def email_message 
    the_message = self.message+' Here is the info:
    Company: '+self.company+'
    Name: '+self.name+'
    Email: '+self.emailAddress+'
    Phone: '+self.busPhone+'
    Description: '+self.description1
    return the_message
  end

  def sms_message
    the_message = self.message+' Name: '+self.name+', Company: '+self.company+', Phone: '+self.busPhone
    return the_message
  end

  def twilio_gather_url
    return Sinatra::Application.settings.base_url+'/call_to_recipient?submission_id='+self.id.to_s
  end

  def phone
    self.busPhone.intl_phone
  end

end

class Geo < ActiveRecord::Base
  belongs_to :territory
  has_one :recipient, :through => :territory
end

class Territory < ActiveRecord::Base
  belongs_to :recipient
  has_many :geos
end

class Recipient < ActiveRecord::Base
  has_many :territories
  has_many :geos, :through => :territories
  has_many :submissions

  def work_hours?
    work_hours = false
    if self.hours == 'emea'
      work_hours = true if Time.now >= '09:00:00 GMT' && Time.now <= '17:00:00 GMT'
    else
      work_hours = true #if Time.now >= '09:00:00 PT' && Time.now <= '17:00:00 PT'
    end
    return work_hours
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
  
end

#static pages and sign in
get '/recipients' do
  @recipients = Recipient.all
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
  @recipient.hours = params[:hours]
  @recipient.save
  redirect to('/recipients')
end

post '/recipients' do
  @recipient = Recipient.new
  @recipient.name = params[:name]
  @recipient.email = params[:email]
  @recipient.phone = params[:phone].intl_phone
  @recipient.hours = params[:hours]
  @recipient.save
  redirect to('/recipients')
end

get '/territories' do
  @territories = Territory.all
  @recipients = Recipient.all
  @active_area = 'territories'
  erb :territories
end

get '/territories/new' do
  @territory = Territory.new
  @recipients = Recipient.all
  @active_area = 'territories'
  erb :territory_new
end

put '/territories/:id' do
  @territory = Territory.find(params[:id])
  @territory.recipient_id = params[:recipient_id]
  @territory.save
  redirect to('/territories')
end

post '/territories' do
  @territory = Territory.new
  @territory.name = params[:name]
  @territory.recipient_id = params[:recipient_id]
  @territory.save
  redirect to('/territories')
end

get '/geos' do
  @geos = Geo.all.order('area, country, sub_country, zip_code')
  @territories = Territory.all
  @active_area = 'geos'
  erb :geos
end

put '/geos/:id' do
  @geo = Geo.find(params[:id])
  @geo.territory_id = params[:territory_id]
  @geo.save
  redirect to('/geos')
end

get '/submissions' do
  @submissions = Submission.all.order('created_at DESC')
  erb :submissions
end

post '/submissions' do 
	@submission = Submission.new
	@submission.all_params = params.to_s
  @submission.busPhone = params[:busPhone] || ''
  @submission.caTerritories = params[:caTerritories] || ''
	@submission.company = params[:company] || ''
  @submission.country = params[:country] || ''
  @submission.description1 = params[:description1] || ''
  @submission.emailAddress = params[:emailAddress] || ''
  @submission.firstName = params[:firstName] || ''
  @submission.jobRole = params[:jobRole] || ''
  @submission.lastName = params[:lastName] || ''
  @submission.postal1 = params[:postal1] || ''
  @submission.ukBoroughs = params[:ukBoroughs] || ''
  @submission.usStates = params[:usStates] || ''

  @submission.status =''
  @submission.save

  if @submission.country == 'United States'
    submitted_sub_country = @submission.usStates
  elsif @submission.country == 'Canada'
    submitted_sub_country = @submission.caTerritories
  else
    submitted_sub_country = ''
  end

  if Geo.find_by(country: @submission.country, sub_country: submitted_sub_country, zip_code: @submission.postal1)
    recipient = Geo.find_by(country: @submission.country, sub_country: submitted_sub_country, zip_code: @submission.postal1).recipient
    territory = Geo.find_by(country: @submission.country, sub_country: submitted_sub_country, zip_code: @submission.postal1).territory.name
  elsif Geo.find_by(country: @submission.country, sub_country: submitted_sub_country)
    recipient = Geo.find_by(country: @submission.country, sub_country: submitted_sub_country).recipient
    territory = Geo.find_by(country: @submission.country, sub_country: submitted_sub_country).territory.name
  elsif Geo.find_by(country: @submission.country)
    recipient = Geo.find_by(country: @submission.country).recipient
    territory = Geo.find_by(country: @submission.country).territory.name
  else
    recipient = Geo.find_by(country: '').recipient
    territory = 'none found'
  end

  @submission.recipient_id = recipient.id
  @submission.status += 'territory: '+territory+', recipient: '+@submission.recipient.name+' - '+@submission.recipient.email
  @submission.status += recipient.work_hours? ? ', during work hours' : ', outside of work hours'
  @submission.save

  #first_letter = @submission.emailAddress[0]
  #if ('a'..'z').to_a.include?(first_letter)
  #	@submission.bdr = "Casey"
  #	notification_email = "casey@twilio.com"
  #else
  #	@submission.bdr = "error"
  #	notification_email = "emerald@twilio.com"
  #end

  email_subject = 'New FSR Submission - '+@submission.company
  
  begin 
	  @sendgrid_client = SendGrid::Client.new(api_user: settings.sendgrid_api_user, api_key: settings.sendgrid_api_key)
	  @sendgrid_client.send(SendGrid::Mail.new(to: @submission.recipient.email, from: settings.email_from, subject: email_subject, text: @submission.email_message))
	  @submission.status += ', sent email'
  rescue
  	@submission.status += ', error on sending email'
  end
  @submission.save

  if recipient.work_hours?
    unless @submission.phone
      @submission.status += ', no call made because phone number invalid'
    else
      @twilio_client = Twilio::REST::Client.new settings.twilio_account_sid, settings.twilio_auth_token
      begin
        @call = @twilio_client.calls.create(
          from: settings.calls_sms_from,
          to: @submission.recipient.phone,
          url: @submission.twilio_gather_url,
          method: 'GET'
        ) 
        @submission.status += ', call_made' 
      rescue
        @submission.status += ', error on making call'
      end
    end
    @submission.save
  end
end

get '/call_to_recipient' do
  if params[:submission_id] 
    @submission = Submission.find(params[:submission_id].to_i)

    if params[:Digits].nil?
      erb :'twiml/call', :layout => false
    elsif params[:Digits] == '1'
      @submission.status += ', connected call with client'
      @submission.save
      erb :'twiml/connect_call', :layout => false
    else
      begin
        @twilio_client = Twilio::REST::Client.new settings.twilio_account_sid, settings.twilio_auth_token
        @twilio_client.messages.create(
          from: settings.calls_sms_from,
          to: @submission.recipient.phone,
          body: @submission.sms_message
        )
        @submission.status += ', sent sms message'
        @submission.save
      rescue
        @submission.status += ', error on sending sms'
        @submission.save
      end
      erb :'twiml/end_call', :layout => false
    end
  end
end
