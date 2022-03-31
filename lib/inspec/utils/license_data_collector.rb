require_relative "../dist"
require_relative "../version"
require "time" unless defined?(Time.zone_offset)

require_relative "license_data_collector/http"
require_relative "license_data_collector/offline"
require_relative "../globals"

module Inspec
  class LicenseDataCollector

    @@instance = nil

    def self.scan_starting(opts)
      instance.scan_starting(opts)
    end

    def self.scan_finishing(opts)
      instance.scan_finishing(opts)
    end

    def self.instance
      @@instance ||= determine_backend_class.new
    end

    def self.determine_backend_class
      # Don't perform license data collection if we are not the official Progress Chef InSpec distro
      return Inspec::LicenseDataCollector::Null if Inspec::Dist::EXEC_NAME != "inspec"

      # TODO: use Null backend if running under Automate

      # TODO: always use Null backend unless feature flagged on
      # Switch between Offline and Http intelligently
      if Inspec::LicenseDataCollector::Offline.airgap_mode?
        Inspec::LicenseDataCollector::Offline
      else
        Inspec::LicenseDataCollector::Http
      end
    end

    class Base
      attr_accessor :payload
      attr_accessor :headers

      def self.license_data_dir
        File.join(Inspec.config_dir, "license-data")
      end

      def scan_starting(opts)
        start_time = Time.now.getutc.iso8601

        # Populate header
        @headers = {
          Principal: "#{Inspec::Dist::EXEC_NAME}:#{Inspec::VERSION}",
          Customer: fetch_customer_id,
        }

        # Initialize payload
        @payload = {
          Periods: [
            Version: "#{Inspec::VERSION}",
            Date: start_time,
            Period: {
              Start: start_time,
            },
            Summary: {
              Nodes: { Total: 0, Active: 0 },
              Scans: { Targets: 1, Total: 1 },
            },
            Evidence: {
              Nodes: [],
              Scans: [
                {
                  Identifier: opts[:runner].backend.backend.platform.uuid,
                  Executions: 1, # TODO: Do they mean resource count here?
                  Version: "#{Inspec::VERSION}",
                  Activity: { Start: start_time },
                },
              ],
              Content: [], # Populated dynamically below
            },
          ],
        }

        # Create one content evidence for each licensed profile to be scanned
        opts[:runner].target_profiles.each do |profile|
          next unless profile.licensed?

          payload[:Periods][0][:Evidence][:Content] << {
            Identifier: profile.metadata.params[:entitlement_id],
            Executions: 1,
            # Version: "#{Inspec::VERSION}",
            Version: profile.metadata.params[:version],
            Type: "Profile",
            Activity: { Start: start_time },
          }
        end
      end

      def scan_finishing(_opts)
        end_time = Time.now.getutc.iso8601
        payload[:Periods][0][:Period][:End] = end_time
        payload[:Periods][0][:Evidence][:Scans][0][:Activity][:End] = end_time

        # TODO: Arguably, we should be looking through run_data and finding each profile's end time
        payload[:Periods][0][:Evidence][:Content].each { |c| c[:Activity][:End] = end_time }
      end

      def fetch_customer_id
        # TODO: obtain customer ID from some mechanism
        "TODOTODOTODOTODOTO"
      end

      # Merge two payloads
      def aggregate_ldc_payload(merged, newer)
        # Merge headers
        # Header is always the newer
        merged[:headers] = newer[:headers]

        # Merge payloads
        # Append new payload to merged Periods
        merged[:payload] ||= {}
        merged[:payload][:Periods] ||= []
        merged[:payload][:Periods] << newer[:payload][:Periods][0]
      end
    end

    class Null < Base
      def scan_starting(_opts); end
      def scan_finishing(_opts); end
    end
  end
end