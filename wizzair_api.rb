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

class WizzAPI
  require "net/http"
  require "http-cookie"
  require "json"
  require "pp"
  
  API_ENDPOINT = "https://be.wizzair.com/3.9.0/Api/search/"
  
  def initialize
    @jar = HTTP::CookieJar.new
    @debug = false
  end
  
  # Internal method for accessing wizz URL's with 
  def do_http(url, method=:get, data={}, custom_headers={} )
     uri = URI(url)
     
     # Setup default headers
     headers = {
			"Accept" => "application/json",
			"Cache-Control" => "max-age=0",
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
       headers['Content-Type']='application/json'
       data_string=JSON.generate(data)
       response = http.post2(uri.request_uri, data_string, headers)
     else
       return nil
     end
         
     case response
       when Net::HTTPSuccess      
         @jar.parse(response.header["Set-Cookie"], uri) unless response.header["Set-Cookie"].nil?
         return response
       when Net::HTTPRedirection 
         new_location =  URI.join(url,response['location']).to_s
         return do_http(new_location, :get, {}, custom_headers)
       else
         return response.error!
       end
  end

  # Search for a flight with return date
  def search(origin, destination, departure_date, return_date=nil)
    result = []
    
    departure_date=departure_date.strftime("%Y-%m-%d") if departure_date.is_a? Date  
    return_date=return_date.strftime("%Y-%m-%d") if return_date.is_a? Date rescue nil
        
    # Assemble the data to be posted
    data = {
      adultCount: 1,
      childCount: 0,
      infantCount: 0,
      wdc: true,
      flightList: [
        {
          departureStation: origin,
          arrivalStation: destination,
          departureDate: departure_date
        }
      ]
    }
    # Add return date if given
    data[:flightList] << {
              departureStation: destination,
              arrivalStation: origin,
              departureDate: return_date
    } unless return_date.nil? 
    
    
    # Post the data    
    headers = { "Referer" => "https://wizzair.com/" }
    response=do_http(API_ENDPOINT+"search",:post,data,headers)
    raise 'error getting search results' unless response.is_a? Net::HTTPSuccess
    
    # Parse response
    res = JSON.parse(response.body)
    [*res['outboundFlights'],*res['returnFlights']].each do |flight|  
        entry = {
          from_airport: flight['departureStation'] ,
          to_airport: flight['arrivalStation'] ,
          flight_code: flight['carrierCode']+flight['flightNumber'],
          departure: DateTime.parse(flight['departureDateTime'])
        }
        # Collect fares to get best fare
        fares = flight['fares'].collect { |f| f['discountedPrice']['amount'] }
        entry[:best_fare] = fares.min
        
        yield entry if block_given?
        result << entry
    end

    return result
  end

  
  def search_multiple_days(origin, destination, start_date, return_date=nil, days = 1)
    result = []
    
    if start_date.is_a? String
      s_date = Date.parse(start_date)       
    elsif start_date.is_a? Date
      s_date = start_date
    else
      raise "Invalid start date"
    end

    if return_date.nil?
      r_date = nil       
    elsif return_date.is_a? String
      r_date = Date.parse(return_date)       
    elsif return_date.is_a? Date
      r_date = return_date
    else
      raise "Invalid return date"
    end
    
    days.times do    
      search(origin,destination,s_date, r_date) do |entry|
        yield entry if block_given?
        result << entry
      end
      s_date += 1
      r_date += 1 unless r_date.nil?
    end
    
    return result
  end
  
  
  private :do_http
  attr_accessor :debug

end