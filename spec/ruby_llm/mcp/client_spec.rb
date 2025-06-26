# frozen_string_literal: true

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

        it "initializes with a custom request_timeout" do
          merged_options = options[:options].merge(request_timeout: 15_000)
          client = RubyLLM::MCP::Client.new(**merged_options)
          expect(client.request_timeout).to eq(15_000)
          expect(client.instance_variable_get(:@coordinator).transport.instance_variable_get(:@request_timeout)).to eq(15_000)
          client.stop
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
    end
  end
end
