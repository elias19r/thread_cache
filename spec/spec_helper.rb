# frozen_string_literal: true

require 'simplecov'
SimpleCov.start

require 'rspec'
require 'active_support/testing/time_helpers'
require 'pry-byebug'

RSpec.configure do |config|
  config.include ActiveSupport::Testing::TimeHelpers
end
