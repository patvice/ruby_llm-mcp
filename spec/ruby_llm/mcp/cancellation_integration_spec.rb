# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Cancellation Integration", :vcr do # rubocop:disable RSpec/DescribeClass
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    ClientRunner.build_client_runners(CLIENT_OPTIONS)
  end

  before do
    MCPTestConfiguration.reset_config!
    MCPTestConfiguration.configure_ruby_llm!
  end

  around do |example|
    cassette_name = example.full_description
                           .delete_prefix("RubyLLM::MCP::")
                           .downcase
                           .gsub(", ", "")
                           .gsub(" ", "_")
                           .gsub("/", "_")

    VCR.use_cassette(cassette_name, allow_playback_repeats: true) do
      example.run
    end
  end

  each_client_supporting(:sampling) do |config|
    describe "End-to-end cancellation with #{config[:name]}" do
      let(:client) { RubyLLM::MCP::Client.new(**config[:options], start: false) }

      after do
        client.stop if client.alive?
      end

      # rubocop:disable RSpec/ExampleLength
      it "handles server-initiated cancellation of sampling requests" do
        # Enable sampling so the client can handle sampling requests
        RubyLLM::MCP.configure do |config|
          config.sampling.enabled = true
          config.sampling.preferred_model = "gpt-4o"
        end

        # Track if sampling was actually cancelled (shouldn't complete)
        sampling_completed = false
        sampling_request_id = nil

        # Set up a sampling callback that would take time if not cancelled
        client.on_sampling do |sample|
          sampling_request_id = sample.to_h[:id]
          # This should be interrupted by cancellation
          sleep 1.0
          sampling_completed = true
          true
        end

        client.start

        # Wait for the tool to become available
        tool = wait_for_tool(client, "sample_with_cancellation")

        # Call the tool in a thread so we can cancel it
        tool_thread = Thread.new do
          tool.execute
        end

        # Wait for the sampling request to start
        sleep 0.1 until sampling_request_id

        # Send cancellation notification for the sampling request
        notification = RubyLLM::MCP::Notification.new(
          {
            "method" => "notifications/cancelled",
            "params" => {
              "requestId" => sampling_request_id,
              "reason" => "Test cancellation"
            }
          }
        )

        notification_handler = RubyLLM::MCP::NotificationHandler.new(client)
        notification_handler.execute(notification)

        # Wait a bit for cancellation to take effect
        sleep 0.2

        # Verify our sampling callback never completed
        expect(sampling_completed).to be false

        # Clean up
        tool_thread.kill if tool_thread.alive?
        tool_thread.join
      end
      # rubocop:enable RSpec/ExampleLength

      # rubocop:disable RSpec/ExampleLength
      it "properly cleans up cancelled requests" do
        # Enable sampling
        RubyLLM::MCP.configure do |config|
          config.sampling.enabled = true
          config.sampling.preferred_model = "gpt-4o"
        end

        request_ids = []

        client.on_sampling do |sample|
          request_ids << sample.to_h[:id]
          sleep 0.5
          true
        end

        client.start

        # Wait for the tool to become available
        tool = wait_for_tool(client, "sample_with_cancellation")

        # Start multiple sampling requests
        threads = 3.times.map do
          Thread.new do
            tool.execute
          end
        end

        # Wait for ALL requests to start
        sleep 0.1 until request_ids.length >= 3

        # Cancel each request as soon as we detect it
        cancelled_ids = []
        request_ids.each do |request_id|
          notification = RubyLLM::MCP::Notification.new(
            {
              "method" => "notifications/cancelled",
              "params" => {
                "requestId" => request_id,
                "reason" => "Test cancellation"
              }
            }
          )

          notification_handler = RubyLLM::MCP::NotificationHandler.new(client)
          notification_handler.execute(notification)
          cancelled_ids << request_id
        end

        # Wait for cancellations to propagate
        sleep 0.3

        # Clean up threads
        threads.each do |t|
          t.kill if t.alive?
          t.join
        end

        # Verify all cancelled requests are cleaned up
        in_flight = client.adapter.native_client.instance_variable_get(:@in_flight_requests)
        cancelled_ids.each do |id|
          expect(in_flight.key?(id.to_s)).to be false
        end
      end
      # rubocop:enable RSpec/ExampleLength
    end
  end
end
