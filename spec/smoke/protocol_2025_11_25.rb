#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "json"
require "ruby_llm"
require "ruby_llm/mcp"
require "ruby_llm/mcp/native/transports/support/timeout"

require_relative "../support/mcp_test_configuration"
require_relative "../support/test_server_manager"

module Protocol20251125SmokeTest
  TARGET_PROTOCOL_VERSION = "2025-11-25"
  WAIT_TIMEOUT = 10

  TRANSPORT_CONFIGS = [
    {
      name: "streamable-native",
      transport_type: :streamable,
      config: {
        url: TestServerManager::HTTP_SERVER_URL
      }
    },
    {
      name: "stdio-native",
      transport_type: :stdio,
      config: {
        command: "bun",
        args: ["spec/fixtures/typescript-mcp/index.ts", "--stdio", "--silent"]
      }
    }
  ].freeze

  module_function

  def run!
    results = []

    TestServerManager.start_server

    TRANSPORT_CONFIGS.each do |transport_config|
      results.concat(run_transport_suite(transport_config))
    end

    print_summary(results)
  ensure
    TestServerManager.stop_server
  end

  def run_transport_suite(transport_config)
    configure_for_protocol!
    client = build_client(transport_config)
    configure_callbacks!(client)
    client.start

    execute_transport_checks(client, transport_config)
  ensure
    client&.stop if client&.alive?
  end

  def build_client(transport_config)
    RubyLLM::MCP::Client.new(
      name: "protocol-smoke-#{transport_config[:name]}",
      adapter: :ruby_llm,
      transport_type: transport_config[:transport_type],
      config: transport_config[:config],
      start: false
    )
  end

  def execute_transport_checks(client, transport_config)
    [
      run_check(transport_config, "negotiates protocol #{TARGET_PROTOCOL_VERSION}") do
        check_protocol_negotiation(client)
      end,
      run_check(transport_config, "advertises new client capability shape") do
        check_capabilities(client)
      end,
      run_check(transport_config, "executes sampling via client callback") do
        check_sampling(client)
      end,
      run_check(transport_config, "executes elicitation flow") do
        check_elicitation(client)
      end,
      run_check(transport_config, "supports tasks/list, tasks/get, tasks/result") do
        check_task_lifecycle(client)
      end,
      run_check(transport_config, "supports tasks/cancel") do
        check_task_cancel(client)
      end
    ]
  end

  def check_protocol_negotiation(client)
    protocol = client.adapter.native_client.protocol_version
    assert(protocol == TARGET_PROTOCOL_VERSION, "expected #{TARGET_PROTOCOL_VERSION}, got #{protocol.inspect}")
  end

  def check_capabilities(client)
    capabilities = fetch_client_capabilities(client)
    assert(capabilities.dig("sampling", "context") == {}, "missing sampling.context capability")
    assert(capabilities.dig("sampling", "tools") == {}, "missing sampling.tools capability")
    assert(capabilities.dig("elicitation", "form") == {}, "missing elicitation.form capability")
    assert(capabilities.dig("elicitation", "url") == {}, "missing elicitation.url capability")
    assert(capabilities.dig("tasks", "list") == {}, "missing tasks.list capability")
    assert(capabilities.dig("tasks", "cancel") == {}, "missing tasks.cancel capability")
    assert(capabilities.dig("tasks", "requests").nil?, "tasks.requests should not be advertised")
  end

  def check_sampling(client)
    tool = wait_for_tool(client, "sampling-test")
    response = tool.execute.to_s
    assert(response.include?("Sampling test completed"), "sampling tool did not complete: #{response.inspect}")
    assert(response.include?("sampled-response-from-client"),
           "custom sampled response not found in: #{response.inspect}")
  end

  def check_elicitation(client)
    simple_tool = wait_for_tool(client, "simple_elicitation")
    simple_response = simple_tool.execute(message: "Please confirm this action").to_s
    assert(simple_response.include?("Simple elicitation completed"),
           "simple elicitation did not complete: #{simple_response.inspect}")
    assert(simple_response.include?("\"confirmed\":true"), "simple elicitation response missing confirmation")

    preference_tool = wait_for_tool(client, "user_preference_elicitation")
    preference_response = preference_tool.execute(scenario: "protocol smoke test").to_s
    assert(preference_response.include?("Collected user preferences"),
           "preference elicitation did not complete: #{preference_response.inspect}")
    assert(preference_response.include?("\"preference\":\"option_a\""), "preference elicitation missing option")
  end

  def check_task_lifecycle(client)
    task_tool = wait_for_tool(client, "start_background_task")
    response = task_tool.execute(prompt: "Task completed via protocol smoke script", delay_ms: 150).to_s
    task_id = extract_task_id(response)
    assert(!task_id.nil?, "task id was not returned")

    listed_ids = client.tasks_list.map(&:task_id)
    assert(listed_ids.include?(task_id), "task #{task_id} not present in tasks/list")

    completed = wait_for_task(client, task_id, statuses: ["completed"])
    assert(completed.completed?, "task #{task_id} did not reach completed status")

    payload = client.task_result(task_id)
    actual_text = payload.dig("content", 0, "text")
    expected_text = "Task completed via protocol smoke script"
    assert(actual_text == expected_text, "unexpected task result payload: #{actual_text.inspect}")
  end

  def check_task_cancel(client)
    task_tool = wait_for_tool(client, "start_background_task")
    response = task_tool.execute(prompt: "This should be cancelled", delay_ms: 5_000).to_s
    task_id = extract_task_id(response)
    assert(!task_id.nil?, "task id was not returned for cancellable task")

    cancelled = client.task_cancel(task_id)
    assert(cancelled.cancelled?, "tasks/cancel did not return cancelled state")

    cancelled_task = wait_for_task(client, task_id, statuses: ["cancelled"])
    assert(cancelled_task.status_message.to_s.include?("Cancelled"), "cancelled task missing status message")
  end

  def configure_for_protocol!
    MCPTestConfiguration.reset_config!
    MCPTestConfiguration.configure_ruby_llm!

    RubyLLM::MCP.configure do |config|
      config.protocol_version = TARGET_PROTOCOL_VERSION
      config.sampling.enabled = true
      config.sampling.tools = true
      config.sampling.context = true
      config.sampling.preferred_model = "gpt-4o-mini"
      config.elicitation.form = true
      config.elicitation.url = true
      config.tasks.enabled = true

      # Must be set before client initialization so elicitation capability
      # is advertised in initialize.
      config.on_elicitation do |elicitation|
        elicitation.structured_response = if elicitation.message.to_s.include?("user preferences")
                                            {
                                              "preference" => "option_a",
                                              "confidence" => 0.9,
                                              "reasoning" => "Used by protocol smoke test"
                                            }
                                          else
                                            {
                                              "response" => "approved",
                                              "confirmed" => true
                                            }
                                          end
        true
      end
    end
  end

  def configure_callbacks!(client)
    client.on_sampling do |_sample|
      sampled_message = Struct.new(:role, :content, :stop_reason).new(
        "assistant",
        "sampled-response-from-client",
        "end_turn"
      )
      { accepted: true, response: sampled_message }
    end
  end

  def wait_for_tool(client, tool_name)
    deadline = Time.now + WAIT_TIMEOUT

    loop do
      tool = client.tool(tool_name)
      return tool if tool

      raise "timed out waiting for tool #{tool_name.inspect}" if Time.now > deadline

      sleep 0.1
    end
  end

  def fetch_client_capabilities(client)
    tool = wait_for_tool(client, "client-capabilities")
    raw = tool.execute.to_s
    payload = raw.sub(/\AClient capabilities:\s*/, "")
    JSON.parse(payload)
  rescue JSON::ParserError => e
    raise "could not parse client capabilities JSON: #{e.message}; raw=#{raw.inspect}"
  end

  def extract_task_id(content)
    content.to_s[/task_id:(task-[0-9a-f-]+)/, 1]
  end

  def wait_for_task(client, task_id, statuses:, timeout: WAIT_TIMEOUT)
    deadline = Time.now + timeout

    loop do
      task = client.task_get(task_id)
      return task if statuses.include?(task.status)

      if Time.now > deadline
        raise "timed out waiting for task #{task_id} to reach #{statuses.join(', ')}; " \
              "last status=#{task.status.inspect}"
      end

      sleep 0.05
    end
  end

  def run_check(transport_config, check_name)
    yield

    { transport: transport_config[:name], check: check_name, status: :pass }
  rescue StandardError => e
    { transport: transport_config[:name], check: check_name, status: :fail, error: e }
  end

  def print_summary(results)
    failures = results.select { |result| result[:status] == :fail }
    return if failures.empty?

    details = failures.map do |failure|
      "[#{failure[:transport]}] #{failure[:check]}: #{failure[:error].message}"
    end
    raise "Protocol #{TARGET_PROTOCOL_VERSION} smoke failures:\n#{details.join("\n")}"
  end

  def assert(condition, message)
    raise message unless condition
  end
end

Protocol20251125SmokeTest.run!
