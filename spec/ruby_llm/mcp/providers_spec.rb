# frozen_string_literal: true

require "spec_helper"
require "ruby_llm/tool"

RSpec.describe RubyLLM::MCP::Providers do
  before do
    RubyLLM::MCP.support_complex_parameters!
  end

  let(:base_parameters) do
    {
      name: RubyLLM::Parameter.new(:name, type: :string, desc: "User name", required: true),
      age: RubyLLM::Parameter.new(:age, type: :integer, desc: "User age", required: false)
    }
  end

  let(:mcp_parameters) do
    {
      name: RubyLLM::MCP::Parameter.new(:name, type: :string, title: "Name", desc: "User name", required: true),
      age: RubyLLM::MCP::Parameter.new(:age, type: :integer, title: "Age", desc: "User age", required: false)
    }
  end

  let(:mixed_parameters) do
    {
      name: RubyLLM::Parameter.new(:name, type: :string, desc: "User name", required: true),
      age: RubyLLM::MCP::Parameter.new(:age, type: :integer, title: "Age", desc: "User age", required: false)
    }
  end

  describe "Anthropic::Tools monkey patches" do
    let(:tools_module) { RubyLLM::Providers::Anthropic::Tools }

    it "handles base RubyLLM::Parameter in clean_parameters" do
      expect do
        result = tools_module.clean_parameters(base_parameters)
        expect(result).to be_a(Hash)
        expect(result[:name]).to have_key(:type)
        expect(result[:name]).to have_key(:description)
      end.not_to raise_error
    end

    it "handles MCP::Parameter in clean_parameters with MCP attributes" do
      result = tools_module.clean_parameters(mcp_parameters)

      expect(result).to be_a(Hash)
      expect(result[:name][:title]).to eq("Name")
      expect(result[:name][:description]).to eq("User name")
      expect(result[:age][:title]).to eq("Age")
    end

    it "handles base RubyLLM::Parameter in required_parameters" do
      expect do
        result = tools_module.required_parameters(base_parameters)
        expect(result).to include(:name)
        expect(result).not_to include(:age)
      end.not_to raise_error
    end

    it "handles MCP::Parameter in required_parameters" do
      result = tools_module.required_parameters(mcp_parameters)

      expect(result).to include(:name)
      expect(result).not_to include(:age)
    end

    it "falls back to original implementation with mixed parameters" do
      expect do
        result = tools_module.clean_parameters(mixed_parameters)
        expect(result).to be_a(Hash)
        expect(result[:name]).to have_key(:type)
        expect(result[:name]).to have_key(:description)
      end.not_to raise_error
    end
  end

  describe "Gemini::Tools monkey patches" do
    let(:tools_module) { RubyLLM::Providers::Gemini::Tools }

    it "handles base RubyLLM::Parameter in format_parameters" do
      expect do
        result = tools_module.format_parameters(base_parameters)
        expect(result).to be_a(Hash)
        expect(result).to have_key(:type)
        expect(result).to have_key(:properties)
      end.not_to raise_error
    end

    it "handles MCP::Parameter in format_parameters with MCP attributes" do
      result = tools_module.format_parameters(mcp_parameters)

      expect(result).to be_a(Hash)
      expect(result[:type]).to eq("OBJECT")
      expect(result[:properties][:name][:title]).to eq("Name")
      expect(result[:properties][:name][:description]).to eq("User name")
      expect(result[:required]).to include("name")
    end

    it "falls back to original implementation with mixed parameters" do
      ## Likely should not be possible, but just in case we will resolve gracefully but reducing what is passed
      expect do
        result = tools_module.format_parameters(mixed_parameters)
        expect(result).to be_a(Hash)
        expect(result).to have_key(:type)
        expect(result).to have_key(:properties)
      end.not_to raise_error
    end
  end

  describe "OpenAI::Tools monkey patches" do
    let(:tools_module) { RubyLLM::Providers::OpenAI::Tools }
    let(:base_param) { base_parameters[:name] }
    let(:mcp_param) { mcp_parameters[:name] }

    it "handles base RubyLLM::Parameter in param_schema" do
      expect do
        result = tools_module.param_schema(base_param)
        expect(result).to be_a(Hash)
        expect(result).to have_key(:type)
        expect(result).to have_key(:description)
      end.not_to raise_error
    end

    it "handles MCP::Parameter in param_schema with MCP attributes" do
      result = tools_module.param_schema(mcp_param)

      expect(result).to be_a(Hash)
      expect(result[:title]).to eq("Name")
      expect(result[:description]).to eq("User name")
      expect(result[:type]).to eq(:string)
    end
  end
end
