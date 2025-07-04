# frozen_string_literal: true
require_relative "base"
require "faraday" unless defined?(Faraday)
# require "inspec/utils/licensing_config" ## Disabled licensing
module Inspec
  class Telemetry
    class HTTP < Base
      TELEMETRY_JOBS_PATH = "v1/job"
      # Allow dev/CI to override the telemetry URL to a staging service
      TELEMETRY_URL = ENV["CHEF_TELEMETRY_URL"] || "https://services.chef.io/telemetry/"
      def run_ending(opts)
        payload = super
        response = connection.post(TELEMETRY_JOBS_PATH) do |req|
          req.body = payload.to_json
        end
        if response.success?
          Inspec::Log.debug "HTTP connection with Telemetry Client successful."
          Inspec::Log.debug "HTTP response from Telemetry Client -> #{response.to_hash}"
          true
        else
          Inspec::Log.debug "HTTP connection with Telemetry Client faced an error."
          Inspec::Log.debug "HTTP error -> #{response.to_hash[:body]["error"]}" if response.to_hash[:body] && response.to_hash[:body]["error"]
          false
        end
      rescue Faraday::ConnectionFailed
        Inspec::Log.debug "HTTP connection failure with telemetry url -> #{TELEMETRY_URL}"
      end

      def connection
        Faraday.new(url: TELEMETRY_URL) do |config|
          config.request :json
          config.response :json
        end
      end
    end
  end
end
