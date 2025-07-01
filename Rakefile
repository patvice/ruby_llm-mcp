# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

Dir.glob("lib/tasks/*.rake").each { |file| load file }

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

task default: %i[spec rubocop]
