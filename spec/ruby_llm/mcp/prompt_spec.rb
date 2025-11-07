# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::Prompt do
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    ClientRunner.build_client_runners(CLIENT_OPTIONS)
    ClientRunner.start_all
  end

  after(:all) do # rubocop:disable RSpec/BeforeAfterAll
    ClientRunner.stop_all
  end

  context "with #{PAGINATION_CLIENT_CONFIG[:name]}" do
    let(:client) { RubyLLM::MCP::Client.new(**PAGINATION_CLIENT_CONFIG) }

    before do
      client.start
    end

    after do
      client.stop
    end

    describe "prompts_list" do
      it "paginates prompts list to get all prompts" do
        prompts = client.prompts
        expect(prompts.count).to eq(2)
      end
    end
  end

  # Prompt tests - only run on adapters that support prompts
  each_client_supporting(:prompts) do |config|
    describe "prompts_list" do
      it "returns array of prompts" do
        prompts = client.prompts
        expect(prompts).to be_a(Array)
      end
    end

    describe "#execute_prompt" do
      it "returns prompt messages" do
        prompt = client.prompt("say_hello")
        messages = prompt.fetch

        expect(messages).to be_a(Array)
        expect(messages.first).to be_a(RubyLLM::Message)
        expect(messages.first.role).to eq(:user)
        expect(messages.first.content).to eq("Hello, how are you? Can you also say Hello back?")
      end

      it "returns multiple messages" do
        prompt = client.prompt("multiple_messages")
        messages = prompt.fetch

        expect(messages).to be_a(Array)

        message = messages.first
        expect(message).to be_a(RubyLLM::Message)
        expect(message.role).to eq(:assistant)
        expect(message.content).to eq("You are great at saying hello, the best in the world at it.")

        message = messages.last
        expect(message).to be_a(RubyLLM::Message)
        expect(message.role).to eq(:user)
        expect(message.content).to eq("Hello, how are you?")
      end
    end
  end

  # Refresh via notifications - only supported by adapters with notification support
  each_client_supporting(:notifications) do |config|
    describe "prompts_list" do
      it "refreshes prompts when requested" do
        tool = client.tool("send_list_changed")
        prompt_count = client.prompts.count
        tool.execute(type: "prompts")

        expect(client.prompts.count).to eq(prompt_count + 1)
      end
    end
  end
end
