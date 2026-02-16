# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Task Integration" do # rubocop:disable RSpec/DescribeClass
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    ClientRunner.build_client_runners(CLIENT_OPTIONS)
  end

  before do
    MCPTestConfiguration.reset_config!
    MCPTestConfiguration.configure_ruby_llm!
  end

  after do
    next unless respond_to?(:client)

    client.stop if client.alive?
  end

  def extract_task_id(content)
    match = content.to_s.match(/task_id:(task-[0-9a-f-]+)/)
    match&.captures&.first
  end

  def wait_for_task(client, task_id, statuses:, timeout: 8)
    deadline = Time.now + timeout
    observed_statuses = []
    loop do
      task = client.task_get(task_id)
      observed_statuses << task.status
      return task if statuses.include?(task.status)

      if Time.now >= deadline
        unique_statuses = observed_statuses.compact.uniq.join(", ")
        raise "Timed out waiting for task #{task_id} to reach #{statuses.join(', ')}. Observed: #{unique_statuses}"
      end

      sleep 0.05
    end
  end

  each_client_supporting(:tasks) do |config|
    let(:client) { RubyLLM::MCP::Client.new(**config[:options], start: false) }

    it "supports task lifecycle via tasks/list, tasks/get and tasks/result (e2e)" do
      client.start
      tool = wait_for_tool(client, "start_background_task")

      response = tool.execute(prompt: "Task completed via polling", delay_ms: 150)
      task_id = extract_task_id(response)

      expect(task_id).not_to be_nil

      listed_ids = client.tasks_list.map(&:task_id)
      expect(listed_ids).to include(task_id)

      completed_task = wait_for_task(client, task_id, statuses: ["completed"])
      expect(completed_task.completed?).to be(true)

      payload = client.task_result(task_id)
      expect(payload.dig("content", 0, "text")).to eq("Task completed via polling")
    end

    it "supports tasks/cancel for in-flight tasks (e2e)" do
      client.start
      tool = wait_for_tool(client, "start_background_task")

      response = tool.execute(prompt: "Should never complete", delay_ms: 1_000)
      task_id = extract_task_id(response)

      expect(task_id).not_to be_nil

      cancelled = client.task_cancel(task_id)
      expect(cancelled.cancelled?).to be(true)

      task = wait_for_task(client, task_id, statuses: ["cancelled"])
      expect(task.status_message).to include("Cancelled")
    end
  end

  each_client_supporting(:tasks, :sampling) do |config|
    let(:client) { RubyLLM::MCP::Client.new(**config[:options], start: false) }

    it "resolves llm-backed background tasks through sampling integration (e2e)" do
      RubyLLM::MCP.configure do |config|
        config.sampling.enabled = true
        config.sampling.preferred_model = "gpt-4o"
      end

      chat = instance_double(RubyLLM::Chat)
      sampled_message = double(
        "SampledMessage",
        role: "assistant",
        content: "Task summary from sampled llm",
        stop_reason: "end_turn"
      )
      allow(RubyLLM::Chat).to receive(:new).and_return(chat)
      allow(chat).to receive(:add_message)
      allow(chat).to receive(:complete).and_return(sampled_message)

      client.start
      tool = wait_for_tool(client, "start_llm_background_task")

      response = tool.execute(prompt: "Summarize why task polling is useful in one sentence.")
      task_id = extract_task_id(response)

      expect(task_id).not_to be_nil

      completed_task = wait_for_task(client, task_id, statuses: ["completed"])
      expect(completed_task.completed?).to be(true)

      payload = client.task_result(task_id)
      expect(payload.dig("content", 0, "text")).to include("Task summary from sampled llm")
      expect(RubyLLM::Chat).to have_received(:new).at_least(:once)
    end
  end
end
