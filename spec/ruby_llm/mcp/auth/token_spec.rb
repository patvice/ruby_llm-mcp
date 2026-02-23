# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Auth::Token do
  describe "#to_header" do
    it "formats default bearer token type" do
      token = described_class.new(access_token: "abc123")

      expect(token.to_header).to eq("Bearer abc123")
    end

    it "normalizes lowercase bearer token type to canonical Bearer" do
      token = described_class.new(access_token: "abc123", token_type: "bearer")

      expect(token.to_header).to eq("Bearer abc123")
    end

    it "preserves non-bearer token types" do
      token = described_class.new(access_token: "abc123", token_type: "DPoP")

      expect(token.to_header).to eq("DPoP abc123")
    end
  end
end
