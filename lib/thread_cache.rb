# frozen_string_literal: true

require_relative './thread_cache/version'

# A simple thread-local cache store
#
# options:
#   namespace:  Thread attribute name to use as data store (String or Symbol)
#   expires_in: Default number of seconds to expire values (number)
#   skip_nil:   Whether or not to cache nil values by default (boolean)
class ThreadCache
  def initialize(options = {})
    @namespace  = options.fetch(:namespace,  'thread_cache')
    @expires_in = options.fetch(:expires_in, 60)
    @skip_nil   = options.fetch(:skip_nil,   false)

    data_store
  end

  def clear
    data_store.clear
  end

  def exist?(key)
    data_store.key?(key)
  end

  # Writes a key-value pair to the data store.
  #
  # NOTE: value is written as it is given, it does not duplicate nor serialize it.
  #
  # key:   (String or Symbol)
  # value: (any type)
  # options:
  #   version:    sets the value's version (any type)
  #   expires_in: overrides the default expires_in
  #   skip_nil:   overrides the default skip_nil
  def write(key, value, options = {})
    perform_write(key, value, parse_options(options))
  end

  # Reads a value from the data store using key.
  #
  # options:
  #   version: defines the version to read the value
  def read(key, options = {})
    options = parse_options(options)

    entry = data_store[key]
    value, _error = validate(key, entry, options[:version])
    value
  end

  # Fetches a value from the data store using key.
  # If a valid value is not found, it writes the value returned from the given block.
  #
  # options:
  #   force:      writes the value even when a valid value is found (boolean)
  #   version:    sets the value's version
  #   expires_in: overrides the default expires_in
  #   skip_nil:   overrides the default skip_nil
  def fetch(key, options = {}, &block)
    options = parse_options(options)

    perform_fetch(key, options, &block)
  end

  def delete(key)
    entry = data_store.delete(key)

    !entry.nil?
  end

  def write_multi(keys_and_values, options = {})
    options = parse_options_multi(keys_and_values.keys, options)

    keys_and_values.each do |key, value|
      opts = {
        version:    options[:version][key],
        expires_in: options[:expires_in][key],
        skip_nil:   options[:skip_nil][key],
      }
      perform_write(key, value, opts)
    end
  end

  def read_multi(keys, options = {})
    options = parse_options_multi(keys, options)

    entries = data_store.slice(*keys)
    keys.each_with_object({}) do |key, acc|
      value, _error = validate(key, entries[key], options[:version][key])
      acc[key] = value
    end
  end

  def fetch_multi(keys, options = {}, &block)
    options = parse_options_multi(keys, options)

    keys.each_with_object({}) do |key, acc|
      opts = {
        force:      options[:force][key],
        version:    options[:version][key],
        expires_in: options[:expires_in][key],
        skip_nil:   options[:skip_nil][key],
      }
      acc[key] = perform_fetch(key, opts, &block)
    end
  end

  def delete_multi(keys)
    keys.map { |key| delete(key) }
  end

  def delete_matched(pattern)
    data_store.keys.each_with_object([]) do |key, acc|
      if key.match?(pattern)
        delete(key)
        acc << key
      end
    end
  end

  # Validates all entries, consequently deleting the ones that have expired.
  #
  # options:
  #   version: defines the version to read the values
  def cleanup(options = {})
    options = parse_options(options)

    data_store.map.each_with_object([]) do |(key, entry), acc|
      _value, error = validate(key, entry, options[:version])
      acc << key if !error.nil?
    end
  end

  def increment(key, amount = 1, options = {})
    options = parse_options(options)

    perform_add(key, amount, options)
  end

  def decrement(key, amount = 1, options = {})
    options = parse_options(options)

    perform_add(key, -amount, options)
  end

  alias exists? exist?

  alias set       write
  alias set_multi write_multi

  alias get       read
  alias get_multi read_multi

  alias remove         delete
  alias remove_multi   delete_multi
  alias remove_matched delete_matched

  alias incr increment
  alias decr decrement

  private

  def data_store
    Thread.current[@namespace] ||= {}
  end

  def build_entry(value, version, expires_in)
    {
      value:      value,
      version:    version,
      expires_in: expires_in&.to_f,
      created_at: current_unix_time,
    }
  end

  def perform_write(key, value, options)
    return if value.nil? && options[:skip_nil]

    data_store[key] = build_entry(value, options[:version], options[:expires_in])
    value
  end

  def perform_fetch(key, options)
    if options[:force]
      perform_write(key, yield(key), options)
    else
      entry = data_store[key]
      value, error = validate(key, entry, options[:version])

      if error.nil?
        value
      else
        perform_write(key, yield(key), options)
      end
    end
  end

  def perform_add(key, amount, options = {})
    entry = data_store[key]
    value, _error = validate(key, entry, options[:version])

    perform_write(key, value.to_i + amount, options)
  end

  def validate(key, entry, version)
    if entry.nil?
      [nil, 'not found']
    elsif expired?(entry) || mismatched?(entry, version)
      delete(key)
      [nil, 'expired or mismatched']
    else
      [entry[:value], nil]
    end
  end

  def expired?(entry)
    entry[:expires_in] && entry[:created_at] + entry[:expires_in] <= current_unix_time
  end

  def mismatched?(entry, version)
    entry[:version] && version && entry[:version] != version
  end

  def current_unix_time
    Time.now.to_f
  end

  def options_defaults
    @options_defaults ||= {
      force:      nil,
      version:    nil,
      expires_in: @expires_in,
      skip_nil:   @skip_nil,
    }
  end

  def parse_options(options)
    options_defaults.each_with_object({}) do |(option_name, default_value), acc|
      acc[option_name] = options.fetch(option_name, default_value)
    end
  end

  def parse_options_multi(keys, options)
    options_defaults.each_with_object({}) do |(option_name, default_value), acc|
      option_value = options.fetch(option_name, default_value)

      acc[option_name] = option_value_for_multi(keys, option_value, default_value)
    end
  end

  def option_value_for_multi(keys, option_value, fallback_value)
    case option_value
    when Hash
      (Hash.new { fallback_value }).merge(option_value)
    when Array
      (Hash.new { fallback_value }).merge(keys.take(option_value.size).zip(option_value).to_h)
    else
      Hash.new { option_value }
    end
  end
end
