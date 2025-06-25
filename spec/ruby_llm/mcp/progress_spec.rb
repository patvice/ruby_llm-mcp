# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::Progress do
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    ClientRunner.build_client_runners(CLIENT_OPTIONS)
    ClientRunner.start_all
  end

  after(:all) do # rubocop:disable RSpec/BeforeAfterAll
    ClientRunner.stop_all
  end

  CLIENT_OPTIONS.each do |options|
    context "with #{options[:name]}" do
      let(:client) do
        ClientRunner.client_runners[options[:name]].client
      end

      describe "basic tool execution" do
        it "can get progress from a tool" do
          progress = nil
          client.on_progress do |progress_update|
            progress = progress_update
          end

          client.tool("simple_progress").execute(progress: 75)

          expect(progress.progress).to eq(75)
          expect(progress.message).to eq("Progress: 75%")
          expect(progress.progress_token).to be_a(String)
        end

        it "can get multiple progress updates from a tool" do
          steps = 3
          count = 0
          client.on_progress do
            count += 1
          end
          client.tool("progress").execute(operation: "test_op", steps: steps)

          expect(count).to eq(steps + 1)
        end
      end
    end
  end
end
