require 'httpclient/include_client'
require 'net/http'

module WebhookMultiplexer
  extend HTTPClient::IncludeClient
  include_http_client do |http|
    if ENV['DEBUG']
      (http.debug_dev = $stdout).sync = true
    end
    http.connect_timeout = ENV.fetch('CONNECT_TIMEOUT', '5').to_i
    http.send_timeout = ENV.fetch('SEND_TIMEOUT', '5').to_i
    http.receive_timeout = ENV.fetch('RECEIVEt_TIMEOUT', '15').to_i
  end

  module_function

  module NormalizeHeaders
    module_function

    def normalize_headers(headers)
      array = headers.map { |name, value|
        [name.to_s.split(/_|-/).map { |segment| segment.capitalize }.join("-"),
         case value
           when Regexp then value
           when Array then (value.size == 1) ? value.first : value.map {|v| v.to_s}.sort
           else value.to_s
         end
        ]
      }
      Hash[*array.inject([]) {|r,x| r + x}]
    end
  end

  module RequestHeaders
    include NormalizeHeaders

    def headers
      http_keys = env.keys.grep(/^HTTP_/)
      values = env.values_at(*http_keys)
      http_keys.map!{|key| key.sub(/^HTTP_/, '') }

      normalize_headers Hash[http_keys.zip(values)]
    end
  end

  def call(env)
    request = ::Rack::Request.new(env)
    request.extend(RequestHeaders)
    results = multiplex(request, multiplexed_locations)

    success, failure = results.partition{|r| r.is_a?(HTTP::Message) && HTTP::Status.successful?(r.status) }
    errors = ", #{failure.size} errors (#{failure.map(&method(:failure_reason)).join(', ')})" unless failure.empty?

    [ 200, {}, ["payload delivered to #{success.size} locations", errors].compact ]
  end

  # @param request [Rack::Request]
  # @param locations [Array<String>]
  def multiplex(request, locations)
    body = request.body.read
    headers = request.headers
    headers.delete('Host')

    connections = locations.map do |location|

      request_method = location.request_method || request.request_method
      uri = URI("#{location}#{request.fullpath == '/' ? '' : request.fullpath}")
      has_body = request_has_body?(request_method)

      http_client.request_async(request_method,
                                uri,
                                request.query_string.split('&'),
                                (has_body.nil? || has_body) ? body : nil,
                                headers.merge('Host' => uri.host).merge(location.headers))
    end

    responses = connections.each(&:join).map do |connection|
      begin
        connection.pop
      rescue => error
        error
      end
    end

    responses
  end

  def request_has_body?(method)
    request_method = method.downcase
    request = Net::HTTP.const_get(request_method.capitalize) if Net::HTTP.instance_method(request_method)
    request::REQUEST_HAS_BODY
  rescue NameError
    nil
  end


  def failure_reason(message)
    case message
      when HTTP::Message
        message.status
      when ::HTTPClient::TimeoutError, ::HTTPClient::BadResponseError # convert HTTPClient::ConnectTimeoutError to connect_timeout
        message.message.split('::').last.gsub(/([a-z\d])([A-Z])/,'\1_\2').sub(/_error$/i, '').downcase
    end
  end

  class Location
    include NormalizeHeaders
    attr_reader :request_method, :url, :headers

    alias_method :to_s, :url

    def initialize(url, request_method: nil, headers: nil)
      @url = url
      @request_method = request_method
      @headers = normalize_headers(headers || {})
    end

    def self.parse(definition)
      method, url, *headers = definition.split(',')
      url, method = method, url if method && !url # swap if there is no method defined
      headers = Hash[headers.map{|line| k,v = line.split(/\s*:\s*/); [k.tr('-','_').upcase, v] }]
      new(url, request_method: method, headers: headers)
    end
  end

  def multiplexed_locations
    ENV.fetch('WEBHOOK_MULTIPLEXER_URLS'){ return [] }.split(';').map(&Location.method(:parse))
  end
end
