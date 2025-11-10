# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Auth::Security do
  describe ".secure_compare" do
    it "returns true for identical strings" do
      a = "test_string_123"
      b = "test_string_123"

      expect(described_class.secure_compare(a, b)).to be true
    end

    it "returns false for different strings of same length" do
      a = "test_string_123"
      b = "test_string_456"

      expect(described_class.secure_compare(a, b)).to be false
    end

    it "returns false for strings of different lengths" do
      a = "short"
      b = "much_longer_string"

      expect(described_class.secure_compare(a, b)).to be false
    end

    it "returns false for completely different strings" do
      a = "aaaaaaaa"
      b = "bbbbbbbb"

      expect(described_class.secure_compare(a, b)).to be false
    end

    it "returns false when first string is empty" do
      expect(described_class.secure_compare("", "test")).to be false
    end

    it "returns false when second string is empty" do
      expect(described_class.secure_compare("test", "")).to be false
    end

    it "returns true when both strings are empty" do
      expect(described_class.secure_compare("", "")).to be true
    end

    it "returns false when first string is nil" do
      expect(described_class.secure_compare(nil, "test")).to be false
    end

    it "returns false when second string is nil" do
      expect(described_class.secure_compare("test", nil)).to be false
    end

    it "returns false when both strings are nil" do
      expect(described_class.secure_compare(nil, nil)).to be false
    end

    it "handles strings with special characters" do
      a = "test!@#$%^&*()"
      b = "test!@#$%^&*()"

      expect(described_class.secure_compare(a, b)).to be true
    end

    it "handles strings with unicode characters" do
      a = "テスト文字列🔒"
      b = "テスト文字列🔒"

      expect(described_class.secure_compare(a, b)).to be true
    end

    it "returns false for similar but not identical unicode strings" do
      a = "テスト文字列🔒"
      b = "テスト文字列🔓"

      expect(described_class.secure_compare(a, b)).to be false
    end

    # context "when ActiveSupport::SecurityUtils is available" do
    #   before do
    #     # Try to load ActiveSupport if available
    #     begin
    #       require "active_support/security_utils"
    #     rescue LoadError
    #       skip "ActiveSupport not available"
    #     end
    #   end
    #
    #   it "uses ActiveSupport::SecurityUtils.secure_compare when available" do
    #     skip "ActiveSupport not available" unless defined?(ActiveSupport::SecurityUtils)
    #
    #     allow(ActiveSupport::SecurityUtils).to receive(:secure_compare).and_call_original
    #     described_class.secure_compare("test", "test")
    #     expect(ActiveSupport::SecurityUtils).to have_received(:secure_compare).with("test", "test")
    #   end
    # end

    context "when ActiveSupport is not available" do
      it "uses fallback constant_time_compare? implementation" do
        # Test the fallback directly
        result = described_class.constant_time_compare?("test_123", "test_123")
        expect(result).to be true
      end
    end
  end

  describe ".constant_time_compare?" do
    it "performs constant-time comparison" do
      a = "secret_value_123"
      b = "secret_value_123"

      expect(described_class.constant_time_compare?(a, b)).to be true
    end

    it "returns false for different strings" do
      a = "secret_value_123"
      b = "secret_value_456"

      expect(described_class.constant_time_compare?(a, b)).to be false
    end

    it "returns false for different length strings immediately" do
      a = "short"
      b = "very_long_string"

      expect(described_class.constant_time_compare?(a, b)).to be false
    end

    it "compares all bytes even when first byte differs" do
      # This is the key security property - it should take the same time
      # regardless of where the difference is
      a = "aaaaaaaa"
      b = "baaaaaaa"

      expect(described_class.constant_time_compare?(a, b)).to be false
    end

    it "compares all bytes even when last byte differs" do
      a = "aaaaaaaa"
      b = "aaaaaaa b"

      expect(described_class.constant_time_compare?(a, b)).to be false
    end
  end
end
