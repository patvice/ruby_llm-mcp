# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::Native::Protocol do
  describe "supported versions" do
    it "includes the draft protocol version" do
      expect(described_class.supported_versions).to include(described_class::DRAFT_PROTOCOL_VERSION)
      expect(described_class.supported_version?(described_class::DRAFT_PROTOCOL_VERSION)).to be(true)
    end
  end

  describe ".date_version?" do
    it "returns true for valid date versions" do
      expect(described_class.date_version?("2026-01-26")).to be(true)
    end

    it "returns false for non-date versions" do
      expect(described_class.date_version?("DRAFT-2026-01-26")).to be(false)
      expect(described_class.date_version?("invalid")).to be(false)
      expect(described_class.date_version?(nil)).to be(false)
    end
  end

  describe ".compare_date_versions" do
    it "compares date versions" do
      expect(described_class.compare_date_versions("2026-01-26", "2025-06-18")).to eq(1)
      expect(described_class.compare_date_versions("2025-06-18", "2025-06-18")).to eq(0)
      expect(described_class.compare_date_versions("2024-10-07", "2025-06-18")).to eq(-1)
    end

    it "returns nil for invalid inputs" do
      expect(described_class.compare_date_versions("invalid", "2025-06-18")).to be_nil
      expect(described_class.compare_date_versions("2025-06-18", "invalid")).to be_nil
    end
  end

  describe ".draft_or_newer?" do
    it "returns true for date versions at or above draft" do
      expect(described_class.draft_or_newer?("2026-01-26")).to be(true)
      expect(described_class.draft_or_newer?("2026-03-01")).to be(true)
    end

    it "returns true for DRAFT labels" do
      expect(described_class.draft_or_newer?("DRAFT-2026-01-26")).to be(true)
      expect(described_class.draft_or_newer?("DRAFT-next")).to be(true)
    end

    it "returns false for nil, invalid, and older versions" do
      expect(described_class.draft_or_newer?(nil)).to be(false)
      expect(described_class.draft_or_newer?("invalid")).to be(false)
      expect(described_class.draft_or_newer?("2025-06-18")).to be(false)
    end
  end

  describe ".extensions_supported?" do
    it "returns true for stable versions at or above 2025-06-18" do
      expect(described_class.extensions_supported?("2025-06-18")).to be(true)
      expect(described_class.extensions_supported?("2026-01-26")).to be(true)
    end

    it "returns true for DRAFT labels" do
      expect(described_class.extensions_supported?("DRAFT-2026-01-26")).to be(true)
      expect(described_class.extensions_supported?("DRAFT-next")).to be(true)
    end

    it "returns false for nil, invalid, and older stable versions" do
      expect(described_class.extensions_supported?(nil)).to be(false)
      expect(described_class.extensions_supported?("invalid")).to be(false)
      expect(described_class.extensions_supported?("2025-03-26")).to be(false)
    end
  end
end
