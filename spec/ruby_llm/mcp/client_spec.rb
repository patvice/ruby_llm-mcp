# frozen_string_literal: true

require "stringio"

RSpec.describe RubyLLM::MCP::Client do
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    ClientRunner.build_client_runners(CLIENT_OPTIONS)
    ClientRunner.start_all
  end

  after(:all) do # rubocop:disable RSpec/BeforeAfterAll
    ClientRunner.stop_all
  end

  describe "start" do
    it "starts the client" do
      options = { start: false }.merge(FILESYSTEM_CLIENT)
      client = RubyLLM::MCP::Client.new(**options)
      client.start

      first = client.tools.first
      expect(first).to be_a(RubyLLM::MCP::Tool)
      client.stop
    end

    it "calls start twice does not raise an error" do
      options = { start: false }.merge(FILESYSTEM_CLIENT)
      client = RubyLLM::MCP::Client.new(**options)
      client.start

      expect { client.start }.not_to raise_error

      client.stop
    end
  end

  CLIENT_OPTIONS.each do |options|
    context "with #{options[:name]}" do
      let(:client) do
        ClientRunner.client_runners[options[:name]].client
      end

      describe "initialization" do
        it "initializes with correct transport type and capabilities" do
          expect(client.transport_type).to eq(options[:options][:transport_type])
          expect(client.capabilities).to be_a(RubyLLM::MCP::Capabilities)
        end
      end

      describe "stop" do
        it "closes the transport connection and start it again" do
          client.stop
          expect(client.alive?).to be(false)

          client.start
          expect(client.alive?).to be(true)
        end
      end

      describe "restart!" do
        it "stops and starts the client" do
          expect(client.alive?).to be(true)
          client.restart!
          expect(client.alive?).to be(true)
        end
      end

      describe "ping server" do
        it "can ping the client that hasn't been started yet" do
          new_options = { start: false }.merge(options[:options])
          new_client = RubyLLM::MCP::Client.new(**new_options)

          ping = new_client.ping
          expect(ping).to be(true)
        end

        it "can ping the client that is already started" do
          ping = client.ping
          expect(ping).to be(true)
        end

        it "ping a fake client that is not alive" do
          buffer = StringIO.new
          old_logger = RubyLLM::MCP.config.logger
          RubyLLM::MCP.config.logger = Logger.new(buffer)

          new_client = if options[:options][:transport_type] == :streamable
                         RubyLLM::MCP::Client.new(
                           start: false,
                           name: "fake_client",
                           transport_type: :streamable,
                           config: {
                             url: "http://localhost:12345"
                           },
                           request_timeout: 1000
                         )
                       else
                         RubyLLM::MCP::Client.new(
                           start: false,
                           name: "fake_client",
                           transport_type: :stdio,
                           config: {
                             command: "echo",
                             args: ["Hello, world!"]
                           },
                           request_timeout: 1000
                         )
                       end

          ping = new_client.ping
          RubyLLM::MCP.config.logger = old_logger
          expect(ping).to be(false)
        end
      end

      describe "ping client" do
        it "Server can ping the client to see if it's alive" do
          tool = client.tool("ping_client")
          result = tool.execute
          expect(result.to_s).to eq("Ping successful")
        end
      end

      describe "tools" do
        it "returns array of tools" do
          tools = client.tools
          expect(tools).to be_a(Array)
          expect(tools.first).to be_a(RubyLLM::MCP::Tool)
        end

        it "refreshes tools when requested" do
          tools1 = client.tools
          tools2 = client.tools(refresh: true)
          expect(tools1.map(&:name)).to eq(tools2.map(&:name))
        end

        context "with capabilities" do
          it "returns empty array when tools_list capability is disabled" do
            allow(client.capabilities).to receive(:tools_list?).and_return(false)
            expect(client.tools).to eq([])
          end

          it "returns tools when tools_list capability is enabled" do
            allow(client.capabilities).to receive(:tools_list?).and_return(true)
            tools = client.tools
            expect(tools).to be_a(Array)
            expect(tools).not_to be_empty
          end
        end
      end

      describe "tool" do
        it "returns specific tool by name" do
          tool = client.tool("add")
          expect(tool).to be_a(RubyLLM::MCP::Tool)
          expect(tool.name).to eq("add")
        end
      end

      describe "resources" do
        it "returns array of resources" do
          resources = client.resources
          expect(resources).to be_a(Array)
          expect(resources.first).to be_a(RubyLLM::MCP::Resource)
        end

        it "refreshes resources when requested" do
          resources1 = client.resources
          resources2 = client.resources(refresh: true)
          expect(resources1.map(&:name)).to eq(resources2.map(&:name))
        end

        context "with capabilities" do
          it "returns empty array when resources_list capability is disabled" do
            allow(client.capabilities).to receive(:resources_list?).and_return(false)
            expect(client.resources).to eq([])
          end

          it "returns resources when resources_list capability is enabled" do
            allow(client.capabilities).to receive(:resources_list?).and_return(true)
            resources = client.resources
            expect(resources).to be_a(Array)
            expect(resources).not_to be_empty
          end
        end
      end

      describe "resource" do
        it "returns specific resource by name" do
          resource = client.resource("test.txt")
          expect(resource).to be_a(RubyLLM::MCP::Resource)
          expect(resource.name).to eq("test.txt")
        end
      end

      describe "resource_templates" do
        context "with capabilities" do
          it "returns empty array when resources_list capability is disabled" do
            allow(client.capabilities).to receive(:resources_list?).and_return(false)
            expect(client.resource_templates).to eq([])
          end

          it "returns resource templates when resources_list capability is enabled" do
            allow(client.capabilities).to receive(:resources_list?).and_return(true)
            resource_templates = client.resource_templates
            expect(resource_templates).to be_a(Array)
          end
        end
      end

      describe "prompts" do
        it "returns array of prompts" do
          prompts = client.prompts
          expect(prompts).to be_a(Array)
        end

        it "refreshes prompts when requested" do
          prompts1 = client.prompts
          prompts2 = client.prompts(refresh: true)
          expect(prompts1.size).to eq(prompts2.size)
        end

        context "with capabilities" do
          it "returns empty array when prompt_list capability is disabled" do
            allow(client.capabilities).to receive(:prompt_list?).and_return(false)
            expect(client.prompts).to eq([])
          end

          it "returns prompts when prompt_list capability is enabled" do
            allow(client.capabilities).to receive(:prompt_list?).and_return(true)
            prompts = client.prompts
            expect(prompts).to be_a(Array)
          end
        end
      end

      describe "prompt" do
        it "returns specific prompt by name if available" do
          prompt = client.prompt("nonexistent")
          expect(prompt).to be_nil
        end
      end

      describe "reset_resource_templates!" do
        it "clears the resource templates cache" do
          # First load resource templates to populate cache
          client.resource_templates
          expect(client.instance_variable_get(:@resource_templates)).not_to be_empty

          # Reset the cache
          client.reset_resource_templates!
          expect(client.instance_variable_get(:@resource_templates)).to eq({})
        end

        it "forces refresh on next resource_templates call" do
          # Load resource templates to populate cache
          client.resource_templates
          cache_before_reset = client.instance_variable_get(:@resource_templates)
          expect(cache_before_reset).not_to be_empty

          # Mock the coordinator to verify fresh call is made
          allow(client.instance_variable_get(:@coordinator)).to receive(:resource_template_list).and_call_original

          # Reset and reload
          client.reset_resource_templates!
          expect(client.instance_variable_get(:@resource_templates)).to eq({})

          # Load again - should make fresh call to coordinator
          client.resource_templates
          expect(client.instance_variable_get(:@coordinator)).to have_received(:resource_template_list)
        end
      end

      describe "logging_enabled?" do
        it "returns false when log_level is nil" do
          expect(client.instance_variable_get(:@log_level)).to be_nil
          expect(client.logging_enabled?).to be(false)
        end

        it "returns true when log_level is set" do
          client.instance_variable_set(:@log_level, RubyLLM::MCP::Logging::DEBUG)
          expect(client.logging_enabled?).to be(true)
        end
      end

      describe "on_logging" do
        it "sets up a default lambda when no block is given" do
          allow(client.instance_variable_get(:@coordinator)).to receive(:set_logging)
          allow(client.instance_variable_get(:@coordinator)).to receive(:default_process_logging_message)

          client.on_logging(level: RubyLLM::MCP::Logging::DEBUG, logger: "test_logger")

          # Check that the logging handler is set and is a Proc
          logging_handler = client.instance_variable_get(:@on)[:logging]
          expect(logging_handler).to be_a(Proc)

          # Test that the lambda calls the coordinator's default_process_logging_message
          mock_notification = instance_double(Object)
          logging_handler.call(mock_notification)

          expect(client.instance_variable_get(:@coordinator)).to have_received(:default_process_logging_message)
            .with(mock_notification, logger: "test_logger")
        end

        it "uses provided block when given" do
          custom_handler_called = false

          client.on_logging(level: RubyLLM::MCP::Logging::DEBUG) do |_notification|
            custom_handler_called = true
          end

          # Check that the logging handler is the provided block
          logging_handler = client.instance_variable_get(:@on)[:logging]
          expect(logging_handler).to be_a(Proc)

          # Test that the custom handler is called
          mock_notification = instance_double(Object)
          logging_handler.call(mock_notification)
          expect(custom_handler_called).to be(true)
        end

        it "returns self for method chaining" do
          result = client.on_logging(level: RubyLLM::MCP::Logging::DEBUG)
          expect(result).to eq(client)
        end

        it "sets the logging level on the MCP" do
          is_called = false
          client.on_logging(level: RubyLLM::MCP::Logging::DEBUG) do |notification|
            expect(notification.params["level"]).to eq(RubyLLM::MCP::Logging::DEBUG)
            expect(notification.params["logger"]).to eq("mcp")
            expect(notification.params["data"]["message"]).to eq("Hello, world!")
            is_called = true
          end

          client.tool("log_message").execute(message: "Hello, world!", level: "debug")
          sleep 1

          expect(is_called).to be(true)
        end

        it "logger is at a different level and not will output" do
          is_called = false
          client.on_logging(level: RubyLLM::MCP::Logging::WARNING) do
            is_called = true
          end

          client.tool("log_message").execute(message: "Hello, world!", level: "debug")

          expect(is_called).to be(false)
        end

        it "sets the logging level to default" do
          is_called = false
          client.on_logging do |notification|
            is_called = true
            expect(notification.params["level"]).to eq(RubyLLM::MCP::Logging::WARNING)
            expect(notification.params["logger"]).to eq("mcp")
            expect(notification.params["data"]["message"]).to eq("This is a warning")
          end

          client.tool("log_message").execute(message: "This is a warning", level: "warning")
          expect(is_called).to be(true)
        end
      end
    end
  end
end
