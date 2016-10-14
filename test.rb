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

require 'pp'
require "./wizzair_api.rb"

scraper = WizzAPI.new
depart = (Date.today+7).strftime('%Y-%m-%d')
ret = (Date.today+14).strftime('%Y-%m-%d')

puts "Searching #{depart} - #{ret}"
pp scraper.search 'LTN','BUD',depart,ret

pp scraper.search 'LTN','BUD',Date.today+7

puts "Searching 5 days from #{depart}"
pp scraper.search_multiple_days 'LTN','BUD',depart,ret,5
