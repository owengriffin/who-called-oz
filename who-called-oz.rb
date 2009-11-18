#!/bin/ruby

require 'rubygems'
require 'mechanize'
require 'net/http'
require 'net/https'
require 'rexml/document'
require 'yaml'

class GoogleContacts
  attr_accessor :auth
  
  # Authenticate with the Google API
  def authenticate(email, password)
    url=URI.parse('https://www.google.com/accounts/ClientLogin')
    # Create a new POST HTTP request and set the required authentication
    # variables
    req = Net::HTTP::Post.new(url.path)
    req.set_form_data({'accountType' => 'HOSTED_OR_GOOGLE',
                        'Email' => email,
                        'Passwd' => password,
                        'service' => 'cp', # cp = Google Contacts
                        'source' => "owengriffin.com-whocalledoz?-1"
                      })
    # Create a new SSL HTTP connection to the URL
    http = Net::HTTP.new(url.host, url.port)
    #http.set_debug_output $stdout
    http.use_ssl = true
    resp = nil
    # Start the connection and dump the response into resp
    http.start {|http| 
      resp = http.request(req) 
    }
    data = resp.body
    if resp.code == "200" 
      # Read the data from the response body, search for the Auth token
      data.split.each do |str|
        if not (str =~ /Auth=/).nil?
          # Set the auth token to be used by this class
          @auth = str.gsub(/Auth=/, '')   
        end
      end
    else  
      puts "Error code #{resp.code}"
      puts data
    end
  end

  # Fetch a list of Google contacts
  def fetch
    if @auth != nil
      http = Net::HTTP.new('www.google.com', 80)
      path = "/m8/feeds/contacts/default/base?max-results=10000"
      headers = {'Authorization' => "GoogleLogin auth=#{@auth}"}
      resp, data = http.get(path, headers)
      
      xml = REXML::Document.new(data)
      contacts = []
      xml.elements.each('//entry') do |entry|
        person = {}
        person['name'] = entry.elements['title'].text
        
        gd_email = entry.elements['gd:email']
        person['email'] = gd_email.attributes['address'] if gd_email

        entry.each_element('gd:phoneNumber') { |gd_phonenumber|
        if gd_phonenumber
          if person['phoneNumber'] == nil
            person['phoneNumber'] = []
          end
          person['phoneNumber'] << gd_phonenumber.text
        end
        }
        contacts << person
      end
      return contacts
    end
    return []
  end
end


class VirginMedia

  def initialize
    @agent = WWW::Mechanize.new
  end

  # Returns the form element, based on the given id
  def get_form_by_id(page, id)
    form = page.search(".//form[@id='#{id}']")[0]
    form = WWW::Mechanize::Form.new(form, page.mech, page)
    form.action ||= page.uri.to_s
    return form
  end

  def authenticate(email, pin)
    # Goto the Virgin billing page and authenticate
    page = @agent.get('https://ebill2.virginmedia.com/ebill2/Logon.jsf')
    form = get_form_by_id(page, 'logonForm')
    form['EmailAddress']=email
    form['PIN']=pin
    form['logonForm:_id37']='Sign In'
    page = @agent.submit form
    # We are now at the bill summary page
    # amount_due = page.search(".//div[@class='billSummaryList']/dl/dd[5]")[0].content
    return page
  end

  def get_calls(page)
    form = get_form_by_id(page, 'billSummaryForm')
    form['billSummaryForm:_id39:0:_id66']='Show Me This Bill'
    page = @agent.submit form
    link = page.links_with(:href => 'StatementDetails.jsf')[0]
    page = @agent.click link
    calls = []
    page.search(".//tbody[@id='telephoneUsageCallDetailsCCList:0:telephoneUsageCallDetailsCCCASort:telephoneUsageCallDetailsCCCADList:tbody_element']/tr").each { |row|
      entry = {}
      entry["date"] = row.at_xpath('td[1]').text.strip
      entry["time"] = row.at_xpath('td[2]').text.strip
      entry["destination"] = row.at_xpath('td[3]').text.match(/^\s*([^\s]*)\s*$/)[1]
      entry["number"] = row.at_xpath('td[4]').text.match(/^\s*([^\s]*)\s*$/)[1]
      entry["duration"] = row.at_xpath('td[5]').text.match(/^\s*([^\s]*)\s*$/)[1]
      calls << entry
    }
    return calls
  end
end

# We now have a list of numbers


authentication = YAML::load_file("#{ENV['HOME']}/.whocalledoz.yaml")

# Download all the Google Contacts
google = GoogleContacts.new
google.authenticate authentication[:email], authentication[:password]
contacts = google.fetch

# Fetch the latest Virgin bill
virgin = VirginMedia.new
page = virgin.authenticate authentication[:email], authentication[:pin]
calls = virgin.get_calls page


blames = []
calls.each { |call|
  number = call["number"]
  # Strip any leading 0
  if number[0]="0"
    number=number[1..number.length]
  end
  # Iterate through the contacts and find the culprits
  contacts.each { |contact|
    if contact['phoneNumber']
    contact['phoneNumber'].each { |phoneNumber|
      if Regexp.new('[\+0-9]*?' + number).match(phoneNumber)
        blame = {}
        blame['name'] = contact['name']
        blame['number'] = contact['phoneNumber']
        blame['duration'] = call['duration']
        blame['when']=call['date'] + ' at ' + call['time']
        blames << blame
      end
    }
    end
  }
}

puts "Summary:"
blames.each {|blame|
  puts "You called #{blame['name']} for #{blame['duration']} minutes on #{blame['when']}!"
}


