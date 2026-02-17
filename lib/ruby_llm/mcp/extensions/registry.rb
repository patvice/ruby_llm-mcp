# frozen_string_literal: true

module RubyLLM
  module MCP
    module Extensions
      module Registry
        module_function

        def canonicalize_id(id)
          return nil if id.nil?

          normalized = id.to_s.strip
          return nil if normalized.empty?

          Constants::EXTENSION_ALIASES.fetch(normalized, normalized)
        end

        def normalize_map(value)
          return {} unless value.is_a?(Hash)

          value.each_with_object({}) do |(id, config), acc|
            canonical_id = canonicalize_id(id)
            next if canonical_id.nil?

            acc[canonical_id] = normalize_value(config)
          end
        end

        def merge(global_extensions, client_extensions)
          merged = normalize_map(global_extensions)
          normalize_map(client_extensions).each do |id, config|
            merged[id] = deep_merge_values(merged[id], config)
          end
          merged
        end

        def deep_merge_values(base_value, override_value)
          if base_value.is_a?(Hash) && override_value.is_a?(Hash)
            deep_merge_hashes(base_value, override_value)
          else
            normalize_value(override_value)
          end
        end

        def normalize_value(value)
          case value
          when nil
            {}
          when Hash
            deep_stringify_keys(value)
          else
            value
          end
        end

        def deep_stringify_keys(value)
          case value
          when Hash
            value.each_with_object({}) do |(key, nested_value), acc|
              acc[key.to_s] = deep_stringify_keys(nested_value)
            end
          when Array
            value.map { |item| deep_stringify_keys(item) }
          else
            value
          end
        end

        def deep_merge_hashes(base_hash, override_hash)
          merged = base_hash.dup

          override_hash.each do |key, value|
            merged[key] = if merged[key].is_a?(Hash) && value.is_a?(Hash)
                            deep_merge_hashes(merged[key], value)
                          else
                            deep_stringify_keys(value)
                          end
          end

          merged
        end
      end
    end
  end
end
