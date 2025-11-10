# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Auth::GrantStrategies do
  describe "Base" do
    subject(:strategy) { RubyLLM::MCP::Auth::GrantStrategies::Base.new }

    it "raises NotImplementedError for auth_method" do
      expect { strategy.auth_method }.to raise_error(NotImplementedError, /must implement #auth_method/)
    end

    it "raises NotImplementedError for grant_types_list" do
      expect { strategy.grant_types_list }.to raise_error(NotImplementedError, /must implement #grant_types_list/)
    end

    it "raises NotImplementedError for response_types_list" do
      expect { strategy.response_types_list }.to raise_error(NotImplementedError, /must implement #response_types_list/)
    end
  end

  describe "AuthorizationCode" do
    subject(:strategy) { RubyLLM::MCP::Auth::GrantStrategies::AuthorizationCode.new }

    it "uses 'none' auth method for public clients" do
      expect(strategy.auth_method).to eq("none")
    end

    it "requests authorization_code and refresh_token grant types" do
      expect(strategy.grant_types_list).to eq(%w[authorization_code refresh_token])
    end

    it "requests 'code' response type" do
      expect(strategy.response_types_list).to eq(["code"])
    end
  end

  describe "ClientCredentials" do
    subject(:strategy) { RubyLLM::MCP::Auth::GrantStrategies::ClientCredentials.new }

    it "uses 'client_secret_post' auth method" do
      expect(strategy.auth_method).to eq("client_secret_post")
    end

    it "requests client_credentials and refresh_token grant types" do
      expect(strategy.grant_types_list).to eq(%w[client_credentials refresh_token])
    end

    it "requests no response types (no redirect flow)" do
      expect(strategy.response_types_list).to eq([])
    end
  end
end
