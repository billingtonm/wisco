require 'net/http'
require 'uri'
require 'cgi'
require 'json'

module Wisco
  class WorkatoApi
    def initialize(hostname:, api_token:, debug: false)
      @hostname  = hostname
      @api_token = api_token
      @debug     = debug
    end

    # Returns [status_int, parsed_hash_or_nil, raw_body_string]
    def search_connector(title:)
      request(:get, '/api/custom_connectors/search', params: { title: title })
    end

    def get_connector_code(id:)
      request(:get, "/api/custom_connectors/#{id}/code")
    end

    private

    def request(_method, path, params: nil, body: nil)
      # Use URI only for host/port; build path+query as a raw string so
      # Net::HTTP sends it without any re-encoding by the URI class.
      base_uri   = URI("https://#{@hostname}")
      query      = params.map { |k, v| "#{k}=#{v.to_s.gsub(' ', '%20')}" }.join('&') if params
      request_path = query ? "#{path}?#{query}" : path

      req = Net::HTTP::Get.new(request_path)
      req['Authorization'] = "Bearer #{@api_token}"
      req['Accept']        = '*/*'
      req['User-Agent']    = 'wisco'
      if body
        req['Content-Type'] = 'application/json'
        req.body = body.to_json
      end

      if @debug
        warn "[api] → GET https://#{@hostname}#{request_path}"
        warn "[api]   Authorization: Bearer #{masked_token}"
        warn "[api]   Accept: */*"
        warn "[api]   User-Agent: wisco"
        warn "[api]   Content-Type: application/json" if body
        warn "[api]   Body: #{req.body}" if body
      end

      http         = Net::HTTP.new(base_uri.host, base_uri.port)
      http.use_ssl = true
      resp         = http.request(req)
      raw_body     = resp.body.to_s

      if @debug
        warn "[api] ← #{resp.code} #{resp.message}"
        warn "[api]   Body: #{raw_body}"
      end

      begin
        parsed = JSON.parse(raw_body)
      rescue JSON::ParserError
        parsed = nil
      end
      [resp.code.to_i, parsed, raw_body]
    end

    def masked_token
      return '(empty)' if @api_token.nil? || @api_token.empty?

      visible = [@api_token.length, 6].min
      "#{@api_token[0, visible]}..."
    end
  end
end
