ENV["RAILS_ENV"] ||= "test"
# Never let tests accidentally spawn real agent runs (the dev container may
# have the CLI and mounted credentials); live-path tests override explicitly.
ENV["PIPELINE_RUNNER"] = "demo"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
