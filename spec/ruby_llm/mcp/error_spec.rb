# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::Error do
  describe "#initialize" do
    it "extracts code, message, and data from error_data" do
      error_data = {
        "code" => -32_700,
        "message" => "Parse error",
        "data" => { "details" => "Invalid JSON" }
      }

      error = described_class.new(error_data)

      expect(error.instance_variable_get(:@code)).to eq(-32_700)
      expect(error.instance_variable_get(:@message)).to eq("Parse error")
      expect(error.instance_variable_get(:@data)).to eq({ "details" => "Invalid JSON" })
    end

    it "handles missing optional fields" do
      error_data = { "code" => -32_600 }

      error = described_class.new(error_data)

      expect(error.instance_variable_get(:@code)).to eq(-32_600)
      expect(error.instance_variable_get(:@message)).to be_nil
      expect(error.instance_variable_get(:@data)).to be_nil
    end

    it "handles empty error data" do
      error_data = {}

      error = described_class.new(error_data)

      expect(error.instance_variable_get(:@code)).to be_nil
      expect(error.instance_variable_get(:@message)).to be_nil
      expect(error.instance_variable_get(:@data)).to be_nil
    end
  end

  describe "#type" do
    it "returns :parse_error for code -32700" do
      error = described_class.new({ "code" => -32_700 })
      expect(error.type).to eq(:parse_error)
    end

    it "returns :invalid_request for code -32600" do
      error = described_class.new({ "code" => -32_600 })
      expect(error.type).to eq(:invalid_request)
    end

    it "returns :method_not_found for code -32601" do
      error = described_class.new({ "code" => -32_601 })
      expect(error.type).to eq(:method_not_found)
    end

    it "returns :invalid_params for code -32602" do
      error = described_class.new({ "code" => -32_602 })
      expect(error.type).to eq(:invalid_params)
    end

    it "returns :internal_error for code -32603" do
      error = described_class.new({ "code" => -32_603 })
      expect(error.type).to eq(:internal_error)
    end

    it "returns :custom_error for unknown codes" do
      error = described_class.new({ "code" => -1000 })
      expect(error.type).to eq(:custom_error)
    end

    it "returns :custom_error for positive codes" do
      error = described_class.new({ "code" => 1000 })
      expect(error.type).to eq(:custom_error)
    end

    it "returns :custom_error for nil code" do
      error = described_class.new({})
      expect(error.type).to eq(:custom_error)
    end
  end

  describe "#to_s" do
    it "formats error with all fields present" do
      error_data = {
        "code" => -32_700,
        "message" => "Parse error",
        "data" => { "details" => "Invalid JSON" }
      }
      error = described_class.new(error_data)

      result = error.to_s

      expect(result).to eq(
        "Error: code: -32700 (parse_error), message: Parse error, data: {\"details\"=>\"Invalid JSON\"}"
      )
    end

    it "formats error with missing message" do
      error_data = {
        "code" => -32_600,
        "data" => { "info" => "test" }
      }
      error = described_class.new(error_data)

      result = error.to_s

      expect(result).to eq("Error: code: -32600 (invalid_request), message: , data: {\"info\"=>\"test\"}")
    end

    it "formats error with missing data" do
      error_data = {
        "code" => -32_601,
        "message" => "Method not found"
      }
      error = described_class.new(error_data)

      result = error.to_s

      expect(result).to eq("Error: code: -32601 (method_not_found), message: Method not found, data: ")
    end

    it "formats error with all fields missing" do
      error = described_class.new({})

      result = error.to_s

      expect(result).to eq("Error: code:  (custom_error), message: , data: ")
    end

    it "formats error with custom error code" do
      error_data = {
        "code" => -5000,
        "message" => "Custom error",
        "data" => "custom data"
      }
      error = described_class.new(error_data)

      result = error.to_s

      expect(result).to eq("Error: code: -5000 (custom_error), message: Custom error, data: custom data")
    end
  end

  describe "JSON-RPC error code constants" do
    it "correctly maps all standard JSON-RPC error codes" do
      standard_codes = {
        -32_700 => :parse_error,
        -32_600 => :invalid_request,
        -32_601 => :method_not_found,
        -32_602 => :invalid_params,
        -32_603 => :internal_error
      }

      standard_codes.each do |code, expected_type|
        error = described_class.new({ "code" => code })
        expect(error.type).to eq(expected_type), "Expected code #{code} to map to #{expected_type}"
      end
    end
  end
end
