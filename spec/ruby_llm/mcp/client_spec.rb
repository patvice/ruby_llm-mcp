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

      describe "ping" do
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
          new_client = RubyLLM::MCP::Client.new(
            name: "fake-client",
            transport_type: :streamable,
            start: false,
            config: {
              url: "http://localhost:5555/mcp"
            }
          )

          ping = new_client.ping
          expect(ping).to be(false)
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
      end

      describe "resource" do
        it "returns specific resource by name" do
          resource = client.resource("test.txt")
          expect(resource).to be_a(RubyLLM::MCP::Resource)
          expect(resource.name).to eq("test.txt")
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
      end

      describe "prompt" do
        it "returns specific prompt by name if available" do
          prompt = client.prompt("nonexistent")
          expect(prompt).to be_nil
        end
      end

      describe "on_logging" do
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
