require 'spec_helper'

module Bosh::Director
  describe TaskDBWriter do
    subject(:task_db_writer) { TaskDBWriter.new(column_name, task) }
    let(:task) { Bosh::Director::Models::Task.make(:id => 42) }
    let(:column_name) { :result_output }

    describe '#write' do
      it 'records data to task in db' do
        task_db_writer.write("result")
        expect(task[:result_output]).to eq("result")
      end

      it 'adds data to existing information in record' do
        task_db_writer.write("result")
        task_db_writer.write("-result1")
        expect(task[:result_output]).to eq("result-result1")
      end
    end
  end
end
