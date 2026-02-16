# frozen_string_literal: true

module RubyLLM
  module MCP
    module Native
      # In-memory task state cache used by the native client.
      # This keeps task metadata/status synchronized across list/get/cancel calls
      # and out-of-band status notifications.
      class TaskRegistry
        def initialize
          @tasks = {}
          @payloads = {}
          @mutex = Mutex.new
        end

        def upsert(task_hash)
          return if task_hash.nil? || task_hash["taskId"].nil?

          @mutex.synchronize do
            @tasks[task_hash["taskId"]] = task_hash
          end
        end

        def upsert_many(task_hashes)
          Array(task_hashes).each { |task| upsert(task) }
        end

        def store_payload(task_id, payload)
          return if task_id.nil?

          @mutex.synchronize do
            @payloads[task_id] = payload
          end
        end

        def task(task_id)
          @mutex.synchronize { @tasks[task_id] }
        end

        def payload(task_id)
          @mutex.synchronize { @payloads[task_id] }
        end

        def tasks
          @mutex.synchronize { @tasks.values }
        end

        def update_status(task_id, status:, status_message: nil)
          @mutex.synchronize do
            task = @tasks[task_id]
            return nil unless task

            task["status"] = status
            task["statusMessage"] = status_message unless status_message.nil?
            task["lastUpdatedAt"] = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
            task
          end
        end
      end
    end
  end
end
