require 'spec_helper'
require 'tempfile'

describe Bosh::Blobstore::BaseClient do
  subject { described_class.new({}) }

  it_implements_base_client_interface

  describe '#create' do
    it 'should raise a NotImplemented exception' do
      expect { subject.create('contents') }.to raise_error(
        Bosh::Blobstore::NotImplemented, 'not supported by this blobstore')
    end

    it 'should raise BlobstoreError exceptions' do
      expect(subject).to receive(:create_file).and_raise(
        Bosh::Blobstore::BlobstoreError, 'Could not create object')

      expect { subject.create('contents') }.to raise_error(
        Bosh::Blobstore::BlobstoreError, 'Could not create object')
    end

    it 'should trap generic exceptions and raise a BlobstoreError exception' do
      expect(subject).to receive(:create_file).and_raise(
        Errno::ECONNRESET, 'Could not create object')

      expect { subject.create('contents') }.to raise_error(
        Bosh::Blobstore::BlobstoreError,
        /Errno::ECONNRESET: Connection reset by peer - Could not create object/,
      )
    end
  end

  describe '#get' do
    it 'allows to pass options optionally' do
      expect { subject.get('id', 'file')     }.to raise_error(Bosh::Blobstore::NotImplemented)
      expect { subject.get('id', 'file', {}) }.to raise_error(Bosh::Blobstore::NotImplemented)
    end

    it 'should raise a NotImplemented exception' do
      expect { subject.get('id', 'file') }.to raise_error(
        Bosh::Blobstore::NotImplemented, 'not supported by this blobstore')
    end

    it 'should raise BlobstoreError exceptions' do
      expect(subject).to receive(:get_file).and_raise(
        Bosh::Blobstore::BlobstoreError, 'Could not fetch object')

      expect { subject.get('id', 'file') }.to raise_error(
        Bosh::Blobstore::BlobstoreError, 'Could not fetch object')
    end

    it 'should trap generic exceptions and raise a BlobstoreError exception' do
      expect(subject).to receive(:get_file).and_raise(
        Errno::ECONNRESET, 'Could not fetch object')

      expect { subject.get('id', 'file') }.to raise_error(
        Bosh::Blobstore::BlobstoreError,
        /Errno::ECONNRESET: Connection reset by peer - Could not fetch object/,
      )
    end
  end

  describe '#delete' do
    it 'should raise a NotImplemented exception' do
      expect { subject.delete('id') }.to raise_error(
        Bosh::Blobstore::NotImplemented, 'not supported by this blobstore')
    end

    it 'should propagate unexpected exception' do
      subject.define_singleton_method(:delete_object) {|id| raise Exception.new 'fake-exception'}
      expect { subject.delete('id') }.to raise_error(
        Exception, 'fake-exception')
    end
  end

  describe '#exists?' do
    it 'should raise a NotImplemented exception' do
      expect { subject.exists?('id') }.to raise_error(
        Bosh::Blobstore::NotImplemented, 'not supported by this blobstore')
    end

    it 'should propagate unexpected exception' do
      subject.define_singleton_method(:object_exists?) {|id| raise Exception.new 'fake-exception'}
      expect { subject.exists?('id') }.to raise_error(
        Exception, 'fake-exception')
    end
  end

  context 'with logging' do
    let(:logger) { Logging::Logger.new('test-logger') }
    let(:start_time) { Time.new(2017) }
    let(:end_time) { Time.new(2018) }

    before do
      subject.define_singleton_method(:create_file) {|id, file| true}
      subject.define_singleton_method(:get_file) {|id, file| true}
      subject.define_singleton_method(:delete_object) {|id| true}
      subject.define_singleton_method(:object_exists?) {|id| true}

      allow(Bosh::Director::Config).to receive(:logger).and_return(logger)
      allow(logger).to receive(:debug)
      allow(Time).to receive(:now).twice
      allow(Time).to receive(:now).and_return(start_time, end_time)
    end

    context '#create' do
      context 'when the id is not nil' do
        it 'creates and logs messages with start time and total time' do
          # Tempfile calls Time.now so need three calls
          allow(Time).to receive(:now).exactly(3)
          allow(Time).to receive(:now).and_return(Time.new(2016),start_time, end_time)

          expect(logger).to receive(:debug).with("[blobstore] creating 'id' start: #{start_time}").ordered
          expect(subject).to receive(:create_file).ordered
          expect(logger).to receive(:debug).with("[blobstore] creating 'id' (took #{end_time - start_time})").ordered
          subject.create(File.new(Tempfile.new().path, 'r'), 'id')
        end
      end

      context 'when the id is nil' do
        it 'creates and logs messages with start time and total time' do
          expect(logger).to receive(:debug).with(/\[blobstore\] creating \'.*temp-path.*\' start: #{Regexp.escape(start_time.to_s)}/).ordered
          expect(subject).to receive(:create_file).ordered
          expect(logger).to receive(:debug).with(/\[blobstore\] creating \'.*temp-path.*\' \(took #{end_time - start_time}\)/).ordered
          subject.create('contents')
        end
      end
    end

    it 'gets and logs messages with start time and total time' do
      expect(logger).to receive(:debug).with("[blobstore] getting 'id' start: #{start_time}").ordered
      expect(logger).to receive(:debug).with("[blobstore] getting 'id' (took #{end_time - start_time})").ordered
      allow(subject).to receive(:get_file).once
      subject.get('id')
    end

    it 'deletes and logs messages with start time and total time' do
      expect(logger).to receive(:debug).with("[blobstore] deleting 'oid' start: #{start_time}").ordered
      expect(subject).to receive(:delete_object).ordered
      expect(logger).to receive(:debug).with("[blobstore] deleting 'oid' (took #{end_time - start_time})").ordered
      subject.delete('oid')
    end

    it 'checks the existence of an object and logs messages with start time and total time' do
      expect(logger).to receive(:debug).with("[blobstore] checking existence of 'oid' start: #{start_time}").ordered
      expect(subject).to receive(:object_exists?).ordered
      expect(logger).to receive(:debug).with("[blobstore] checking existence of 'oid' (took #{end_time - start_time})").ordered
      subject.exists?('oid')
    end
  end
end
