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
require "./wizzair.rb"
require "elasticsearch"
require "httpclient"

scraper = WizzScraper.new
client = Elasticsearch::Client.new log: true, adapter: :httpclient
client.cluster.health

scraper.search 'LTN','BUD','12/11/2015','17/11/2015' do |flight|
  pp flight
  client.index index: 'wizzair', type: 'flight', body: flight
end



