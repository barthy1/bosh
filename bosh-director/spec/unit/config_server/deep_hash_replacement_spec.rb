require 'spec_helper'

module Bosh::Director::ConfigServer
  describe DeepHashReplacement do
    describe "#replacement_map" do

      let(:global_props) do
        {'a' => 'test', 'b' => '((bla))'}
      end

      let(:instance_groups_props) do
        {'a' => ['123', 45, '((secret_key))']}
      end

      let(:job_props) do
        {
          'a' => {
            'b' => {
              'c' => '((nuclear_launch_code))'
            }
          }
        }
      end

      let(:env) do
        {
          'a' => 'public',
          'b' => [{'f' => '((my_db_passwd))'}, ['public', '((secret2))']]
        }
      end

      let(:test_obj) do
        {
          'name' => 'test_manifest',
          'resource_pools' => [
          {
            'name' => 'rp',
            'env' => env
          }
        ],
          'instance_groups' => [
          {
            'name' => 'db',
            'jobs' => [
              {'name' => 'mysql', 'template' => 'template1', 'properties' => job_props},
              {'name' => '((job_name))', 'template' => 'template1'}
            ],
            'properties' => {'a' => ['123', 45, '((secret_key))']}
          }
        ],
          'properties' => global_props
        }
      end

      let(:replacement_list) do
        DeepHashReplacement.replacement_map(test_obj)
      end

      it 'should create map for placeholders under `global` properties' do
        replacements = replacement_list.select { |r| r['key'] == "bla" }
        expected = [{'key' => 'bla', 'path' => ['properties', 'b']}]

        expect(replacements).to eq(expected)
      end

      it 'should create map for config placeholders under `instance_groups` properties' do
        replacements = replacement_list.select { |r| r['key'] == "secret_key" }
        expected = [{'key' => 'secret_key', 'path' => ['instance_groups', 0, 'properties', 'a', 2]}]

        expect(replacements).to eq(expected)
      end

      it 'should create map for config placeholders under `jobs` properties' do
        replacements = replacement_list.select { |r| r['key'] == "nuclear_launch_code" }
        expected = [{'key' => 'nuclear_launch_code', 'path' => ['instance_groups', 0, 'jobs', 0, 'properties', 'a', 'b', 'c']}]

        expect(replacements).to eq(expected)
      end

      it 'should create map for all config placeholders under `env`' do
        replacements = replacement_list.select { |r| r['key'] == "my_db_passwd" || r['key'] == 'secret2' }
        expected = [
          {'key' => 'my_db_passwd', 'path' => ['resource_pools', 0, 'env', 'b', 0, 'f']},
          {'key' => 'secret2', 'path' => ['resource_pools', 0, 'env', 'b', 1, 1]}
        ]

        expect(replacements).to eq(expected)
      end

      it 'should create a map for any placeholders under other sections' do
        replacements = replacement_list.select { |r| r['key'] == 'job_name' }
        expected = [
          {'key' => 'job_name', 'path' => ['instance_groups', 0, 'jobs', 1, 'name']}
        ]
        expect(replacements).to eq(expected)
      end

      context 'when to_be_ignored subtrees exist' do
        let(:ignored_subtrees) {[]}
        let(:replacement_list) do
          DeepHashReplacement.replacement_map(test_obj, ignored_subtrees)
        end
        it 'should should not include ignored paths in the result' do
          ignored_subtrees = []
          ignored_subtrees << ['instance_groups', Numeric.new, 'jobs', Numeric.new, 'properties']
          ignored_subtrees << ['instance_groups', Numeric.new, 'properties']
          ignored_subtrees << ['properties']

          replacements = DeepHashReplacement.replacement_map(test_obj, ignored_subtrees)

          expected = [
            {'key'=>'my_db_passwd', 'path'=>['resource_pools', 0, 'env', 'b', 0, 'f']},
            {'key'=>'secret2', 'path'=>['resource_pools', 0, 'env', 'b', 1, 1]},
            {'key'=>'job_name', 'path'=>['instance_groups', 0, 'jobs', 1, 'name']}
          ]

          expect(replacements).to eq(expected)
        end
      end
    end
  end
end
