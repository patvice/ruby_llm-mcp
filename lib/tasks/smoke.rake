# frozen_string_literal: true

module SmokeTasks
  module_function

  def run
    requested_file = ENV["FILE"]&.strip
    files = smoke_files(requested_file)

    if files.empty?
      puts "No smoke files found in spec/smoke"
      return
    end

    failures = run_files(files)
    print_summary(files, failures)
    raise "Smoke test failures detected" if failures.any?
  end

  def smoke_files(requested_file)
    if requested_file && !requested_file.empty?
      [requested_file]
    else
      Dir.glob("spec/smoke/**/*.rb")
    end
  end

  def run_files(files)
    failures = []

    files.each do |file|
      unless File.exist?(file)
        failures << [file, "file not found"]
        next
      end

      command = file.end_with?("_spec.rb") ? "bundle exec rspec #{file}" : "bundle exec ruby #{file}"

      puts "\n==> Running smoke file: #{file}"
      puts "    #{command}"

      success = system(command)
      failures << [file, "command failed"] unless success
    end

    failures
  end

  def print_summary(files, failures)
    puts "\nSmoke run complete."
    puts "Files run: #{files.length}"
    puts "Failures: #{failures.length}"

    failures.each do |file, reason|
      puts "- #{file}: #{reason}"
    end
  end
end

namespace :smoke do
  desc "Run smoke tests in spec/smoke one-by-one (use FILE=path to run one file)"
  task(:test) { SmokeTasks.run }
end

desc "Run smoke tests (alias for smoke:test)"
task smoke: "smoke:test"
