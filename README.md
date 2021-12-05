# ThreadCache

A simple thread-local cache store

## Install

Install it from rubygems.org in your terminal:

```sh
gem install thread_cache
```

Or via `Gemfile` in your project:

```sh
source 'https://rubygems.org'

gem 'thread_cache', '~> 1.0'
```

Or build and install the gem locally:

```sh
gem build thread_cache.gemspec
gem install thread_cache-1.0.0.gem
```

Require it in your Ruby code and the `ThreadCache` class will be available:

```rb
require 'thread_cache'
```

## Tests

Run tests with:

```sh
bundle exec rspec
```

## Linter

Check your code with:

```sh
bundle exec rubocop
```
