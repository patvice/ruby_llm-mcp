# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::Extensions::Registry do
  let(:canonical_id) { RubyLLM::MCP::Extensions::Constants::UI_EXTENSION_ID }
  let(:alias_id) { RubyLLM::MCP::Extensions::Constants::APPS_EXTENSION_ALIAS }

  describe ".canonicalize_id" do
    it "normalizes the legacy alias to canonical id" do
      expect(described_class.canonicalize_id(alias_id)).to eq(canonical_id)
      expect(described_class.canonicalize_id(canonical_id)).to eq(canonical_id)
    end
  end

  describe ".merge" do
    it "starts with global extensions and overlays per-client values" do
      global = {
        canonical_id => {
          "ui" => {
            "resourceUri" => "ui://global"
          },
          "nested" => {
            "keep" => true
          }
        }
      }

      client = {
        alias_id => {
          "ui" => {
            "resourceUri" => "ui://client"
          },
          "nested" => {
            "override" => true
          }
        }
      }

      merged = described_class.merge(global, client)

      expect(merged.keys).to eq([canonical_id])
      expect(merged[canonical_id]["ui"]["resourceUri"]).to eq("ui://client")
      expect(merged[canonical_id]["nested"]["keep"]).to be(true)
      expect(merged[canonical_id]["nested"]["override"]).to be(true)
    end

    it "treats nil extension values as enabled with empty config" do
      merged = described_class.merge({}, { canonical_id => nil })

      expect(merged).to eq(canonical_id => {})
    end
  end
end
