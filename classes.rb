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
    if self.emailAddress && /\A[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,6}+(\.[A-Z]{2,4})?\z/.match(URI.unescape(self.emailAddress))
      return URI.unescape(self.emailAddress || '').downcase
    else
      return nil
    end
  end

  def email_url
    if /\A[a-zA-Z0-9._%+-]+@([a-zA-Z0-9.-]+\.[a-zA-Z]{2,6}+(\.[A-Z]{2,4})?)\z/.match(self.email)
      return $1
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
    Description: '+self.description+'
    Relevant links:
    https://na2.salesforce.com/_ui/search/ui/UnifiedSearchResults?searchAll=true&initialViewMode=summary&str='+URI.escape(self.email)+'
    https://na2.salesforce.com/_ui/search/ui/UnifiedSearchResults?searchAll=true&initialViewMode=summary&str='+URI.escape(self.email_url)+'

    https://monkey.twilio.com/search?q='+URI.escape(self.email)+'
    https://monkey.twilio.com/search?q='+URI.escape(self.email_url)
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