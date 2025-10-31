# frozen_string_literal: true

require "spec_helper"
require "ruby_llm/tool"

RSpec.describe "Parameter compatibility" do
  before do
    RubyLLM::MCP.support_complex_parameters!
  end

  let(:base_parameter) do
    RubyLLM::Parameter.new(:test_param, type: :string, desc: "Test parameter", required: true)
  end

  let(:mcp_parameter) do
    RubyLLM::MCP::Parameter.new(:test_param, type: :string, title: "Test Title", desc: "Test parameter", required: true)
  end

  describe "Anthropic ComplexParameterSupport" do
    it "handles base RubyLLM::Parameter without MCP attributes" do
      support = RubyLLM::MCP::Providers::Anthropic::ComplexParameterSupport

      expect {
        support.build_properties(base_parameter)
      }.not_to raise_error
    end

    it "handles MCP::Parameter with MCP attributes" do
      support = RubyLLM::MCP::Providers::Anthropic::ComplexParameterSupport

      result = support.build_properties(mcp_parameter)

      expect(result[:title]).to eq("Test Title")
      expect(result[:description]).to eq("Test parameter")
    end
  end

  describe "Gemini ComplexParameterSupport" do
    it "handles base RubyLLM::Parameter without MCP attributes" do
      support = RubyLLM::MCP::Providers::Gemini::ComplexParameterSupport

      expect {
        support.format_parameters({ test: base_parameter })
      }.not_to raise_error
    end
  end

  describe "OpenAI ComplexParameterSupport" do
    it "handles base RubyLLM::Parameter without MCP attributes" do
      support = RubyLLM::MCP::Providers::OpenAI::ComplexParameterSupport

      expect {
        support.param_schema(base_parameter)
      }.not_to raise_error
    end
  end
end
