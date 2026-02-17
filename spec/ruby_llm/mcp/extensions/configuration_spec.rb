# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::Extensions::Configuration do
  let(:canonical_id) { RubyLLM::MCP::Extensions::Constants::UI_EXTENSION_ID }

  describe "#register" do
    it "registers an extension" do
      config = described_class.new

      config.register(canonical_id, "enabled" => true)

      expect(config.to_h).to eq(canonical_id => { "enabled" => true })
    end

    it "merges extension config for repeated registrations" do
      config = described_class.new

      config.register(canonical_id, "ui" => { "resourceUri" => "ui://one" })
      config.register(canonical_id, "ui" => { "visibility" => ["app"] })

      expect(config.to_h[canonical_id]["ui"]).to eq(
        "resourceUri" => "ui://one",
        "visibility" => ["app"]
      )
    end
  end

  describe "#enable_apps" do
    it "registers the canonical apps extension id with default mimeTypes" do
      config = described_class.new

      config.enable_apps

      expect(config.to_h).to eq(
        canonical_id => {
          "mimeTypes" => ["text/html;profile=mcp-app"]
        }
      )
    end

    it "allows explicit mimeTypes override" do
      config = described_class.new

      config.enable_apps("mimeTypes" => ["text/html;profile=mcp-app", "text/html"])

      expect(config.to_h).to eq(
        canonical_id => {
          "mimeTypes" => ["text/html;profile=mcp-app", "text/html"]
        }
      )
    end

    it "rejects tool metadata fields in extension capability config" do
      config = described_class.new

      expect do
        config.enable_apps("ui" => { "resourceUri" => "ui://bad" })
      end.to raise_error(ArgumentError, /tool metadata fields/)
    end
  end

  describe "#reset!" do
    it "clears all extension registrations" do
      config = described_class.new
      config.register(canonical_id, "enabled" => true)

      config.reset!

      expect(config.empty?).to be(true)
      expect(config.to_h).to eq({})
    end
  end
end
