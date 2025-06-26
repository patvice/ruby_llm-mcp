# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::Configuration do
  it "can be configured with support_complex_parameters!" do
    RubyLLM::MCP.configure(&:support_complex_parameters!)

    expect(RubyLLM::MCP.configuration.has_support_complex_parameters).to be(true)
  end

  it "can be configured with a custom logger" do
    RubyLLM::MCP.configure do |config|
      config.logger = Logger.new($stdout)
    end

    expect(RubyLLM::MCP.configuration.logger).to be_a(Logger)
  end

  it "does not share secerts if inspected" do
    RubyLLM::MCP.configure do |config|
      config.log_file = $stdout
      config.log_level = Logger::DEBUG
    end

    expect(RubyLLM::MCP.configuration.inspect).to include("log_file")
  end

  it "enable debug mode if RUBYLLM_MCP_DEBUG is set" do
    ENV["RUBYLLM_MCP_DEBUG"] = "true"
    expect(RubyLLM::MCP.configuration.log_level).to eq(Logger::DEBUG)
    ENV.delete("RUBYLLM_MCP_DEBUG")
  end
end
