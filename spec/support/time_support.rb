# frozen_string_literal: true

module TimeSupport
  def freeze_time(&block)
    time = Time.now
    allow(Time).to receive(:now).and_return(time)
    block.call
    allow(Time).to receive(:now).and_call_original
  end

  def travel_to(time)
    allow(Time).to receive(:now).and_return(time)
  end
end

RSpec.configure do |config|
  config.include TimeSupport
end
