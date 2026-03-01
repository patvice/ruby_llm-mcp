# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Agents do
  def configure_agent_e2e_mcp!
    RubyLLM::MCP.instance_variable_set(:@clients, nil)
    RubyLLM::MCP.instance_variable_set(:@toolsets, nil)

    RubyLLM::MCP.configure do |config|
      config.mcp_configuration = [
        {
          name: "agent_stdio",
          adapter: :ruby_llm,
          transport_type: :stdio,
          start: false,
          request_timeout: 10_000,
          config: {
            command: "bun",
            args: ["spec/fixtures/typescript-mcp/index.ts", "--stdio"],
            env: { "TEST_ENV" => "this_is_a_test" }
          }
        }
      ]
    end
  end

  def cleanup_agent_e2e_mcp!
    RubyLLM::MCP.close_connection
    RubyLLM::MCP.instance_variable_set(:@clients, nil)
    RubyLLM::MCP.instance_variable_set(:@toolsets, nil)
  end

  before do
    RubyLLM::MCP.instance_variable_set(:@toolsets, nil)
  end

  after do
    RubyLLM::MCP.instance_variable_set(:@toolsets, nil)
  end

  describe "toolset resolution" do
    let(:clients) do
      {
        "filesystem" => double(
          "FilesystemClient",
          name: "filesystem",
          tools: [double("Tool", name: "read_file"), double("Tool", name: "delete_file")]
        ),
        "projects" => double("ProjectsClient", name: "projects", tools: [double("Tool", name: "list_projects")])
      }
    end

    it "fails closed when an unknown toolset name is configured" do
      klass = Class.new do
        include RubyLLM::MCP::Agents

        with_mcp_tools :typoed_toolset
      end

      expect do
        klass.mcp_tools_from_clients(clients)
      end.to raise_error(
        RubyLLM::MCP::Errors::ConfigurationError,
        /Unknown MCP toolset name\(s\): typoed_toolset/
      )

      expect(RubyLLM::MCP.toolsets).to eq({})
    end

    it "resolves tools from configured toolsets" do
      RubyLLM::MCP.toolset(
        :support,
        clients: [:filesystem],
        include_tools: ["read_file"]
      )

      klass = Class.new do
        include RubyLLM::MCP::Agents

        with_mcp_tools :support
      end

      tools = klass.mcp_tools_from_clients(clients)

      expect(tools.map(&:name)).to eq(["read_file"])
    end

    it "resolves tools directly from configured MCP clients" do
      klass = Class.new do
        include RubyLLM::MCP::Agents

        with_mcps :filesystem
      end

      tools = klass.mcp_tools_from_clients(clients)

      expect(tools.map(&:name)).to contain_exactly("read_file", "delete_file")
    end

    it "supports combining toolsets and mcp clients" do
      RubyLLM::MCP.toolset(
        :support,
        clients: [:projects],
        include_tools: ["list_projects"]
      )

      klass = Class.new do
        include RubyLLM::MCP::Agents

        with_toolsets :support
        with_mcps :filesystem
      end

      tools = klass.mcp_tools_from_clients(clients)

      expect(tools.map(&:name)).to contain_exactly("list_projects", "read_file", "delete_file")
    end

    it "fails closed when an unknown mcp client name is configured" do
      klass = Class.new do
        include RubyLLM::MCP::Agents

        with_mcps :unknown_mcp
      end

      expect do
        klass.mcp_tools_from_clients(clients)
      end.to raise_error(
        RubyLLM::MCP::Errors::ConfigurationError,
        /Unknown MCP client name\(s\): unknown_mcp/
      )
    end

    it "keeps with_mcp_tools as an alias for with_toolsets" do
      klass = Class.new do
        include RubyLLM::MCP::Agents

        with_mcp_tools :support
      end

      expect(klass.mcp_toolset_names).to eq(["support"])
    end

    it "accepts toolsets as varargs or arrays" do
      varargs_class = Class.new do
        include RubyLLM::MCP::Agents

        with_toolsets :support, :apples
      end
      array_class = Class.new do
        include RubyLLM::MCP::Agents

        with_toolsets %i[support apples]
      end

      expect(varargs_class.mcp_toolset_names).to eq(%w[support apples])
      expect(array_class.mcp_toolset_names).to eq(%w[support apples])
    end

    it "accepts mcps as varargs or arrays" do
      varargs_class = Class.new do
        include RubyLLM::MCP::Agents

        with_mcps :filesystem, :projects
      end
      array_class = Class.new do
        include RubyLLM::MCP::Agents

        with_mcps %i[filesystem projects]
      end

      expect(varargs_class.mcp_client_names).to eq(%w[filesystem projects])
      expect(array_class.mcp_client_names).to eq(%w[filesystem projects])
    end
  end

  describe "class-level DSL inheritance" do
    let(:base_class) do
      Class.new do
        include RubyLLM::MCP::Agents

        with_mcp_tools :support
        with_mcps :projects
      end
    end

    it "inherits toolset and mcp config in subclasses" do
      child_class = Class.new(base_class)

      expect(child_class.mcp_toolset_names).to eq(["support"])
      expect(child_class.mcp_client_names).to eq(["projects"])
    end

    it "allows subclasses to override inherited config" do
      child_class = Class.new(base_class) do
        with_mcp_tools :security
        with_mcps :filesystem
      end

      expect(child_class.mcp_toolset_names).to eq(["security"])
      expect(child_class.mcp_client_names).to eq(["filesystem"])
    end

    it "does not expose include_tools/exclude_tools in the agents DSL" do
      klass = Class.new do
        include RubyLLM::MCP::Agents
      end

      expect(klass).not_to respond_to(:include_tools)
      expect(klass).not_to respond_to(:exclude_tools)
    end
  end

  describe "end-to-end agent + toolset + llm" do
    before do
      MCPTestConfiguration.reset_config!
      MCPTestConfiguration.configure_ruby_llm!
      configure_agent_e2e_mcp!
    end

    after do
      cleanup_agent_e2e_mcp!
    end

    it "runs with_toolsets and calls MCP tool(s) during agent ask" do
      RubyLLM::MCP.toolset(
        :agent_messages,
        clients: [:agent_stdio],
        include_tools: ["list_messages"]
      )

      klass = Class.new(RubyLLM::Agent) do
        include RubyLLM::MCP::Agents

        model "gpt-4.1"
        with_toolsets :agent_messages
      end

      response = nil
      VCR.use_cassette(
        "with_stdio-native_with_openai_gpt-4_1_with_tool_adds_a_tool_to_the_chat",
        allow_playback_repeats: true
      ) do
        response = klass.new.ask("Can you pull messages for ruby channel and let me know what they say?")
      end

      expect(response.content).to include("Ruby is a great language")
    end

    it "runs with_mcps and calls MCP tool(s) during agent ask" do
      klass = Class.new(RubyLLM::Agent) do
        include RubyLLM::MCP::Agents

        model "gpt-4.1"
        with_mcps :agent_stdio
      end

      response = nil
      VCR.use_cassette(
        "with_stdio-native_with_openai_gpt-4_1_with_tools_adds_tools_to_the_chat",
        allow_playback_repeats: true
      ) do
        response = klass.new.ask("Can you add 1 and 2?")
      end

      expect(response.content).to include("3")
    end
  end
end
