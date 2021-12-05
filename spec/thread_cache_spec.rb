# frozen_string_literal: true

require 'spec_helper'
require 'thread_cache'

RSpec.describe ThreadCache do
  let(:current_unix_time) { 1577880000.0 }
  let(:current_time) { Time.at(current_unix_time) }

  describe '#new' do
    it 'initializes the Thread.current attribute if needed' do
      nillify_data_store(:custom_namespace)

      described_class.new({ namespace: :custom_namespace })

      expect(data_store(:custom_namespace)).not_to be_nil
      expect(data_store(:custom_namespace)).to eq({})
    end

    it 'does not initialize the Thread.current attribute if not needed' do
      empty_data_store(:custom_namespace)
      create_entry('some/key', {
        value:      'some value',
        version:    '1',
        expires_in: 180,
        created_at: current_unix_time,
      }, :custom_namespace)

      described_class.new({ namespace: :custom_namespace })

      expect(data_store(:custom_namespace)).to eq({
        'some/key' => {
          value:      'some value',
          version:    '1',
          expires_in: 180,
          created_at: current_unix_time,
        }
      })
    end
  end

  describe '#clear' do
    it 'clears all keys from the data store' do
      create_entry('key1', { value: 'value1' })
      create_entry('key2', { value: 'value2' })
      create_entry('key3', { value: 'value3' })

      described_class.new.clear

      expect(data_store).to be_empty
    end
  end

  describe '#exist?' do
    it 'returns whether or not a key exists in the data store' do
      empty_data_store
      create_entry('some/key', { value: 'some value' })

      thread_cache = described_class.new

      expect(thread_cache.exist?('some/key')).to eq(true)
      expect(thread_cache.exist?('some_nonexistent/key')).to eq(false)
    end
  end

  describe '#write' do
    around do |spec|
      travel_to(current_time, &spec)
    end

    before do
      empty_data_store
    end

    it 'adds an entry and with created_at set to the current unix time' do
      described_class.new.write('some/key', 'some value')

      entry = find_entry('some/key')

      expect(entry[:value]).to eq('some value')
      expect(entry[:created_at]).to eq(current_unix_time)
    end

    context 'when options version is not given' do
      it 'adds an entry to the data store with version nil' do
        described_class.new.write('some/key', 'some value')

        entry = find_entry('some/key')

        expect(entry[:value]).to eq('some value')
        expect(entry[:version]).to be_nil
      end
    end

    context 'when options version is given' do
      it 'adds an entry to the data store with the given options version' do
        described_class.new.write('some/key', 'some value', { version: '1' })

        entry = find_entry('some/key')

        expect(entry[:value]).to eq('some value')
        expect(entry[:version]).to eq('1')
      end
    end

    context 'when options expires_in is not given' do
      it 'adds an entry to the data store with the default expires_in' do
        described_class.new.write('some/key', 'some value')

        entry = find_entry('some/key')

        expect(entry[:value]).to eq('some value')
        expect(entry[:expires_in]).to eq(60)
      end
    end

    context 'when options expires_in is given' do
      it 'adds an entry to the data store with the given options expires_in' do
        thread_cache = described_class.new({ expires_in: 60 })
        thread_cache.write('some/key', 'some value', { expires_in: 300 })

        entry = find_entry('some/key')

        expect(entry[:value]).to eq('some value')
        expect(entry[:expires_in]).to eq(300)
      end
    end

    context 'when value is nil, and options skip_nil is not given' do
      it 'skips, and does not add an entry to the data store, when default skip_nil is true' do
        thread_cache = described_class.new({ skip_nil: true })
        thread_cache.write('some/key', nil)

        entry = find_entry('some/key')

        expect(entry).to be_nil
      end

      it 'does not skip, and adds an entry to the data store, when default skip_nil is false' do
        thread_cache = described_class.new({ skip_nil: false })
        thread_cache.write('some/key', nil)

        entry = find_entry('some/key')

        expect(entry).not_to be_nil
        expect(entry[:value]).to eq(nil)
      end
    end

    context 'when value is nil, and options skip_nil is given' do
      it 'skips, and does not add an entry to the data store, when options skip_nil is true' do
        thread_cache = described_class.new({ skip_nil: false }) # It will override this default
        thread_cache.write('some/key', nil, { skip_nil: true })

        entry = find_entry('some/key')

        expect(entry).to be_nil
      end

      it 'does not skip, and adds an entry to the data store, when options skip_nil is false' do
        thread_cache = described_class.new({ skip_nil: true }) # It will override this default
        thread_cache.write('some/key', nil, { skip_nil: false })

        entry = find_entry('some/key')

        expect(entry).not_to be_nil
        expect(entry[:value]).to eq(nil)
      end
    end
  end

  describe '#read' do
    around do |spec|
      travel_to(current_time, &spec)
    end

    before do
      empty_data_store
    end

    context 'when an entry is not found' do
      it 'returns a nil value' do
        value = described_class.new.read('some_nonexistent/key')

        expect(value).to be_nil
      end
    end

    context 'when an entry is found, but it has expired' do
      it 'returns a nil value and deletes from the data store' do
        create_entry('some/key', { value: 'some value', expires_in: -1 })

        value = described_class.new.read('some/key')

        expect(value).to be_nil
        expect(find_entry('some/key')).to be_nil
      end
    end

    context 'when an entry is found, and it has not expired, but its version mismatches' do
      it 'returns a nil value and deletes from the data store' do
        create_entry('some/key', { value: 'some value', version: '1', expires_in: 300 })

        value = described_class.new.read('some/key', version: '2')

        expect(value).to be_nil
        expect(find_entry('some/key')).to be_nil
      end
    end

    context 'when an entry is found, and it has not expired, and its version does not mismatch' do
      it 'returns the value and does not delete from the data store' do
        create_entry('some/key', { value: 'some value', version: nil, expires_in: 300 })

        value = described_class.new.read('some/key')

        expect(value).to eq('some value')
        expect(find_entry('some/key')).to eq(
          build_entry({
            value:      'some value',
            version:    nil,
            expires_in: 300,
            created_at: current_unix_time
          })
        )
      end
    end
  end

  describe '#fetch' do
    around do |spec|
      travel_to(current_time, &spec)
    end

    before do
      empty_data_store
    end

    describe 'normal fetch' do
      context 'when value is not found, or it has expired, or its version mismatched' do
        it 'writes and returns the value from the given block' do
          [
            ['other/key', {}], # not found
            ['some/key',  { value: 'some existing value', version: '1', expires_in: -1 }], # expired
            ['some/key',  { value: 'some existing value', version: '2', expires_in: 60 }], # mismatched
          ].each do |key, attributes|
            create_entry(key, attributes)

            value = described_class.new.fetch('some/key', { version: '1', expires_in: 300 }) do
              'some new value from the block'
            end

            expect(value).to eq('some new value from the block')

            expect(find_entry('some/key')).to eq(
              build_entry({
                value:     'some new value from the block',
                version:   '1',
                expires_in: 300,
                create_at:  current_unix_time
              })
            )
          end
        end

        context 'when value from the given block is nil, and default skip_nil is true' do
          it 'does not write the new nil value, and returns nil' do
            thread_cache = described_class.new({ skip_nil: true })

            options = { version: '1', expires_in: 300 }
            value = thread_cache.fetch('some/key', options) do
              nil
            end

            expect(value).to eq(nil)
            expect(find_entry('some/key')).to be_nil
          end
        end

        context 'when value from the given block is nil, and options skip_nil is true' do
          it 'does not write the new nil value, and returns nil' do
            thread_cache = described_class.new({ skip_nil: false })

            options = { version: '1', expires_in: 300, skip_nil: true }
            value = thread_cache.fetch('some/key', options) do
              nil
            end

            expect(value).to eq(nil)
            expect(find_entry('some/key')).to be_nil
          end
        end
      end

      context 'when value is found, and it has not expired, and it does not mismatch' do
        it 'does not write value from the block, and returns the existing value' do
          create_entry('some/key', { value: 'some existing value', version: '1', expires_in: 60 })

          value = described_class.new.fetch('some/key', { version: '1', expires_in: 300 }) do
            'some new value from the block'
          end

          expect(value).to eq('some existing value')

          expect(find_entry('some/key')).to eq(
            build_entry({
              value:      'some existing value',
              version:    '1',
              expires_in: 60,
              created_at: current_unix_time
            })
          )
        end
      end
    end

    describe 'forced fetch' do
      it 'writes and returns the value from the given block' do
        create_entry('some/key', { value: 'some existing value', version: '1', expires_in: 60 })

        options = { force: true, version: '1', expires_in: 300 }
        value = described_class.new.fetch('some/key', options) do
          'some new value from the block'
        end

        expect(value).to eq('some new value from the block')

        expect(find_entry('some/key')).to eq(
          build_entry({
            value:     'some new value from the block',
            version:   '1',
            expires_in: 300,
            create_at:  current_unix_time
          })
        )
      end

      context 'when value from the given block is nil, and default skip_nil is true' do
        it 'does not write the new nil value, and returns nil' do
          thread_cache = described_class.new({ skip_nil: true })

          options = { force: true, version: '1', expires_in: 300 }
          value = thread_cache.fetch('some/key', options) do
            nil
          end

          expect(value).to eq(nil)
          expect(find_entry('some/key')).to be_nil
        end
      end

      context 'when value from the given block is nil, and options skip_nil is true' do
        it 'does not write the new nil value, and returns nil' do
          thread_cache = described_class.new({ skip_nil: false })

          options = { force: true, version: '1', expires_in: 300, skip_nil: true }
          value = thread_cache.fetch('some/key', options) do
            nil
          end

          expect(value).to eq(nil)
          expect(find_entry('some/key')).to be_nil
        end
      end
    end
  end

  describe '#delete' do
    context 'when key exists' do
      it 'deletes the key from the data store and returns true' do
        create_entry('some/key', { value: 'some value' })

        result = described_class.new.delete('some/key')

        expect(result).to eq(true)
        expect(find_entry('some/key')).to be_nil
      end
    end

    context 'when key does not exist' do
      it 'returns false' do
        empty_data_store

        result = described_class.new.delete('some/key')

        expect(result).to eq(false)
      end
    end
  end

  describe '#write_multi' do
    around do |spec|
      travel_to(current_time, &spec)
    end

    before do
      empty_data_store
    end

    context 'when options values are Hashes' do
      it 'uses options values from Hashes' do
        keys_and_values = {
          'key1' => nil,
          'key2' => 'value2',
          'key3' => 'value3',
          'key4' => 'value4',
        }
        options = {
          version: {
            'key1' => nil,
            'key2' => '2',
            'key3' => '3',
          },
          expires_in: {
            'key1' =>  60,
            'key2' => 180,
            'key3' => 240,
          },
          skip_nil: {
            'key1' => true,
            'key2' => true,
            'key3' => false,
          },
        }

        result = described_class.new.write_multi(keys_and_values, options)

        expect(result).to eq(keys_and_values)

        expect(data_store).to eq(
          {
            'key2' => build_entry({
              value:      'value2',
              version:    '2',
              expires_in: 180,
              created_at: current_unix_time,
            }),
            'key3' => build_entry({
              value:      'value3',
              version:    '3',
              expires_in: 240,
              created_at: current_unix_time,
            }),
            'key4' => build_entry({
              value:      'value4',
              version:    nil,
              expires_in: 60,
              created_at: current_unix_time,
            }),
          }
        )
      end
    end

    context 'when options values are Arrays' do
      it 'uses options values from Arrays' do
        keys_and_values = {
          'key1' => nil,
          'key2' => 'value2',
          'key3' => 'value3',
          'key4' => 'value4',
        }
        options = {
          version:    [nil, '2',   '3'],
          expires_in: [60,   180,  240],
          skip_nil:   [true, true, false],
        }

        result = described_class.new.write_multi(keys_and_values, options)

        expect(result).to eq(keys_and_values)

        expect(data_store).to eq(
          {
            'key2' => build_entry({
              value:      'value2',
              version:    '2',
              expires_in: 180,
              created_at: current_unix_time,
            }),
            'key3' => build_entry({
              value:      'value3',
              version:    '3',
              expires_in: 240,
              created_at: current_unix_time,
            }),
            'key4' => build_entry({
              value:      'value4',
              version:    nil,
              expires_in: 60,
              created_at: current_unix_time,
            }),
          }
        )
      end
    end

    context 'when options values are not Hashes nor Arrays' do
      it 'uses the same options values for all keys' do
        keys_and_values = {
          'key1' => nil,
          'key2' => 'value2',
          'key3' => 'value3',
          'key4' => 'value4',
        }
        options = {
          version:    '1',
          expires_in: 180,
          skip_nil:   true,
        }

        result = described_class.new.write_multi(keys_and_values, options)

        expect(result).to eq(keys_and_values)

        expect(data_store).to eq(
          {
            'key2' => build_entry({
              value:      'value2',
              version:    '1',
              expires_in: 180,
              created_at: current_unix_time,
            }),
            'key3' => build_entry({
              value:      'value3',
              version:    '1',
              expires_in: 180,
              created_at: current_unix_time,
            }),
            'key4' => build_entry({
              value:      'value4',
              version:    '1',
              expires_in: 180,
              created_at: current_unix_time,
            }),
          }
        )
      end
    end
  end

  describe '#read_multi' do
    around do |spec|
      travel_to(current_time, &spec)
    end

    before do
      empty_data_store
    end

    context 'when options version is a Hash' do
      it 'uses versions from the Hash' do
        create_entry('key1', { value: 'value1', version: nil, expires_in: -1 }) # expired
        create_entry('key2', { value: 'value2', version: '1', expires_in: 60 })
        create_entry('key3', { value: 'value3', version: '1', expires_in: 60 }) # mismatched
        create_entry('key4', { value: 'value4', version: '2', expires_in: -1 }) # mismatched and expired
        create_entry('key5', { value: 'value5', version: '1', expires_in: 60 })
        # and 'key6' is not found

        keys = [
          'key1',
          'key2',
          'key3',
          'key4',
          'key5',
          'key6',
        ]
        options = {
          version: {
            'key1' => nil,
            'key2' => '1',
            'key3' => '2',
            'key4' => '2',
          }
        }

        result = described_class.new.read_multi(keys, options)

        expect(result).to eq({
          'key1' => nil,
          'key2' => 'value2',
          'key3' => nil,
          'key4' => nil,
          'key5' => 'value5',
          'key6' => nil,
        })
      end
    end

    context 'when options version is an Array' do
      it 'uses versions from the Array in order' do
        create_entry('key1', { value: 'value1', version: nil, expires_in: -1 }) # expired
        create_entry('key2', { value: 'value2', version: '1', expires_in: 60 })
        create_entry('key3', { value: 'value3', version: '1', expires_in: 60 }) # mismatched
        create_entry('key4', { value: 'value4', version: '2', expires_in: -1 }) # mismatched and expired
        create_entry('key5', { value: 'value5', version: '1', expires_in: 60 })
        # and 'key6' is not found

        keys = [
          'key1',
          'key2',
          'key3',
          'key4',
          'key5',
          'key6',
        ]
        options = {
          version: [nil, '1', '2', '2']
        }

        result = described_class.new.read_multi(keys, options)

        expect(result).to eq({
          'key1' => nil,
          'key2' => 'value2',
          'key3' => nil,
          'key4' => nil,
          'key5' => 'value5',
          'key6' => nil,
        })
      end
    end

    context 'when options version is not a Hash nor an Array' do
      it 'uses the same version for all keys' do
        create_entry('key1', { value: 'value1', version: nil, expires_in: -1 }) # expired
        create_entry('key2', { value: 'value2', version: '1', expires_in: 60 }) # mismatched
        create_entry('key3', { value: 'value3', version: '1', expires_in: -1 }) # mismatched and expired
        create_entry('key4', { value: 'value4', version: '2', expires_in: 60 })
        create_entry('key5', { value: 'value5', version: nil, expires_in: 60 })
        # and 'key6' is not found

        keys = [
          'key1',
          'key2',
          'key3',
          'key4',
          'key5',
          'key6',
        ]
        options = {
          version: '2'
        }

        result = described_class.new.read_multi(keys, options)

        expect(result).to eq({
          'key1' => nil,
          'key2' => nil,
          'key3' => nil,
          'key4' => 'value4',
          'key5' => 'value5',
          'key6' => nil,
        })
      end
    end
  end

  describe '#fetch_multi' do
    before do
      empty_data_store
    end

    context 'when options values are Hashes' do
      it 'uses options values from Hashes' do
        # expired
        create_entry('key1', { value: 'value1', version: nil, expires_in: -1, created_at: current_unix_time })
        # mismatched
        create_entry('key2', { value: 'value2', version: '1', expires_in: 300, created_at: current_unix_time })
        # expired and mismatched
        create_entry('key3', { value: 'value3', version: '1', expires_in: -1, created_at: current_unix_time })

        create_entry('key4', { value: 'value4', version: '2', expires_in: 300, created_at: current_unix_time })
        create_entry('key5', { value: 'value5', version: nil, expires_in: 300, created_at: current_unix_time })
        # and 'key6' is not found

        keys = [
          'key1',
          'key2',
          'key3',
          'key4',
          'key5',
          'key6',
        ]
        options = {
          version: {
            'key1' => nil,
            'key2' => '2',
            'key3' => '2',
            'key4' => '2',
          },
          expires_in: {
            'key1' =>  60,
            'key2' => 180,
            'key3' => 240,
            'key4' => 300,
          },
          skip_nil: {
            'key1' => false,
            'key2' => false,
            'key3' => true,
            'key4' => false,
          },
        }

        result = {}
        travel_to(current_time + 100) do
          result = described_class.new.fetch_multi(keys, options) do |key|
            if key == 'key3'
              nil
            else
              "new value for #{key}"
            end
          end
        end

        expect(result).to eq({
          'key1' => 'new value for key1',
          'key2' => 'new value for key2',
          'key3' => nil,
          'key4' => 'value4',
          'key5' => 'value5',
          'key6' => 'new value for key6',
        })

        expect(data_store).to eq(
          {
            'key1' => build_entry({
              value:      'new value for key1',
              version:    nil,
              expires_in: 60,
              created_at: current_unix_time + 100,
            }),
            'key2' => build_entry({
              value:      'new value for key2',
              version:    '2',
              expires_in: 180,
              created_at: current_unix_time + 100,
            }),
            # no entry for 'key3' entry
            'key4' => build_entry({
              value:      'value4',
              version:    '2',
              expires_in: 300,
              created_at: current_unix_time,
            }),
            'key5' => build_entry({
              value:      'value5',
              version:    nil,
              expires_in: 300,
              created_at: current_unix_time,
            }),
            'key6' => build_entry({
              value:      'new value for key6',
              version:    nil,
              expires_in: 60,
              created_at: current_unix_time + 100,
            }),
          }
        )
      end
    end

    context 'when options values are Arrays' do
      it 'uses options values from Arrays' do
        # expired
        create_entry('key1', { value: 'value1', version: nil, expires_in: -1, created_at: current_unix_time })
        # mismatched
        create_entry('key2', { value: 'value2', version: '1', expires_in: 300, created_at: current_unix_time })
        # expired and mismatched
        create_entry('key3', { value: 'value3', version: '1', expires_in: -1, created_at: current_unix_time })

        create_entry('key4', { value: 'value4', version: '2', expires_in: 300, created_at: current_unix_time })
        create_entry('key5', { value: 'value5', version: nil, expires_in: 300, created_at: current_unix_time })
        # and 'key6' is not found

        keys = [
          'key1',
          'key2',
          'key3',
          'key4',
          'key5',
          'key6',
        ]
        options = {
          version:    [nil,   '2',   '2',  '2'],
          expires_in: [60,    180,   240,  300],
          skip_nil:   [false, false, true, false],
        }

        result = {}
        travel_to(current_time + 100) do
          result = described_class.new.fetch_multi(keys, options) do |key|
            if key == 'key3'
              nil
            else
              "new value for #{key}"
            end
          end
        end

        expect(result).to eq({
          'key1' => 'new value for key1',
          'key2' => 'new value for key2',
          'key3' => nil,
          'key4' => 'value4',
          'key5' => 'value5',
          'key6' => 'new value for key6',
        })

        expect(data_store).to eq(
          {
            'key1' => build_entry({
              value:      'new value for key1',
              version:    nil,
              expires_in: 60,
              created_at: current_unix_time + 100,
            }),
            'key2' => build_entry({
              value:      'new value for key2',
              version:    '2',
              expires_in: 180,
              created_at: current_unix_time + 100,
            }),
            # no entry for 'key3' entry
            'key4' => build_entry({
              value:      'value4',
              version:    '2',
              expires_in: 300,
              created_at: current_unix_time,
            }),
            'key5' => build_entry({
              value:      'value5',
              version:    nil,
              expires_in: 300,
              created_at: current_unix_time,
            }),
            'key6' => build_entry({
              value:      'new value for key6',
              version:    nil,
              expires_in: 60,
              created_at: current_unix_time + 100,
            }),
          }
        )
      end
    end

    context 'when options values are not Hashes nor Arrays' do
      it 'uses the same options values for all keys' do
        # expired
        create_entry('key1', { value: 'value1', version: '2', expires_in: -1, created_at: current_unix_time })
        # mismatched
        create_entry('key2', { value: 'value2', version: '1', expires_in: 300, created_at: current_unix_time })
        # expired and mismatched
        create_entry('key3', { value: 'value3', version: '1', expires_in: -1, created_at: current_unix_time })

        create_entry('key4', { value: 'value4', version: '2', expires_in: 300, created_at: current_unix_time })
        create_entry('key5', { value: 'value5', version: nil, expires_in: 300, created_at: current_unix_time })

        # and 'key6' is not found

        keys = [
          'key1',
          'key2',
          'key3',
          'key4',
          'key5',
          'key6',
        ]
        options = {
          version:    '2',
          expires_in: 180,
          skip_nil:   true,
        }

        result = {}
        travel_to(current_time + 100) do
          result = described_class.new.fetch_multi(keys, options) do |key|
            if key == 'key3'
              nil
            else
              "new value for #{key}"
            end
          end
        end

        expect(result).to eq({
          'key1' => 'new value for key1',
          'key2' => 'new value for key2',
          'key3' => nil,
          'key4' => 'value4',
          'key5' => 'value5',
          'key6' => 'new value for key6',
        })

        expect(data_store).to eq(
          {
            'key1' => build_entry({
              value:      'new value for key1',
              version:    '2',
              expires_in: 180,
              created_at: current_unix_time + 100,
            }),
            'key2' => build_entry({
              value:      'new value for key2',
              version:    '2',
              expires_in: 180,
              created_at: current_unix_time + 100,
            }),
            # no entry for 'key3' entry
            'key4' => build_entry({
              value:      'value4',
              version:    '2',
              expires_in: 300,
              created_at: current_unix_time,
            }),
            'key5' => build_entry({
              value:      'value5',
              version:    nil,
              expires_in: 300,
              created_at: current_unix_time,
            }),
            'key6' => build_entry({
              value:      'new value for key6',
              version:    '2',
              expires_in: 180,
              created_at: current_unix_time + 100,
            }),
          }
        )
      end
    end
  end

  describe '#delete_multi' do
    it 'deletes the keys from the data store and returns an Array with true/false for each key' do
      empty_data_store

      create_entry('key1', { value: 'value1' })
      create_entry('key2', { value: 'value2' })

      result = described_class.new.delete_multi(['key1', 'some_nonexistent/key', 'key2'])

      expect(result).to eq([true, false, true])

      expect(find_entry('key1')).to be_nil
      expect(find_entry('key2')).to be_nil
    end
  end

  describe '#delete_matched' do
    it 'deletes the keys that match the given pattern and returns a list of deleted keys' do
      empty_data_store

      create_entry('key1', { value: 'value1' })
      create_entry('key2', { value: 'value2' })
      create_entry('other/key', { value: 'other value' })

      result = described_class.new.delete_matched(/key[0-9]/)

      expect(result).to eq(['key1', 'key2'])

      expect(find_entry('key1')).to be_nil
      expect(find_entry('key2')).to be_nil
      expect(find_entry('other/key')).not_to be_nil
    end
  end

  describe '#cleanup' do
    around do |spec|
      travel_to(current_time, &spec)
    end

    it 'deletes from the data store all invalid entries and returns a list of deleted keys' do
      empty_data_store

      create_entry('key1', { value: 'value1', version: nil, expires_in: 300 })
      create_entry('key2', { value: 'value2', version: '1', expires_in: 300 })
      create_entry('key3', { value: 'value3', version: '2', expires_in: -1  })
      create_entry('key4', { value: 'value4', version: '1', expires_in: -1  })
      create_entry('key5', { value: 'value5', version: '2', expires_in: 300 })

      result = described_class.new.cleanup({ version: '2' })

      expect(result).to eq(['key2', 'key3', 'key4'])

      expect(find_entry('key1')).to_not be_nil
      expect(find_entry('key2')).to be_nil
      expect(find_entry('key3')).to be_nil
      expect(find_entry('key4')).to be_nil
      expect(find_entry('key5')).to_not be_nil
    end
  end

  describe '#increment' do
    around do |spec|
      travel_to(current_time, &spec)
    end

    before do
      empty_data_store
    end

    it 'increments value by 1' do
      thread_cache = described_class.new

      thread_cache.increment('some/key')
      expect(find_entry('some/key')[:value]).to eq(1)

      thread_cache.increment('some/key')
      thread_cache.increment('some/key')
      expect(find_entry('some/key')[:value]).to eq(3)

      thread_cache.increment('some/key')
      expect(find_entry('some/key')[:value]).to eq(4)
    end

    it 'increments value by the given amount' do
      thread_cache = described_class.new

      thread_cache.increment('some/key', 2)
      expect(find_entry('some/key')[:value]).to eq(2)

      thread_cache.increment('some/key', 5)
      thread_cache.increment('some/key', -1)
      expect(find_entry('some/key')[:value]).to eq(6)

      thread_cache.increment('some/key', 2)
      expect(find_entry('some/key')[:value]).to eq(8)
    end

    it 'passes options down' do
      create_entry('some/key', { value: 5, version: '1', expires_in: 60 })

      thread_cache = described_class.new

      # matched
      thread_cache.increment('some/key', 5, { version: '1' })
      expect(find_entry('some/key')[:value]).to eq(10)

      # mismatched
      thread_cache.increment('some/key', 1, { version: '2' })
      expect(find_entry('some/key')[:value]).to eq(1)
      expect(find_entry('some/key')[:version]).to eq('2')

      # matched
      thread_cache.increment('some/key', 1, { version: '2' })
      expect(find_entry('some/key')[:value]).to eq(2)

      # mismatched
      thread_cache.increment('some/key', 1, { version: '3', expires_in: -1 })
      expect(find_entry('some/key')[:value]).to eq(1)
      expect(find_entry('some/key')[:expires_in]).to eq(-1)

      # matched, but it has expired; set default expires_in
      thread_cache.increment('some/key', 1, { version: '3' })
      expect(find_entry('some/key')[:value]).to eq(1)
      expect(find_entry('some/key')[:expires_in]).to eq(60)

      # mismatched; set expires_in
      thread_cache.increment('some/key', 1, { version: '4', expires_in: 300 })
      expect(find_entry('some/key')[:value]).to eq(1)
      expect(find_entry('some/key')[:expires_in]).to eq(300)
    end
  end

  describe '#decrement' do
    before do
      empty_data_store
    end

    it 'decrements value by 1' do
      thread_cache = described_class.new

      thread_cache.decrement('some/key')
      expect(find_entry('some/key')[:value]).to eq(-1)

      thread_cache.decrement('some/key')
      thread_cache.decrement('some/key')
      expect(find_entry('some/key')[:value]).to eq(-3)

      thread_cache.decrement('some/key')
      expect(find_entry('some/key')[:value]).to eq(-4)
    end

    it 'decrements value by the given amount' do
      thread_cache = described_class.new

      thread_cache.decrement('some/key', 2)
      expect(find_entry('some/key')[:value]).to eq(-2)

      thread_cache.decrement('some/key', -5)
      thread_cache.decrement('some/key', 1)
      expect(find_entry('some/key')[:value]).to eq(2)

      thread_cache.decrement('some/key', 2)
      expect(find_entry('some/key')[:value]).to eq(0)
    end

    it 'passes options down' do
      create_entry('some/key', { value: 10, version: '1', expires_in: 60 })

      thread_cache = described_class.new

      # matched
      thread_cache.decrement('some/key', 5, { version: '1' })
      expect(find_entry('some/key')[:value]).to eq(5)

      # mismatched
      thread_cache.decrement('some/key', 1, { version: '2' })
      expect(find_entry('some/key')[:value]).to eq(-1)
      expect(find_entry('some/key')[:version]).to eq('2')

      # matched
      thread_cache.decrement('some/key', 1, { version: '2' })
      expect(find_entry('some/key')[:value]).to eq(-2)

      # mismatched
      thread_cache.decrement('some/key', 1, { version: '3', expires_in: -1 })
      expect(find_entry('some/key')[:value]).to eq(-1)
      expect(find_entry('some/key')[:expires_in]).to eq(-1)

      # matched but it has expired; set default expires_in
      thread_cache.decrement('some/key', 1, { version: '3' })
      expect(find_entry('some/key')[:value]).to eq(-1)
      expect(find_entry('some/key')[:expires_in]).to eq(60)

      # mismatched; set expires_in
      thread_cache.decrement('some/key', 1, { version: '4', expires_in: 300 })
      expect(find_entry('some/key')[:value]).to eq(-1)
      expect(find_entry('some/key')[:expires_in]).to eq(300)
    end
  end

  describe 'reading many times' do
    context 'with a single thread' do
      it 'behaves as expected' do
        thread_cache = described_class.new

        travel_to(current_time) do
          thread_cache.write('key1', 'value1') # default_expires_in: 60
          thread_cache.write('key2', 'value2', { expires_in: 15 })

          expect(thread_cache.read('key1')).to eq('value1')
          expect(thread_cache.read('key2')).to eq('value2')
          expect(thread_cache.read('some_nonexistent/key')).to eq(nil)
        end

        travel_to(current_time + 15) do
          expect(thread_cache.read('key1')).to eq('value1')
          expect(thread_cache.read('key2')).to eq(nil) # expired
          expect(thread_cache.read('some_nonexistent/key')).to eq(nil)

          thread_cache.write('key1', 'new value1', { expires_in: 20 })
          thread_cache.write('key2', 'new value2', { expires_in: 60, version: '1' })

          expect(thread_cache.read('key1')).to eq('new value1')
        end

        travel_to(current_time + 15 + 20) do
          expect(thread_cache.read('key1')).to eq(nil) # expired
          expect(thread_cache.read('key2')).to eq('new value2')
          expect(thread_cache.read('some_nonexistent/key')).to eq(nil)

          expect(thread_cache.read('key2', { version: '2' })).to eq(nil) # mismatched
          expect(thread_cache.read('key2')).to eq(nil)
        end
      end
    end

    context 'with multiple threads' do
      around do |spec|
        freeze_time(&spec)
      end

      it 'behaves as expected, each thread with its own data store' do
        thread_cache = described_class.new
        thread_cache.write('some/key', 'some value for thread0')

        threads = []

        threads << Thread.new do
          thread_cache.write('some/key', 'some value for thread1')

          threads << Thread.new do
            thread_cache.write('some/key', 'some value for thread2')

            expect(thread_cache.read('some/key')).to eq('some value for thread2')
          end

          expect(thread_cache.read('some/key')).to eq('some value for thread1')
        end

        threads.each(&:join)

        expect(thread_cache.read('some/key')).to eq('some value for thread0')
      end
    end
  end

  # Helper methods

  def nillify_data_store(namespace = 'thread_cache')
    Thread.current[namespace] = nil
  end

  def empty_data_store(namespace = 'thread_cache')
    Thread.current[namespace] = {}
  end

  def init_data_store(namespace = 'thread_cache')
    Thread.current[namespace] ||= {}
  end

  def data_store(namespace = 'thread_cache')
    Thread.current[namespace]
  end

  def build_entry(attributes = {})
    {
      value:      attributes[:value],
      version:    attributes[:version],
      expires_in: attributes[:expires_in],
      created_at: attributes[:created_at] || Time.now.to_f,
    }
  end

  def create_entry(key, attributes = {}, thread_namespace = 'thread_cache')
    init_data_store(thread_namespace)

    data_store(thread_namespace)[key] = build_entry(attributes)
  end

  def find_entry(key, thread_namespace = 'thread_cache')
    init_data_store(thread_namespace)

    data_store(thread_namespace)[key]
  end
end
