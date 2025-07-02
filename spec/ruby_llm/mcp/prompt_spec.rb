# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::Prompt do
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    ClientRunner.build_client_runners(CLIENT_OPTIONS)
    ClientRunner.start_all
  end

  after(:all) do # rubocop:disable RSpec/BeforeAfterAll
    ClientRunner.stop_all
  end

  CLIENT_OPTIONS.each do |config|
    context "with #{config[:name]}" do
      let(:client) { ClientRunner.fetch_client(config[:name]) }

      describe "prompts" do
        it "returns array of prompts" do
          prompts = client.prompts
          expect(prompts).to be_a(Array)
        end

        it "refreshes prompts when requested" do
          tool = client.tool("send_list_changed")
          prompt_count = client.prompts.count
          tool.execute(type: "prompts")

          expect(client.prompts.count).to eq(prompt_count + 1)
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

        it "returns multiple messages" do # rubocop:disable RSpec/MultipleExpectations
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
  end
end
