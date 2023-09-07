# frozen_string_literal: true

require_relative 'lib/thread_cache/version'

Gem::Specification.new do |s|
  s.name        = 'thread_cache'
  s.version     = ThreadCache::VERSION
  s.license     = 'MIT'
  s.summary     = 'A simple thread-local cache store'
  s.homepage    = 'https://github.com/elias19r/thread_cache'
  s.author      = 'Elias Rodrigues'

  s.files = Dir[
    'lib/**/*',
    'spec/**/*',
    '.gitignore',
    '.rubocop.yml',
    'Gemfile',
    'LICENSE',
    'README.md',
    'thread_cache.gemspec'
  ]

  s.required_ruby_version = '>= 3.1.4'
  s.metadata = {
    'source_code_uri'       => "https://github.com/elias19r/thread_cache/tree/v#{ThreadCache::VERSION}",
    'rubygems_mfa_required' => 'true'
  }
end
