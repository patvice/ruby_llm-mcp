# frozen_string_literal: true

module RubyLLM
  module MCP
    module Handlers
      # Registry for tracking pending human-in-the-loop approvals.
      # Registries are scoped per native client, with global ID routing so
      # approval IDs can still be completed externally.
      class HumanInTheLoopRegistry
        GLOBAL_OWNER = "__global__"

        class << self
          def instance
            for_owner(GLOBAL_OWNER)
          end

          def for_owner(owner_id)
            key = owner_id.to_s
            registries_mutex.synchronize do
              @registries ||= {}
              @registries[key] ||= new(owner_id: key)
            end
          end

          def release(owner_id)
            key = owner_id.to_s
            registry = registries_mutex.synchronize { (@registries ||= {}).delete(key) }
            registry&.shutdown
          end

          # Backward-compatible global store path.
          def store(id, approval)
            instance.store(id, approval)
          end

          def retrieve(id)
            route_registry(id)&.retrieve(id)
          end

          def remove(id)
            route_registry(id)&.remove(id)
          end

          def approve(id)
            registry = route_registry(id)
            if registry
              registry.approve(id)
            else
              RubyLLM::MCP.logger.warn("Attempted to approve unknown approval #{id}")
              false
            end
          end

          def deny(id, reason: "Denied")
            registry = route_registry(id)
            if registry
              registry.deny(id, reason: reason)
            else
              RubyLLM::MCP.logger.warn("Attempted to deny unknown approval #{id}")
              false
            end
          end

          def clear(owner_id: nil)
            if owner_id
              release(owner_id)
            else
              registries = registries_mutex.synchronize do
                current = (@registries ||= {}).values
                @registries = {}
                current
              end
              registries.each(&:shutdown)
            end
          end

          def size(owner_id: nil)
            if owner_id
              registry = registries_mutex.synchronize { (@registries ||= {})[owner_id.to_s] }
              registry ? registry.size : 0
            else
              registries_mutex.synchronize { (@registries ||= {}).values.sum(&:size) }
            end
          end

          def register_approval(id, owner_id)
            approval_index_mutex.synchronize do
              @approval_index ||= {}
              @approval_index[id.to_s] = owner_id.to_s
            end
          end

          def unregister_approval(id)
            approval_index_mutex.synchronize do
              (@approval_index ||= {}).delete(id.to_s)
            end
          end

          def route_registry(id)
            owner_id = approval_index_mutex.synchronize { (@approval_index ||= {})[id.to_s] }
            if owner_id
              registries_mutex.synchronize { (@registries ||= {})[owner_id] }
            else
              registries_mutex.synchronize { (@registries ||= {})[GLOBAL_OWNER] }
            end
          end

          private

          def registries_mutex
            @registries_mutex ||= Mutex.new
          end

          def approval_index_mutex
            @approval_index_mutex ||= Mutex.new
          end
        end

        attr_reader :owner_id

        def initialize(owner_id:)
          @owner_id = owner_id
          @registry = {}
          @deadlines = {}
          @registry_mutex = Mutex.new
          @condition = ConditionVariable.new
          @stopped = false
          start_timeout_scheduler
        end

        # Store approval context: { promise:, timeout:, tool_name:, parameters: }
        def store(id, approval_context)
          key = id.to_s
          timeout = approval_context[:timeout]

          @registry_mutex.synchronize do
            @registry[key] = approval_context
            if timeout
              @deadlines[key] = monotonic_now + timeout.to_f
            else
              @deadlines.delete(key)
            end
            @condition.signal
          end

          self.class.register_approval(key, owner_id)
          RubyLLM::MCP.logger.debug("Stored approval #{key} in registry for #{owner_id}")
        end

        def retrieve(id)
          @registry_mutex.synchronize { @registry[id.to_s] }
        end

        def remove(id)
          key = id.to_s
          approval = nil

          @registry_mutex.synchronize do
            approval = @registry.delete(key)
            @deadlines.delete(key)
            @condition.signal
          end

          self.class.unregister_approval(key) if approval
          RubyLLM::MCP.logger.debug("Removed approval #{key} from registry for #{owner_id}") if approval
          approval
        end

        def approve(id) # rubocop:disable Naming/PredicateMethod
          approval = remove(id)
          unless approval && approval[:promise]
            RubyLLM::MCP.logger.warn("Attempted to approve unknown approval #{id}")
            return false
          end

          RubyLLM::MCP.logger.info("Approving #{id}")
          approval[:promise].resolve(true)
          true
        end

        def deny(id, reason: "Denied") # rubocop:disable Naming/PredicateMethod
          approval = remove(id)
          unless approval && approval[:promise]
            RubyLLM::MCP.logger.warn("Attempted to deny unknown approval #{id}")
            return false
          end

          RubyLLM::MCP.logger.info("Denying #{id}: #{reason}")
          approval[:promise].resolve(false)
          true
        end

        def clear
          approvals = @registry_mutex.synchronize do
            current = @registry.dup
            @registry.clear
            @deadlines.clear
            @condition.broadcast
            current
          end

          approvals.each_key { |id| self.class.unregister_approval(id) }
          RubyLLM::MCP.logger.debug("Cleared human-in-the-loop registry for #{owner_id}")
        end

        def size
          @registry_mutex.synchronize { @registry.size }
        end

        def shutdown
          clear
          @registry_mutex.synchronize do
            @stopped = true
            @condition.broadcast
          end
          @scheduler_thread&.join(0.5)
        rescue StandardError => e
          RubyLLM::MCP.logger.debug("Error shutting down approval registry #{owner_id}: #{e.message}")
        ensure
          @scheduler_thread = nil
        end

        private

        def start_timeout_scheduler
          @scheduler_thread = Thread.new do
            loop do
              expired_ids = wait_for_expired_ids
              break if expired_ids.nil?

              expired_ids.each { |id| handle_timeout(id) }
            end
          end
        end

        def wait_for_expired_ids
          @registry_mutex.synchronize do
            loop do
              return nil if @stopped

              now = monotonic_now
              expired_ids = @deadlines.each_with_object([]) do |(id, deadline), ids|
                ids << id if deadline <= now
              end
              return expired_ids unless expired_ids.empty?

              if @deadlines.empty?
                @condition.wait(@registry_mutex)
              else
                wait_time = @deadlines.values.min - now
                @condition.wait(@registry_mutex, wait_time) if wait_time.positive?
              end
            end
          end
        end

        def handle_timeout(id)
          approval = remove(id)
          return unless approval && approval[:promise]

          RubyLLM::MCP.logger.warn("Approval #{id} timed out")
          approval[:promise].resolve(false)
        end

        def monotonic_now
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
