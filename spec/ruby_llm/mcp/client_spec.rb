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

  describe "cancel_request" do
    it "cancels a request if the timeout is triggered" do
      options = CLIENT_OPTIONS.last[:options].merge({ start: false, request_timeout: 1000 })
      client = RubyLLM::MCP::Client.new(**options)
      client.start

      tool = client.tool("timeout_tool")

      allow(client.instance_variable_get(:@adapter)).to receive(:cancelled_notification).and_call_original
      expect { tool.execute(seconds: 2) }.to raise_error(RubyLLM::MCP::Errors::TimeoutError)
      expect(client.instance_variable_get(:@adapter)).to have_received(:cancelled_notification)

      client.stop
    end
  end

  # Ping tests - only for RubyLLM adapter (MCPSDK doesn't support true server ping)
  each_client(adapter: :ruby_llm) do |config|
    describe "ping server" do
      it "can ping the client that hasn't been started yet" do
        new_options = { start: false }.merge(config[:options])
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

        new_client = if config[:options][:transport_type] == :streamable
                       RubyLLM::MCP::Client.new(
                         start: false,
                         name: "fake_client",
                         transport_type: :streamable,
                         adapter: :ruby_llm,
                         config: {
                           url: "http://localhost:12345"
                         },
                         request_timeout: 100
                       )
                     else
                       RubyLLM::MCP::Client.new(
                         start: false,
                         name: "fake_client",
                         transport_type: :stdio,
                         adapter: :ruby_llm,
                         config: {
                           command: "echo",
                           args: ["Hello, world!"]
                         },
                         request_timeout: 100
                       )
                     end

        ping = new_client.ping
        RubyLLM::MCP.config.logger = old_logger
        expect(ping).to be(false)
      end
    end
  end

  each_client do |config|
    describe "initialization" do
      it "initializes with correct transport type and capabilities" do
        expect(client.transport_type).to eq(config[:options][:transport_type])
        expect(client.capabilities).to be_a(RubyLLM::MCP::ServerCapabilities)
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

    describe "tools" do
      it "returns array of tools" do
        tools = client.tools
        expect(tools).to be_a(Array)
        expect(tools.first).to be_a(RubyLLM::MCP::Tool)
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
    end

    describe "resource" do
      it "returns specific resource by name" do
        resource = client.resource("test.txt")
        expect(resource).to be_a(RubyLLM::MCP::Resource)
        expect(resource.name).to eq("test.txt")
      end
    end
  end

  # Resource template capability tests - only run on adapters that support resource_templates
  each_client_supporting(:resource_templates) do |config|
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
  end

  # Prompt tests - only run on adapters that support prompts
  each_client_supporting(:prompts) do |config|
    describe "prompts" do
      it "returns array of prompts" do
        prompts = client.prompts
        expect(prompts).to be_a(Array)
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
  end

  # Reset tests - only run on native adapter (uses internal native_client accessor)
  each_client(adapter: :ruby_llm) do |config|
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
        client.resource_templates
        cache_before_reset = client.instance_variable_get(:@resource_templates)
        expect(cache_before_reset).not_to be_empty

        allow(client.adapter.native_client).to receive(:resource_template_list).and_call_original
        client.reset_resource_templates!
        expect(client.instance_variable_get(:@resource_templates)).to eq({})

        client.resource_templates
        expect(client.adapter.native_client).to have_received(:resource_template_list)
      end
    end
  end

  # Logging tests - only run on adapters that support logging
  each_client_supporting(:logging) do |config|
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
      it "uses provided block when given" do
        custom_handler_called = false

        client.on_logging(level: RubyLLM::MCP::Logging::DEBUG) do |_notification|
          custom_handler_called = true
        end

        logging_handler = client.instance_variable_get(:@on)[:logging]
        expect(logging_handler).to be_a(Proc)

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

      it "uses default logging handler if no handler is provided" do
        client.on_logging

        logger_double = instance_double(Logger)
        allow(logger_double).to receive(:error)
        allow(logger_double).to receive(:debug)
        allow(logger_double).to receive(:info)

        RubyLLM::MCP.config.logger = logger_double
        client.tool("log_message").execute(message: "Hello, world!", level: "critical")

        expect(logger_double).to have_received(:error)
        RubyLLM::MCP.config.logger = nil
      end
    end
  end

  # Server-to-client requests (ping_client tool) - only supported by native adapter
  each_client_supporting(:list_changed_notifications) do |config|
    describe "ping client" do
      it "Server can ping the client to see if it's alive" do
        # This test involves bidirectional communication (server->client ping during tool execution)
        # Streamable transport needs more time under load due to HTTP/2 connection handling
        if config[:options][:transport_type] == :streamable
          test_client = RubyLLM::MCP::Client.new(
            **config[:options], request_timeout: 20_000, start: true
          )
          tool = test_client.tool("ping_client")
          result = tool.execute
          test_client.stop
        else
          tool = client.tool("ping_client")
          result = tool.execute
        end

        expect(result.to_s).to eq("Ping successful")
      end
    end

    describe "refreshes" do
      it "tool list when requested" do
        tools1 = client.tools
        tools2 = client.tools(refresh: true)
        expect(tools1.map(&:name)).to eq(tools2.map(&:name))
      end

      it "resources list when requested" do
        resources1 = client.resources
        resources2 = client.resources(refresh: true)
        expect(resources1.map(&:name)).to eq(resources2.map(&:name))
      end

      it "prompts list when requested" do
        prompts1 = client.prompts
        prompts2 = client.prompts(refresh: true)
        expect(prompts1.size).to eq(prompts2.size)
      end
    end

    # Capability stubbing tests - only work on native adapter
    describe "tools" do
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

    describe "resources" do
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
  end
end
