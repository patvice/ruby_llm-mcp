# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Native::Transports::Support::RateLimiter do
  describe "#initialize" do
    it "uses default values when no arguments provided" do
      rate_limiter = described_class.new

      # Should allow up to 10 requests initially
      10.times { rate_limiter.add }
      expect(rate_limiter.exceeded?).to be(true)
    end

    it "accepts custom limit and interval" do
      rate_limiter = described_class.new(limit: 3, interval: 500)

      3.times { rate_limiter.add }
      expect(rate_limiter.exceeded?).to be(true)
    end
  end

  describe "#exceeded?" do
    it "returns false when no requests have been made" do
      rate_limiter = described_class.new(limit: 5, interval: 1000)

      expect(rate_limiter.exceeded?).to be(false)
    end

    it "returns false when under limit" do
      rate_limiter = described_class.new(limit: 5, interval: 1000)

      3.times { rate_limiter.add }

      expect(rate_limiter.exceeded?).to be(false)
    end

    it "returns true when at limit" do
      rate_limiter = described_class.new(limit: 3, interval: 1000)

      3.times { rate_limiter.add }

      expect(rate_limiter.exceeded?).to be(true)
    end

    it "returns true when over limit" do
      rate_limiter = described_class.new(limit: 3, interval: 1000)

      5.times { rate_limiter.add }

      expect(rate_limiter.exceeded?).to be(true)
    end

    it "allows requests again after interval expires" do
      rate_limiter = described_class.new(limit: 2, interval: 0.1) # 100ms interval

      2.times { rate_limiter.add }
      expect(rate_limiter.exceeded?).to be(true)

      sleep(0.15) # Wait for interval to expire

      expect(rate_limiter.exceeded?).to be(false)
    end

    it "correctly purges old timestamps" do
      rate_limiter = described_class.new(limit: 2, interval: 0.1)

      # Add 2 requests at the limit
      2.times { rate_limiter.add }
      expect(rate_limiter.exceeded?).to be(true)

      # Wait for them to expire
      sleep(0.15)

      # Now we should be able to add more
      rate_limiter.add
      expect(rate_limiter.exceeded?).to be(false)

      rate_limiter.add
      expect(rate_limiter.exceeded?).to be(true)
    end
  end

  describe "#add" do
    it "records a new timestamp" do
      rate_limiter = described_class.new(limit: 5, interval: 1000)

      expect(rate_limiter.exceeded?).to be(false)

      # Adding requests should change the state
      5.times { rate_limiter.add }

      expect(rate_limiter.exceeded?).to be(true)
    end

    it "purges old entries when adding new ones" do
      rate_limiter = described_class.new(limit: 2, interval: 0.1)

      # Fill up the limit
      2.times { rate_limiter.add }
      expect(rate_limiter.exceeded?).to be(true)

      # Wait for old entries to expire
      sleep(0.15)

      # Adding should purge old entries first
      rate_limiter.add
      expect(rate_limiter.exceeded?).to be(false)
    end
  end

  describe "thread safety" do
    it "handles concurrent add operations safely" do
      rate_limiter = described_class.new(limit: 100, interval: 1000)

      threads = 20.times.map do
        Thread.new do
          10.times { rate_limiter.add }
        end
      end

      expect { threads.each(&:join) }.not_to raise_error
    end

    it "handles concurrent exceeded? checks safely" do
      rate_limiter = described_class.new(limit: 50, interval: 1000)

      # Pre-fill some requests
      25.times { rate_limiter.add }

      threads = 20.times.map do
        Thread.new do
          10.times { rate_limiter.exceeded? }
        end
      end

      expect { threads.each(&:join) }.not_to raise_error
    end

    it "handles concurrent mixed operations safely" do
      rate_limiter = described_class.new(limit: 100, interval: 1000)

      threads = []

      # Threads that add requests
      10.times do
        threads << Thread.new do
          10.times { rate_limiter.add }
        end
      end

      # Threads that check if exceeded
      10.times do
        threads << Thread.new do
          10.times { rate_limiter.exceeded? }
        end
      end

      expect { threads.each(&:join) }.not_to raise_error
    end
  end

  describe "edge cases" do
    it "handles limit of 1 correctly" do
      rate_limiter = described_class.new(limit: 1, interval: 1000)

      expect(rate_limiter.exceeded?).to be(false)

      rate_limiter.add
      expect(rate_limiter.exceeded?).to be(true)
    end

    it "handles very short intervals" do
      rate_limiter = described_class.new(limit: 5, interval: 0.01) # 10ms

      5.times { rate_limiter.add }
      expect(rate_limiter.exceeded?).to be(true)

      sleep(0.02)
      expect(rate_limiter.exceeded?).to be(false)
    end

    it "handles very long intervals" do
      rate_limiter = described_class.new(limit: 2, interval: 10_000) # 10 seconds

      2.times { rate_limiter.add }
      expect(rate_limiter.exceeded?).to be(true)

      # Even after a short wait, should still be exceeded
      sleep(0.1)
      expect(rate_limiter.exceeded?).to be(true)
    end
  end
end




