require 'sinatra'
require 'sinatra/activerecord'
require 'twilio-ruby'
require 'stripe'
require 'sendgrid-ruby'

configure :development do
 set :database, 'sqlite3:fsr.db'
 set :show_exceptions, true
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
end

class Submission < ActiveRecord::Base
end

#static pages and sign in
post '/' do 
	@submission = Submission.new
	@submission.all_params = params.to_s
	@submission.company = params[:company] || ''
  @submission.country = params[:country] || ''
  @submission.description1 = params[:description1] || ''
  @submission.emailAddress = params[:emailAddress].downcase || ''
  @submission.firstName = params[:firstName] || ''
  @submission.jobRole = params[:jobRole] || ''
  @submission.lastName = params[:lastName] || ''
  @submission.usStates = params[:usStates] || ''

  first_letter = @submission.emailAddress[0]
  if ('a'..'z').to_a.include?(first_letter)
  	@submission.bdr = "Casey"
  	notification_email = "casey@twilio.com"
  else
  	@submission.bdr = "error"
  	notification_email = "emerald@twilio.com"
  end

  email_text = 'You have a new FSR submission, please reach out within the next hour. Here is the info:
  	Company: '+@submission.company+'
  	Name: '+@submission.firstName+' '+@submission.lastName+'
  	Email: '+@submission.emailAddress+'
  	Description: '+@submission.description1+'
  	All info: '+@submission.all_params
  
  begin 
	  client = SendGrid::Client.new(api_user: 'caseyclegg', api_key: 'tigerdude48')
	  client.send(SendGrid::Mail.new(to: notification_email, from: 'casey@twilio.com', subject: 'New FSR Submission', text: email_text))
	  @submission.bdr += ', sent'
  rescue
  	@submission.bdr += ', error on sending'
  end

  @submission.save
end

get '/' do
	@submissions = Submission.all
	erb :submissions
end
