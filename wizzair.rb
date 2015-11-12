# Copyright Jozsef Orosz jozsef@orosz.name
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

class WizzScraper
  require "net/http"
  require "http-cookie"
  require "nokogiri"
  
  def initialize
    @jar = HTTP::CookieJar.new
    @debug = false
  end
  
  # Internal method for accessing wizz URL's with 
  def do_http(url, method=:get, data={}, custom_headers={} )
     uri = URI(url)
     
     # Setup default headers
     headers = {
			"Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
  		"Accept-Encoding" => "identity",
			"Cache-Control" => "max-age=0",
			"Accept-Language" => "en-GB;q=1.0,en;q=0.6",
      "Cookie" => HTTP::Cookie.cookie_value(@jar.cookies(uri))
		 }   

     # Copy custom headers
     custom_headers.each { |key,val| headers[key] = val }

     # Connect to host
     http = Net::HTTP.new(uri.host, uri.port)
     http.use_ssl = true
     http.set_debug_output($stdout) if @debug
     
     # Fire off request
     case method 
     when :get
       response = http.get2(uri.request_uri , headers)
     when :post 
       headers['Content-Type']='application/x-www-form-urlencoded'
       data_string=URI.encode_www_form(data)
       response = http.post2(uri.request_uri, data_string, headers)
     else
       return nil
     end
         
     case response
       when Net::HTTPSuccess      
         @jar.parse(response.header["Set-Cookie"], uri)
         return response
       when Net::HTTPRedirection 
         new_location =  URI.join(url,response['location']).to_s
         return do_http(new_location, :get, {}, custom_headers)
       else
         return response.error!
       end
   end

  # Parses the Wizz page for the view state and secret name/value pair
  def grep_view_state(page_source)
    body = Nokogiri::HTML(page_source)
    pageToken=body.at_css('form#SkySales input[name="pageToken"]').next
    viewState=body.at('input#viewState')['value']
    return viewState, pageToken['name'],  pageToken['value']
  end 
  
  
  # Parses Wizz page for the flight table and yields each record to a block 
  def grep_flights(page_source)
    table_body = Nokogiri::HTML(page_source)
    table_body.css("label.flight.flight-data.flight-fare.flight-fare-type--basic.flight-fare--wdc").each do |label|
      # Label contains the price and the checkbox has the flight parameters
      date_str = label.at_css('input')['value']
      if date_str then
        date_arr = date_str.split '~'
        entry = {
          'sample_time' => DateTime.now.strftime,
          'amount' => label.xpath('text()').text.match(/\d+(\.\d+)?/mi)[0].to_s,
          'departure' => DateTime.strptime(date_arr[12], '%m/%d/%Y %H:%M').strftime,
          'from_airport' => date_arr[11],
          'to_airport' => date_arr[13]
        }        
        yield entry
      end
    end
  end

  # Search using the main page
  def search(origin, destination, departure_date, return_date)
    result = []
    
    response = do_http("https://wizzair.com/en-GB/FlightSearch")
    raise 'error getting homepage' unless response.is_a? Net::HTTPSuccess
    
    # We have a GET response, now we will parse the body of the search page for hidden fields
    view_state, secret_name, secret_value = grep_view_state(response.body)
    
    # Assemble the data to be posted
    post = {
      "__EVENTTARGET" => "HeaderControlGroupRibbonSelectView_AvailabilitySearchInputRibbonSelectView_ButtonSubmit",
			"__VIEWSTATE" => view_state,
      secret_name => secret_value,
      "ControlGroupRibbonAnonNewHomeView$AvailabilitySearchInputRibbonAnonNewHomeView$OriginStation" => origin,
  		"ControlGroupRibbonAnonNewHomeView$AvailabilitySearchInputRibbonAnonNewHomeView$DestinationStation" => destination,
      "ControlGroupRibbonAnonNewHomeView$AvailabilitySearchInputRibbonAnonNewHomeView$DepartureDate" => departure_date,
      "ControlGroupRibbonAnonNewHomeView$AvailabilitySearchInputRibbonAnonNewHomeView$ReturnDate" => return_date,
      "ControlGroupRibbonAnonNewHomeView$AvailabilitySearchInputRibbonAnonNewHomeView$PaxCountADT" => "1",
      "ControlGroupRibbonAnonNewHomeView$AvailabilitySearchInputRibbonAnonNewHomeView$PaxCountCHD" => "0",
      "ControlGroupRibbonAnonNewHomeView$AvailabilitySearchInputRibbonAnonNewHomeView$PaxCountINFANT" => "0",
      "ControlGroupRibbonAnonNewHomeView$AvailabilitySearchInputRibbonAnonNewHomeView$ButtonSubmit" => "Search"
    }
    
    headers = {
      "Referer" => "https://wizzair.com/en-GB/FlightSearch"
    }
    
    # Post the data
    response=do_http("https://wizzair.com/en-GB/FlightSearch",:post,post,headers)
    raise 'error getting search results' unless response.is_a? Net::HTTPSuccess
    
    # Parse response
    grep_flights(response.body) do |entry|        
        yield entry if block_given?
        result << entry
    end
  
    return result
  end
  
  def search_multiple_days(origin, destination, start_date, days = 1)
    result = []

    # Kickoff with a simple search for one day
    search origin, destination, start_date, start_date do |entry|
      yield entry if block_given?
      result << entry
    end
    
    
    # Now fire off navigation requests using further POST's to select-resource
    headers = {
      "Referer" => "https://wizzair.com/en-GB/Select",
      "X-Requested-With" => "XMLHttpRequest"
    }
    
    post = {
      "isAjaxRequest"=>"true",
      "marketIndex"=>"0",
      "direction"=>"1"
    }
    
    # Step number of days - 1 (we've done the first one!)
    (days - 1).times do
      response = do_http("https://wizzair.com/en-GB/Select-resource",:post,post,headers)
      return result unless response.is_a? Net::HTTPSuccess # Quit if something goes wrong
      
      grep_flights(response.body) do |entry|        
        yield entry if block_given?
        result << entry
      end
    end
        
    return result
  end
  
  
  private :do_http, :grep_flights, :grep_view_state
  attr_accessor :debug

end


