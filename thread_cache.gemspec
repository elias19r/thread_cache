# frozen_string_literal: true

require_relative 'lib/thread_cache/version'

Gem::Specification.new do |s|
  s.name        = 'thread_cache'
  s.version     = ThreadCache::VERSION
  s.license     = 'MIT'
  s.summary     = 'A simple thread-local cache store'
  s.homepage    = 'https://github.com/elias19r/thread_cache'
  s.author      = 'Elias Rodrigues'

  s.files      = `git ls-files`.split("\n")
  s.test_files = `git ls-files -- spec/*`.split("\n")

  s.required_ruby_version = '>= 2.5'
  s.metadata = {
    'source_code_uri'       => "https://github.com/elias19r/thread_cache/tree/v#{ThreadCache::VERSION}",
    'rubygems_mfa_required' => 'true'
  }

  s.add_development_dependency 'activesupport', '~> 6.1.4'
  s.add_development_dependency 'bundler', '~> 1.17'
  s.add_development_dependency 'pry-byebug', '~> 3.9.0'
  s.add_development_dependency 'rspec', '~> 3.10.0'
  s.add_development_dependency 'rubocop', '~> 1.23.0'
  s.add_development_dependency 'rubocop-performance', '~> 1.12.0'
  s.add_development_dependency 'simplecov', '~> 0.21.2'
end
