require 'spec_helper'

module Bosh::Director::ConfigServer
  describe EnabledClient do
    subject(:client) { EnabledClient.new(http_client, director_name, logger) }
    let(:director_name) { 'smurf_director_name' }
    let(:deployment_name) { 'deployment_name' }
    let(:deployment_attrs) { { id: 1, name: deployment_name } }
    let(:logger) { double('Logging::Logger') }
    let(:variables_set_id) { 2000 }
    let(:success_post_response) {
      generate_success_response({ "id": "some_id1" }.to_json)
    }

    let(:event_manager) {Bosh::Director::Api::EventManager.new(true)}
    let(:task_id) {42}
    let(:update_job) {instance_double(Bosh::Director::Jobs::UpdateDeployment, username: 'user', task_id: task_id, event_manager: event_manager)}

    let(:success_response) do
      result = SampleSuccessResponse.new
      result.body = '{}'
      result
    end

    def prepend_namespace(name)
      "/#{director_name}/#{deployment_name}/#{name}"
    end

    before do
      deployment_model = Bosh::Director::Models::Deployment.make(deployment_attrs)
      Bosh::Director::Models::VariableSet.make(id: variables_set_id, deployment: deployment_model)

      allow(logger).to receive(:info)
      allow(Bosh::Director::Config).to receive(:current_job).and_return(update_job)
    end

    describe '#interpolate' do
      subject { client.interpolate(manifest_hash, deployment_name, nil, interpolate_options) }
      let(:interpolate_options) do
        {
          :subtrees_to_ignore => ignored_subtrees
        }
      end
      let(:ignored_subtrees) { [] }
      let(:nil_placeholder) { {'data' => [{'name' => "#{prepend_namespace('nil_placeholder')}", 'value' => nil, 'id' => '1'}]} }
      let(:empty_placeholder) { {'data' => [{'name' => "#{prepend_namespace('empty_placeholder')}", 'value' => '', 'id' => '2'}]} }
      let(:integer_placeholder) { {'data' => [{'name' => "#{prepend_namespace('integer_placeholder')}", 'value' => 123, 'id' => '3'}]} }
      let(:instance_placeholder) { {'data' => [{'name' => "#{prepend_namespace('instance_placeholder')}", 'value' => 'test1', 'id' => '4'}]} }
      let(:job_placeholder) { {'data' => [{'name' => "#{prepend_namespace('job_placeholder')}", 'value' => 'test2', 'id' => '5'}]} }
      let(:env_placeholder) { {'data' => [{'name' => "#{prepend_namespace('env_placeholder')}", 'value' => 'test3', 'id' => '6'}]} }
      let(:cert_placeholder) { {'data' => [{'name' => "#{prepend_namespace('cert_placeholder')}", 'value' => {'ca' => 'ca_value', 'private_key' => 'abc123'}, 'id' => '7'}]} }
      let(:mock_config_store) do
        {
          prepend_namespace('nil_placeholder') => generate_success_response(nil_placeholder.to_json),
          prepend_namespace('empty_placeholder') => generate_success_response(empty_placeholder.to_json),
          prepend_namespace('integer_placeholder') => generate_success_response(integer_placeholder.to_json),
          prepend_namespace('instance_placeholder') => generate_success_response(instance_placeholder.to_json),
          prepend_namespace('job_placeholder') => generate_success_response(job_placeholder.to_json),
          prepend_namespace('env_placeholder') => generate_success_response(env_placeholder.to_json),
          prepend_namespace('cert_placeholder') => generate_success_response(cert_placeholder.to_json),
        }
      end

      let(:http_client) { double('Bosh::Director::ConfigServer::HTTPClient') }
      let(:manifest_hash) do
        {
          'name' => deployment_name,
          'properties' => {
            'name' => '((integer_placeholder))',
            'nil_allowed' => '((nil_placeholder))',
            'empty_allowed' => '((empty_placeholder))'
          },
          'instance_groups' => {
            'name' => 'bla',
            'jobs' => [
              {
                'name' => 'test_job',
                'properties' => {'job_prop' => '((job_placeholder))'}
              }
            ]
          },
          'resource_pools' => [
            {'env' => {'env_prop' => '((env_placeholder))'}}
          ],
          'cert' => '((cert_placeholder))'
        }
      end

      before do
        mock_config_store.each do |name, value|
          allow(http_client).to receive(:get).with(name).and_return(value)
        end
      end

      context 'with variable mappings' do
        let(:variable_name) { '/boo' }
        let(:variable_id) { 'cfg-svr-id' }
        let(:variable_value) { 'var_val' }
        let(:response_body_id) { {'name' => variable_name, 'value' => variable_value, 'id' => variable_id} }
        let(:response_body_name) { {'data' => [response_body_id]} }
        let(:mock_response) { generate_success_response(response_body_id.to_json) }

        context 'when variable set is manually specified' do
          let(:latest_variable_set) { 1500 }

          it 'should request by id from the specified set' do
            allow(http_client).to receive(:get_by_id).with(variable_id).and_return(mock_response)
            Bosh::Director::Models::VariableSet.make(id: latest_variable_set, deployment: Bosh::Director::Models::Deployment.find(deployment_attrs))
            Bosh::Director::Models::Variable.create(variable_set_id: variables_set_id, variable_name: variable_name, variable_id: variable_id)
            Bosh::Director::Models::Variable.create(variable_set_id: latest_variable_set, variable_name: '/not/used', variable_id: 'unused id')
            expect(http_client).to receive(:get_by_id).with("#{variable_id}").and_return(mock_response)
            expected_variable_set = Bosh::Director::Models::VariableSet.find({id: variables_set_id})
            client.interpolate({'key' => "((#{variable_name}))"}, deployment_name, expected_variable_set, interpolate_options)
          end
        end

        context 'when variable is already fetched for the current set' do
          before do
            allow(http_client).to receive(:get_by_id).with(variable_id).and_return(mock_response)
            Bosh::Director::Models::Variable.create(variable_set_id: variables_set_id, variable_name: variable_name, variable_id: variable_id)
          end

          it 'should request by id' do
            expect(http_client).to receive(:get_by_id).with("#{variable_id}").and_return(mock_response)
            client.interpolate({'key' => "((#{variable_name}))"}, deployment_name, nil, interpolate_options)
          end
        end

        context 'when variable requested is not in the current set' do
          before do
            allow(http_client).to receive(:get).with(variable_name).and_return(generate_success_response(response_body_name.to_json))
          end

          it 'should add the name to id mapping for the current set to database' do
            expect(Bosh::Director::Models::Variable[variable_name: variable_name, variable_set_id: variables_set_id]).to be_nil
            client.interpolate({'key' => "((#{variable_name}))"}, deployment_name, nil, interpolate_options)
            models = Bosh::Director::Models::Variable.all
            expect(models.length).to eq(1)
            expect(Bosh::Director::Models::Variable[variable_name: variable_name, variable_set_id: variables_set_id]).to_not be_nil
          end

          context 'but variable was added to the current set by another worker after the initial check' do
            let(:deployment_lookup){ instance_double(Bosh::Director::Api::DeploymentLookup) }
            let(:deployment_model) { instance_double(Bosh::Director::Models::Deployment) }
            let(:variable_set) { instance_double(Bosh::Director::Models::VariableSet) }
            let(:variable) { instance_double(Bosh::Director::Models::Variable) }

            before do
              allow(Bosh::Director::Api::DeploymentLookup).to receive(:new).and_return(deployment_lookup)
              allow(deployment_lookup).to receive(:by_name).and_return(deployment_model)
              allow(deployment_model).to receive(:current_variable_set).and_return(variable_set)
              allow(variable_set).to receive(:add_variable).and_raise(Sequel::UniqueConstraintViolation)
              allow(variable_set).to receive(:id)
              allow(variable).to receive(:variable_id).and_return(variable_id)
              allow(variable).to receive(:variable_name).and_return(variable_name)

              allow(Bosh::Director::Models::Variable).to receive(:[]).and_return(nil, variable)
            end

            it 'should fetch by id from database' do
              allow(http_client).to receive(:get_by_id).with(variable_id).and_return(mock_response)

              expect(http_client).to receive(:get_by_id).with(variable_id)
              client.interpolate({'key' => "((#{variable_name}))"}, deployment_name, nil, interpolate_options)
            end
          end
        end
      end

      context 'when response received from server is not in the expected format' do
        let(:manifest_hash) do
          {
            'name' => 'deployment_name',
            'properties' => {
              'name' => '((/bad))'
            }
          }
        end

        [
          {'response' => 'Invalid JSON response',
           'message' => '- Failed to fetch variable \'/bad\' from config server: Invalid JSON response'},

          {'response' => {'x' => {}},
           'message' => '- Failed to fetch variable \'/bad\' from config server: Expected data to be an array'},

          {'response' => {'data' => {'value' => 'x'}},
           'message' => '- Failed to fetch variable \'/bad\' from config server: Expected data to be an array'},

          {'response' => {'data' => []},
           'message' => '- Failed to fetch variable \'/bad\' from config server: Expected data to be non empty array'},

          {'response' => {'data' => [{'name' => 'name1', 'id' => 'id1', 'val' => 'x'}]},
           'message' => '- Failed to fetch variable \'/bad\' from config server: Expected data[0] to have key \'value\''},

          {'response' => {'data' => [{'value' => 'x'}]},
           'message' => '- Failed to fetch variable \'/bad\' from config server: Expected data[0] to have key \'id\''},
        ].each do |entry|
          it 'raises an error' do
            allow(http_client).to receive(:get).with('/bad').and_return(generate_success_response(entry['response'].to_json))
            expect {
              subject
            }.to raise_error { |error|
              expect(error).to be_a(Bosh::Director::ConfigServerFetchError)
              expect(error.message).to include(entry['message'])
            }
          end
        end
      end

      context 'when response received from server has multiple errors' do
        let(:manifest_hash) do
          {
            'name' => 'deployment_name',
            'properties' => {
              'p1' => '((/bad1))',
              'p2' => '((/bad2))',
              'p3' => '((/bad3))',
              'p4' => '((/bad4))',
              'p5' => '((/bad5))',
            }
          }
        end

        let(:mock_config_store) do
          {
            '/bad1' => generate_success_response('Invalid JSON response'),
            '/bad2' => generate_success_response({'data' => 'Not Array'}.to_json),
            '/bad3' => generate_success_response({'data' => []}.to_json),
            '/bad4' => generate_success_response({'data' => [{'name' => 'name exists', 'value' => 'value exists'}]}.to_json),
            '/bad5' => generate_success_response({'data' => [{'id' => 'id exists', 'name' => 'name exists'}]}.to_json),
          }
        end

        it 'raises an error consolidating all the problems' do
          expect {
            subject
          }.to raise_error { |error|
            expect(error).to be_a(Bosh::Director::ConfigServerFetchError)
            expect(error.message).to include("- Failed to fetch variable '/bad1' from config server: Invalid JSON response")
            expect(error.message).to include("- Failed to fetch variable '/bad2' from config server: Expected data to be an array")
            expect(error.message).to include("- Failed to fetch variable '/bad3' from config server: Expected data to be non empty array")
            expect(error.message).to include("- Failed to fetch variable '/bad4' from config server: Expected data[0] to have key 'id'")
            expect(error.message).to include("- Failed to fetch variable '/bad5' from config server: Expected data[0] to have key 'value'")
          }
        end
      end

      context 'when absolute path is required' do
        it 'should raise error when name is not absolute' do
          expect {
            client.interpolate(manifest_hash, deployment_name, nil, {subtrees_to_ignore: ignored_subtrees, must_be_absolute_name: true})
          }.to raise_error(Bosh::Director::ConfigServerIncorrectNameSyntax)
        end
      end

      it 'should return a new copy of the original manifest' do
        expect(client.interpolate(manifest_hash, deployment_name, nil, {subtrees_to_ignore: ignored_subtrees})).to_not equal(manifest_hash)
      end

      it 'replaces all placeholders it finds in the hash passed' do
        expected_result = {
          'name' => 'deployment_name',
          'properties' => {
            'name' => 123,
            'nil_allowed' => nil,
            'empty_allowed' => ''
          },
          'instance_groups' => {
            'name' => 'bla',
            'jobs' => [
              {
                'name' => 'test_job',
                'properties' => {'job_prop' => 'test2'}
              }
            ]
          },
          'resource_pools' => [
            {'env' => {'env_prop' => 'test3'}}
          ],
          'cert' => {
            'ca' => 'ca_value',
            'private_key' => 'abc123'
          }
        }

        expect(subject).to eq(expected_result)
      end

      it 'should raise a missing name error message when name is not found in the config_server' do
        allow(http_client).to receive(:get).with(prepend_namespace('missing_placeholder')).and_return(SampleNotFoundResponse.new)

        manifest_hash['properties'] = {'name' => '((missing_placeholder))'}
        expect {
          subject
        }.to raise_error { |error|
          expect(error).to be_a(Bosh::Director::ConfigServerFetchError)
          expect(error.message).to include("- Failed to find variable '#{prepend_namespace('missing_placeholder')}' from config server: HTTP code '404'")
        }
      end

      it 'should raise an unknown error when config_server returns any error other than a 404' do
        allow(http_client).to receive(:get).with(prepend_namespace('missing_placeholder')).and_return(SampleForbiddenResponse.new)

        manifest_hash['properties'] = {'name' => '((missing_placeholder))'}
        expect {
          subject
        }.to raise_error { |error|
          expect(error).to be_a(Bosh::Director::ConfigServerFetchError)
          expect(error.message).to include("- Failed to fetch variable '/smurf_director_name/deployment_name/missing_placeholder' from config server: HTTP code '403'")
        }
      end

      context 'ignored subtrees' do
        #TODO pull out config server mocks into their own lets
        let(:mock_config_store) do
          {
            prepend_namespace('release_1_placeholder') => generate_success_response({'data' => [{'name' => prepend_namespace('release_1_placeholder'), 'value' => 'release_1', 'id' => 1}]}.to_json),
            prepend_namespace('release_2_version_placeholder') => generate_success_response({'data' => [{'name' => prepend_namespace('release_2_version_placeholder'), 'value' => 'v2', 'id' => 2}]}.to_json),
            prepend_namespace('job_name') => generate_success_response({'data' => [{'name' => prepend_namespace('job_name'), 'value' => 'spring_server', 'id' => 3}]}.to_json)
          }
        end

        let(:manifest_hash) do
          {
            'releases' => [
              {'name' => '((release_1_placeholder))', 'version' => 'v1'},
              {'name' => 'release_2', 'version' => '((release_2_version_placeholder))'}
            ],
            'instance_groups' => [
              {
                'name' => 'logs',
                'env' => {'smurf' => '((smurf_placeholder))'},
                'jobs' => [
                  {
                    'name' => 'mysql',
                    'properties' => {'foo' => '((foo_place_holder))', 'bar' => {'smurf' => '((smurf_placeholder))'}}
                  },
                  {
                    'name' => '((job_name))'
                  }
                ],
                'properties' => {'a' => ['123', 45, '((secret_name))']}
              }
            ],
            'properties' => {
              'global_property' => '((something))'
            },
            'resource_pools' => [
              {
                'name' => 'resource_pool_name',
                'env' => {
                  'f' => '((f_placeholder))'
                }
              }
            ]
          }
        end

        let(:interpolated_manifest_hash) do
          {
            'releases' => [
              {'name' => 'release_1', 'version' => 'v1'},
              {'name' => 'release_2', 'version' => 'v2'}
            ],
            'instance_groups' => [
              {
                'name' => 'logs',
                'env' => {'smurf' => '((smurf_placeholder))'},
                'jobs' => [
                  {
                    'name' => 'mysql',
                    'properties' => {'foo' => '((foo_place_holder))', 'bar' => {'smurf' => '((smurf_placeholder))'}}
                  },
                  {
                    'name' => 'spring_server'
                  }
                ],
                'properties' => {'a' => ['123', 45, '((secret_name))']}
              }
            ],
            'properties' => {
              'global_property' => '((something))'
            },
            'resource_pools' => [
              {
                'name' => 'resource_pool_name',
                'env' => {
                  'f' => '((f_placeholder))'
                }
              }
            ]
          }
        end

        let(:ignored_subtrees) do
          index_type = Integer
          any_string = String

          ignored_subtrees = []
          ignored_subtrees << ['properties']
          ignored_subtrees << ['instance_groups', index_type, 'properties']
          ignored_subtrees << ['instance_groups', index_type, 'jobs', index_type, 'properties']
          ignored_subtrees << ['instance_groups', index_type, 'jobs', index_type, 'consumes', any_string, 'properties']
          ignored_subtrees << ['jobs', index_type, 'properties']
          ignored_subtrees << ['jobs', index_type, 'templates', index_type, 'properties']
          ignored_subtrees << ['jobs', index_type, 'templates', index_type, 'consumes', any_string, 'properties']
          ignored_subtrees << ['instance_groups', index_type, 'env']
          ignored_subtrees << ['jobs', index_type, 'env']
          ignored_subtrees << ['resource_pools', index_type, 'env']
          ignored_subtrees << ['name']
          ignored_subtrees
        end

        it 'should not replace values in ignored subtrees' do
          expect(subject).to eq(interpolated_manifest_hash)
        end
      end

      context 'when placeholders use dot syntax' do
        before do
          get_by_id_response = generate_success_response(nested_placeholder['data'][0].to_json)
          allow(http_client).to receive(:get_by_id).with("some_id").and_return(get_by_id_response)

        end

        let(:nested_placeholder) do
          {
            'data' => [
              {
                'id' => 'some_id',
                'name' => '/nested_placeholder',
                'value' => {'x' => {'y' => {'z' => 'gold'}}}
              }
            ]
          }
        end

        let(:mock_config_store) do
          {
            '/nested_placeholder' => generate_success_response(nested_placeholder.to_json)
          }
        end

        let(:manifest_hash) do
          {
              'nest1' => '((/nested_placeholder.x))',
              'nest2' => '((/nested_placeholder.x.y))',
              'nest3' => '((/nested_placeholder.x.y.z))'
          }
        end

        it 'should only use the first piece of the placeholder name when making requests to the config_server' do
          expect(http_client).to receive(:get).with('/nested_placeholder')
          subject
        end

        it 'should return the sub-property' do
          expected_result = {
            'nest1' => {'y' => {'z' => 'gold'}},
            'nest2' => {'z' => 'gold'},
            'nest3' => 'gold'
          }
          expect(subject).to eq(expected_result)
        end

        context 'when all parts of dot syntax are not found' do

          let(:manifest_hash) do
            {
              'name' => 'deployment_name',
              'bad_nest' => ''
            }
          end

          it 'raises an error' do
            data = [
              {'placeholder' => '((/nested_placeholder.a))',
               'message' => "- Failed to fetch variable '/nested_placeholder' from config server: Expected parent '/nested_placeholder' hash to have key 'a'"},

              {'placeholder' => '((/nested_placeholder.a.b))',
               'message' => "- Failed to fetch variable '/nested_placeholder' from config server: Expected parent '/nested_placeholder' hash to have key 'a'"},

              {'placeholder' => '((/nested_placeholder.x.y.a))',
               'message' => "- Failed to fetch variable '/nested_placeholder' from config server: Expected parent '/nested_placeholder.x.y' hash to have key 'a'"},

              {'placeholder' => '((/nested_placeholder.x.a.y))',
               'message' => "- Failed to fetch variable '/nested_placeholder' from config server: Expected parent '/nested_placeholder.x' hash to have key 'a'"},
            ]

            data.each do |entry|
              manifest_hash['bad_nest'] = entry['placeholder']
              expect {
                subject
              }.to raise_error { |error|
                expect(error).to be_a(Bosh::Director::ConfigServerFetchError)
                expect(error.message).to include(entry['message'])
              }
            end
          end
        end

        context 'when multiple errors occur because of parts of dot syntax not found' do
          let(:manifest_hash) do
            {
              'name' => 'deployment_name',
              'properties' => {
                'p1' => '((/nested_placeholder.a))',
                'p2' => '((/nested_placeholder.x.y.a))',
                'p3' => '((/nested_placeholder.x.a.y))',
              }
            }
          end

          it 'raises an error consolidating all the problems' do
            expect {
              subject
            }.to raise_error { |error|
              expect(error).to be_a(Bosh::Director::ConfigServerFetchError)
              expect(error.message).to include("- Failed to fetch variable '/nested_placeholder' from config server: Expected parent '/nested_placeholder' hash to have key 'a'")
              expect(error.message).to include("- Failed to fetch variable '/nested_placeholder' from config server: Expected parent '/nested_placeholder.x.y' hash to have key 'a'")
              expect(error.message).to include("- Failed to fetch variable '/nested_placeholder' from config server: Expected parent '/nested_placeholder.x' hash to have key 'a'")
            }
          end
        end

        context 'when bad dot syntax is used' do
          let(:manifest_hash) do
            {'bad_nest' => '((nested_placeholder..x))'}
          end

          it 'raises an error' do
            expect {
              subject
            }. to raise_error(Bosh::Director::ConfigServerIncorrectNameSyntax, "Placeholder name 'nested_placeholder..x' syntax error: Must not contain consecutive dots")
          end
        end
      end

      context 'when placeholders begin with !' do
        let(:manifest_hash) do
          {
            'name' => 'deployment_name',
            'properties' => {
              'age' => '((!integer_placeholder))'
            }
          }
        end

        it 'should strip the exclamation mark' do
          expected_result = {
            'name' => 'deployment_name',
            'properties' => {'age' => 123}
          }
          expect(subject).to eq(expected_result)
        end
      end

      context 'when some placeholders have invalid name syntax' do
        let(:manifest_hash) do
          {
            'properties' => {
              'age' => '((I am an invalid name &%^))'
            }
          }
        end

        it 'raises an error' do
          expect {
            subject
          }.to raise_error(Bosh::Director::ConfigServerIncorrectNameSyntax)
        end
      end
    end

    describe '#prepare_and_get_property' do
      let(:http_client) { double('Bosh::Director::ConfigServer::HTTPClient') }
      let(:ok_response) do
        response = SampleSuccessResponse.new
        response.body = {
          :data => [
            :id => 'whateverid',
            :name => 'whatevername',
            :value => 'hello',
          ]
        }.to_json
        response
      end

      context 'when property value provided is nil' do
        it 'returns default value' do
          expect(client.prepare_and_get_property(nil, 'my_default_value', 'some_type', deployment_name)).to eq('my_default_value')
        end
      end

      context 'when property value is NOT nil' do
        context 'when property value is NOT a full placeholder (NOT padded with brackets)' do
          it 'returns that property value' do
            expect(client.prepare_and_get_property('my_smurf', 'my_default_value', nil, deployment_name)).to eq('my_smurf')
            expect(client.prepare_and_get_property('((my_smurf', 'my_default_value', nil, deployment_name)).to eq('((my_smurf')
            expect(client.prepare_and_get_property('my_smurf))', 'my_default_value', 'whatever', deployment_name)).to eq('my_smurf))')
            expect(client.prepare_and_get_property('((my_smurf))((vroom))', 'my_default_value', 'whatever', deployment_name)).to eq('((my_smurf))((vroom))')
            expect(client.prepare_and_get_property('((my_smurf)) i am happy', 'my_default_value', 'whatever', deployment_name)).to eq('((my_smurf)) i am happy')
            expect(client.prepare_and_get_property('this is ((smurf_1)) this is ((smurf_2))', 'my_default_value', 'whatever', deployment_name)).to eq('this is ((smurf_1)) this is ((smurf_2))')
          end
        end

        context 'when property value is a FULL placeholder (padded with brackets)' do
          context 'when placeholder syntax is invalid' do
            it 'raises an error' do
              expect {
                client.prepare_and_get_property('((invalid name $%$^))', 'my_default_value', nil, deployment_name)
              }.to raise_error(Bosh::Director::ConfigServerIncorrectNameSyntax)
            end
          end

          context 'when placeholder syntax is valid' do
            let(:the_placeholder) { '((my_smurf))' }
            let(:bang_placeholder) { '((!my_smurf))' }

            context 'when config server returns an error while checking for name' do
              it 'raises an error' do
                expect(http_client).to receive(:get).with(prepend_namespace('my_smurf')).and_return(SampleForbiddenResponse.new)
                expect {
                  client.prepare_and_get_property(the_placeholder, 'my_default_value', nil, deployment_name)
                }.to raise_error(Bosh::Director::ConfigServerFetchError, "Failed to fetch variable '/smurf_director_name/deployment_name/my_smurf' from config server: HTTP code '403'")
              end
            end

            context 'when value is found in config server' do
              it 'returns that property value as is' do
                expect(http_client).to receive(:get).with(prepend_namespace('my_smurf')).and_return(ok_response)
                expect(client.prepare_and_get_property(the_placeholder, 'my_default_value', nil, deployment_name)).to eq(the_placeholder)
              end

              it 'returns that property value as is when it starts with exclamation mark' do
                expect(http_client).to receive(:get).with(prepend_namespace('my_smurf')).and_return(ok_response)
                expect(client.prepare_and_get_property(bang_placeholder, 'my_default_value', nil, deployment_name)).to eq(bang_placeholder)
              end
            end

            context 'when value is NOT found in config server' do
              before do
                expect(http_client).to receive(:get).with(prepend_namespace('my_smurf')).and_return(SampleNotFoundResponse.new)
              end

              context 'when default is defined' do
                it 'returns the default value when type is nil' do
                  expect(client.prepare_and_get_property(the_placeholder, 'my_default_value', nil, deployment_name)).to eq('my_default_value')
                end

                it 'returns the default value when type is defined' do
                  expect(client.prepare_and_get_property(the_placeholder, 'my_default_value', 'some_type', deployment_name)).to eq('my_default_value')
                end

                it 'returns the default value when type is defined and generatable' do
                  expect(client.prepare_and_get_property(the_placeholder, 'my_default_value', 'password', deployment_name)).to eq('my_default_value')
                end

                context 'when placeholder starts with exclamation mark' do
                  it 'returns the default value when type is nil' do
                    expect(client.prepare_and_get_property(bang_placeholder, 'my_default_value', nil, deployment_name)).to eq('my_default_value')
                  end

                  it 'returns the default value when type is defined' do
                    expect(client.prepare_and_get_property(bang_placeholder, 'my_default_value', 'some_type', deployment_name)).to eq('my_default_value')
                  end

                  it 'returns the default value when type is defined and generatable' do
                    expect(client.prepare_and_get_property(bang_placeholder, 'my_default_value', 'password', deployment_name)).to eq('my_default_value')
                  end
                end
              end

              context 'when default is NOT defined i.e nil' do
                let(:full_key) { prepend_namespace('my_smurf') }
                let(:default_value) { nil }
                let(:type) { 'any-type-you-like' }

                context 'when the release spec property defines a type' do
                  let(:success_response) do
                    result = SampleSuccessResponse.new
                    result.body = {'id'=>858, 'name'=>'/smurf_director_name/deployment_name/my_smurf', 'value'=>'abc'}.to_json
                    result
                  end

                  it 'generates the value, records the event, and returns the user provided placeholder' do
                    expect(http_client).to receive(:post).with({'name' => "#{full_key}", 'type' => 'any-type-you-like', 'parameters' => {}}).and_return(success_response)
                    expect(client.prepare_and_get_property(the_placeholder, default_value, type, deployment_name)).to eq(the_placeholder)
                    expect(Bosh::Director::Models::Event.count).to eq(1)

                    recorded_event = Bosh::Director::Models::Event.first
                    expect(recorded_event.user).to eq('user')
                    expect(recorded_event.action).to eq('create')
                    expect(recorded_event.object_type).to eq('variable')
                    expect(recorded_event.object_name).to eq('/smurf_director_name/deployment_name/my_smurf')
                    expect(recorded_event.task).to eq("#{task_id}")
                    expect(recorded_event.deployment).to eq(deployment_name)
                    expect(recorded_event.instance).to eq(nil)
                    expect(recorded_event.context).to eq({'id'=>858, 'name'=>'/smurf_director_name/deployment_name/my_smurf'})
                  end

                  context 'when config server throws an error while generating' do
                    before do
                      allow(http_client).to receive(:post).with({'name' => "#{full_key}", 'type' => 'any-type-you-like', 'parameters' => {}}).and_return(SampleForbiddenResponse.new)
                    end

                    it 'throws an error and record and event' do
                      expect(logger).to receive(:error)
                      expect{
                        client.prepare_and_get_property(the_placeholder, default_value, type, deployment_name)
                      }. to raise_error(
                              Bosh::Director::ConfigServerGenerationError,
                              "Config Server failed to generate value for '#{full_key}' with type 'any-type-you-like'. Error: 'There was a problem.'"
                            )

                      expect(Bosh::Director::Models::Event.count).to eq(1)

                      error_event = Bosh::Director::Models::Event.first
                      expect(error_event.user).to eq('user')
                      expect(error_event.action).to eq('create')
                      expect(error_event.object_type).to eq('variable')
                      expect(error_event.object_name).to eq('/smurf_director_name/deployment_name/my_smurf')
                      expect(error_event.task).to eq("#{task_id}")
                      expect(error_event.deployment).to eq(deployment_name)
                      expect(error_event.context).to eq({})
                      expect(error_event.error).to eq("Config Server failed to generate value for '/smurf_director_name/deployment_name/my_smurf' with type 'any-type-you-like'. Error: 'There was a problem.'")
                    end
                  end

                  it 'should save generated variable to variable_mappings table' do
                    allow(http_client).to receive(:post).and_return(success_post_response)
                    expect(Bosh::Director::Models::Variable[variable_name: prepend_namespace('my_smurf'), variable_set_id: variables_set_id]).to be_nil

                    client.prepare_and_get_property(the_placeholder, default_value, type, deployment_name)

                    saved_variable = Bosh::Director::Models::Variable[variable_name: prepend_namespace('my_smurf'), variable_set_id: variables_set_id]
                    expect(saved_variable.variable_name).to eq(prepend_namespace('my_smurf'))
                    expect(saved_variable.variable_id).to eq('some_id1')
                  end

                  context 'when placeholder starts with exclamation mark' do
                    it 'generates the value and returns the user provided placeholder' do
                      expect(http_client).to receive(:post).with({'name' => "#{full_key}", 'type' => 'any-type-you-like', 'parameters' => {}}).and_return(success_post_response)
                      expect(client.prepare_and_get_property(bang_placeholder, default_value, type, deployment_name)).to eq(bang_placeholder)
                    end
                  end

                  context 'when type is certificate' do
                    let(:full_key) { prepend_namespace('my_smurf') }
                    let(:type) { 'certificate' }
                    let(:dns_record_names) do
                      %w(*.fake-name1.network-a.simple.bosh *.fake-name1.network-b.simple.bosh)
                    end

                    let(:options) do
                      {
                        :dns_record_names => dns_record_names
                      }
                    end

                    let(:post_body) do
                      {
                        'name' => full_key,
                        'type' => 'certificate',
                        'parameters' => {
                          'common_name' => dns_record_names[0],
                          'alternative_names' => dns_record_names
                        }
                      }
                    end

                    it 'generates a certificate and returns the user provided placeholder' do
                      expect(http_client).to receive(:post).with(post_body).and_return(success_post_response)
                      expect(client.prepare_and_get_property(the_placeholder, default_value, type, deployment_name, options)).to eq(the_placeholder)
                    end

                    it 'generates a certificate and returns the user provided placeholder even with dots' do
                      dotted_placeholder = '((my_smurf.ca))'
                      expect(http_client).to receive(:post).with(post_body).and_return(success_post_response)
                      expect(client.prepare_and_get_property(dotted_placeholder, default_value, type, deployment_name, options)).to eq(dotted_placeholder)
                    end

                    it 'generates a certificate and returns the user provided placeholder even if nested' do
                      dotted_placeholder = '((my_smurf.ca.fingerprint))'
                      expect(http_client).to receive(:post).with(post_body).and_return(success_post_response)
                      expect(client.prepare_and_get_property(dotted_placeholder, default_value, type, deployment_name, options)).to eq(dotted_placeholder)
                    end

                    it 'throws an error if generation of certficate errors' do
                      expect(http_client).to receive(:post).with(post_body).and_return(SampleForbiddenResponse.new)
                      expect(logger).to receive(:error)

                      expect {
                        client.prepare_and_get_property(the_placeholder, default_value, type, deployment_name, options)
                      }.to raise_error(
                             Bosh::Director::ConfigServerGenerationError,
                             "Config Server failed to generate value for '#{full_key}' with type 'certificate'. Error: 'There was a problem.'"
                           )
                    end

                    context 'when placeholder starts with exclamation mark' do
                      it 'generates a certificate and returns the user provided placeholder' do
                        expect(http_client).to receive(:post).with(post_body).and_return(success_post_response)
                        expect(client.prepare_and_get_property(bang_placeholder, default_value, type, deployment_name, options)).to eq(bang_placeholder)
                      end
                    end
                  end
                end

                context 'when the release spec property does NOT define a type' do
                  let(:type) { nil }
                  it 'returns that the user provided value as is' do
                    expect(client.prepare_and_get_property(the_placeholder, default_value, type, deployment_name)).to eq(the_placeholder)
                  end
                end
              end
            end
          end
        end
      end
    end

    describe '#generate_values' do
      let(:http_client) { double('Bosh::Director::ConfigServer::HTTPClient') }

      context 'when given a variables object' do

        context 'when some variable names syntax are NOT correct' do
          let(:variable_specs_list) do
            [
              [{'name' => 'p*laceholder_a', 'type' => 'password'}],
              [{'name' => 'placeholder_a/', 'type' => 'password'}],
              [{'name' => '', 'type' => 'password'}],
              [{'name' => ' ', 'type' => 'password'}],
              [{'name' => '((vroom))', 'type' => 'password'}],
            ]
          end

          it 'should throw an error and log it' do
            variable_specs_list.each do |variables_spec|
              expect {
                client.generate_values(Bosh::Director::DeploymentPlan::Variables.new(variables_spec), deployment_name)
              }.to raise_error Bosh::Director::ConfigServerIncorrectNameSyntax
            end
          end

        end

        context 'when ALL variable names syntax are correct' do
          let(:variables_spec) do
            [
              {'name' => 'placeholder_a', 'type' => 'password'},
              {'name' => 'placeholder_b', 'type' => 'certificate', 'options' => {'common_name' => 'bosh.io', 'alternative_names' => ['a.bosh.io', 'b.bosh.io']}},
              {'name' => '/placeholder_c', 'type' => 'gold', 'options' => {'need' => 'luck'}}
            ]
          end

          let(:variables_obj) do
            Bosh::Director::DeploymentPlan::Variables.new(variables_spec)
          end

          it 'should generate all the variables in order' do
            expect(http_client).to receive(:post).with(
              {
                'name' => prepend_namespace('placeholder_a'),
                'type' => 'password',
                'parameters' => {}
              }
            ).ordered.and_return(
              generate_success_response(
                {
                  "id": "some_id1",
                }.to_json)
            )

            expect(http_client).to receive(:post).with(
              {
                'name' => prepend_namespace('placeholder_b'),
                'type' => 'certificate',
                'parameters' => {'common_name' => 'bosh.io', 'alternative_names' => %w(a.bosh.io b.bosh.io)}
              }
            ).ordered.and_return(
              generate_success_response(
                {
                  "id": "some_id2",
                }.to_json)
            )

            expect(http_client).to receive(:post).with(
              {
                'name' => '/placeholder_c',
                'type' => 'gold',
                'parameters' => {'need' => 'luck'}
              }
            ).ordered.and_return(
              generate_success_response(
                {
                  "id": "some_id3",
                }.to_json)
            )

            client.generate_values(variables_obj, deployment_name)
          end

          it 'should save generated variables to variable table with correct associations' do
            allow(http_client).to receive(:post).and_return(
              generate_success_response({'id': 'some_id1'}.to_json),
              generate_success_response({'id': 'some_id2'}.to_json),
              generate_success_response({'id': 'some_id3'}.to_json),
            )

            expect(Bosh::Director::Models::Variable[variable_id: 'some_id1', variable_name: prepend_namespace('placeholder_a'), variable_set_id: variables_set_id]).to be_nil
            expect(Bosh::Director::Models::Variable[variable_id: 'some_id2', variable_name: prepend_namespace('placeholder_b'), variable_set_id: variables_set_id]).to be_nil
            expect(Bosh::Director::Models::Variable[variable_id: 'some_id3', variable_name: '/placeholder_c', variable_set_id: variables_set_id]).to be_nil

            client.generate_values(variables_obj, deployment_name)

            expect(Bosh::Director::Models::Variable[variable_id: 'some_id1', variable_name: prepend_namespace('placeholder_a'), variable_set_id: variables_set_id]).to_not be_nil
            expect(Bosh::Director::Models::Variable[variable_id: 'some_id2', variable_name: prepend_namespace('placeholder_b'), variable_set_id: variables_set_id]).to_not be_nil
            expect(Bosh::Director::Models::Variable[variable_id: 'some_id3', variable_name: '/placeholder_c', variable_set_id: variables_set_id]).to_not be_nil
          end

          it 'should record events' do
            success_response_1 = SampleSuccessResponse.new
            success_response_1.body = {'id'=>1, 'name'=>'/smurf_director_name/deployment_name/placeholder_a', 'value'=>'abc'}.to_json

            success_response_2 = SampleSuccessResponse.new
            success_response_2.body = {'id'=>2, 'name'=>'/smurf_director_name/deployment_name/placeholder_b', 'value'=>'my_cert_value'}.to_json

            success_response_3 = SampleSuccessResponse.new
            success_response_3.body = {'id'=>3, 'name'=>'/placeholder_c', 'value'=>'value_3'}.to_json

            expect(http_client).to receive(:post).with(
              {
                'name' => prepend_namespace('placeholder_a'),
                'type' => 'password',
                'parameters' => {}
              }
            ).ordered.and_return(success_response_1)

            expect(http_client).to receive(:post).with(
              {
                'name' => prepend_namespace('placeholder_b'),
                'type' => 'certificate',
                'parameters' => {'common_name' => 'bosh.io', 'alternative_names' => %w(a.bosh.io b.bosh.io)}
              }
            ).ordered.and_return(success_response_2)

            expect(http_client).to receive(:post).with(
              {
                'name' => '/placeholder_c',
                'type' => 'gold',
                'parameters' => { 'need' => 'luck' }
              }
            ).ordered.and_return(success_response_3)

            expect {
              client.generate_values(variables_obj, deployment_name)
            }.to change { Bosh::Director::Models::Event.count }.from(0).to(3)

            event_1 = Bosh::Director::Models::Event.first
            expect(event_1.user).to eq('user')
            expect(event_1.action).to eq('create')
            expect(event_1.object_type).to eq('variable')
            expect(event_1.object_name).to eq('/smurf_director_name/deployment_name/placeholder_a')
            expect(event_1.task).to eq("#{task_id}")
            expect(event_1.deployment).to eq(deployment_name)
            expect(event_1.instance).to eq(nil)
            expect(event_1.context).to eq({'id'=>1,'name'=>'/smurf_director_name/deployment_name/placeholder_a'})

            event_2 = Bosh::Director::Models::Event.order(:id)[2]
            expect(event_2.user).to eq('user')
            expect(event_2.action).to eq('create')
            expect(event_2.object_type).to eq('variable')
            expect(event_2.object_name).to eq('/smurf_director_name/deployment_name/placeholder_b')
            expect(event_2.task).to eq("#{task_id}")
            expect(event_2.deployment).to eq(deployment_name)
            expect(event_2.instance).to eq(nil)
            expect(event_2.context).to eq({'id'=>2,'name'=>'/smurf_director_name/deployment_name/placeholder_b'})

            event_3 = Bosh::Director::Models::Event.order(:id)[3]
            expect(event_3.user).to eq('user')
            expect(event_3.action).to eq('create')
            expect(event_3.object_type).to eq('variable')
            expect(event_3.object_name).to eq('/placeholder_c')
            expect(event_3.task).to eq("#{task_id}")
            expect(event_3.deployment).to eq(deployment_name)
            expect(event_3.instance).to eq(nil)
            expect(event_3.context).to eq({'id'=>3,'name'=>'/placeholder_c'})
          end

          context 'when variable options contains a ca key' do

            context 'when variable type is certificate & ca is relative' do
              let(:variables_spec) do
                [
                    {'name' => 'placeholder_b', 'type' => 'certificate', 'options' => {'ca' => 'my_ca', 'common_name' => 'bosh.io', 'alternative_names' => ['a.bosh.io', 'b.bosh.io']}},
                ]
              end

              let(:variables_obj) do
                Bosh::Director::DeploymentPlan::Variables.new(variables_spec)
              end

              it 'namespaces the ca reference for a variable with type certificate' do
                expect(http_client).to receive(:post).with(
                    {
                        'name' => prepend_namespace('placeholder_b'),
                        'type' => 'certificate',
                        'parameters' => {'ca' => prepend_namespace('my_ca'), 'common_name' => 'bosh.io', 'alternative_names' => %w(a.bosh.io b.bosh.io)}
                    }
                ).ordered.and_return(
                    generate_success_response(
                        {
                            "id": "some_id2",
                        }.to_json))

                client.generate_values(variables_obj, deployment_name)
              end

            end

            context 'when variable type is certificate & ca is absolute' do
              let(:variables_spec) do
                [
                    {'name' => 'placeholder_b', 'type' => 'certificate', 'options' => {'ca' => '/my_ca', 'common_name' => 'bosh.io', 'alternative_names' => ['a.bosh.io', 'b.bosh.io']}},
                ]
              end

              let(:variables_obj) do
                Bosh::Director::DeploymentPlan::Variables.new(variables_spec)
              end

              it 'namespaces the ca reference for a variable with type certificate' do
                expect(http_client).to receive(:post).with(
                    {
                        'name' => prepend_namespace('placeholder_b'),
                        'type' => 'certificate',
                        'parameters' => {'ca' => ('/my_ca'), 'common_name' => 'bosh.io', 'alternative_names' => %w(a.bosh.io b.bosh.io)}
                    }
                ).ordered.and_return(
                    generate_success_response(
                        {
                            "id": "some_id2",
                        }.to_json))

                client.generate_values(variables_obj, deployment_name)
              end

            end

            context 'when variable type is NOT certificate' do
              let(:variables_spec) do
                [
                    {'name' => 'placeholder_a', 'type' => 'something-else','options' => {'ca' => 'some_ca_value'}},
                ]
              end

              let(:variables_obj) do
                Bosh::Director::DeploymentPlan::Variables.new(variables_spec)
              end

              it 'it passes options through to config server without modification' do
                expect(http_client).to receive(:post).with(
                    {
                        'name' => prepend_namespace('placeholder_a'),
                        'type' => 'something-else',
                        'parameters' => {'ca' => 'some_ca_value'}
                    }
                ).ordered.and_return(
                    generate_success_response(
                        {
                            "id": "some_id1",
                        }.to_json))

                client.generate_values(variables_obj, deployment_name)
              end
            end


          end
          context 'when config server throws an error while generating' do
            before do
              allow(http_client).to receive(:post).with(
                {
                  'name' => prepend_namespace('placeholder_a'),
                  'type' => 'password',
                  'parameters' => {}
                }
              ).ordered.and_return(SampleForbiddenResponse.new)
            end

            it 'should throw an error, log it, and record event' do
              expect(logger).to receive(:error)

              expect {
                client.generate_values(variables_obj, deployment_name)
              }.to raise_error(
                     Bosh::Director::ConfigServerGenerationError,
                     "Config Server failed to generate value for '/smurf_director_name/deployment_name/placeholder_a' with type 'password'. Error: 'There was a problem.'"
                   )

              expect(Bosh::Director::Models::Event.count).to eq(1)

              error_event = Bosh::Director::Models::Event.first
              expect(error_event.user).to eq('user')
              expect(error_event.action).to eq('create')
              expect(error_event.object_type).to eq('variable')
              expect(error_event.object_name).to eq('/smurf_director_name/deployment_name/placeholder_a')
              expect(error_event.task).to eq("#{task_id}")
              expect(error_event.deployment).to eq(deployment_name)
              expect(error_event.instance).to eq(nil)
              expect(error_event.error).to eq("Config Server failed to generate value for '/smurf_director_name/deployment_name/placeholder_a' with type 'password'. Error: 'There was a problem.'")
            end
          end

          context 'when config server response is NOT in JSON format' do
            before do
              response = SampleSuccessResponse.new
              response.body = 'NOT JSON!!!'

              allow(http_client).to receive(:post).and_return(response)
            end

            it 'should throw an error and log it' do
              expect(logger).to_not receive(:error)

              expect{
                client.generate_values(variables_obj, deployment_name)
              }.to raise_error(
                     Bosh::Director::ConfigServerGenerationError,
                     "Config Server returned a NON-JSON body while generating value for '/smurf_director_name/deployment_name/placeholder_a' with type 'password'"
                   )
            end
          end
        end
      end
    end

    def generate_success_response(body)
      result = SampleSuccessResponse.new
      result.body = body
      result
    end
  end

  describe DisabledClient do
    subject(:disabled_client) { DisabledClient.new }
    let(:deployment_name) { 'smurf_deployment' }

    it 'responds to all methods of EnabledClient and vice versa' do
      expect(EnabledClient.instance_methods - DisabledClient.instance_methods).to be_empty
      expect(DisabledClient.instance_methods - EnabledClient.instance_methods).to be_empty
    end

    it 'has the same arity as EnabledClient methods' do
      EnabledClient.instance_methods.each do |method_name|
        expect(EnabledClient.instance_method(method_name).arity).to eq(DisabledClient.instance_method(method_name).arity)
      end
    end

    describe '#interpolate' do
      let(:src) do
        {
          'test' => 'smurf',
          'test2' => '((placeholder))'
        }
      end

      it 'returns src as is' do
        expect(disabled_client.interpolate(src, deployment_name, nil)).to eq(src)
      end
    end

    describe '#prepare_and_get_property' do
      it 'returns manifest property value if defined' do
        expect(disabled_client.prepare_and_get_property('provided prop', 'default value is here', nil, deployment_name)).to eq('provided prop')
        expect(disabled_client.prepare_and_get_property('provided prop', 'default value is here', nil, deployment_name, {})).to eq('provided prop')
        expect(disabled_client.prepare_and_get_property('provided prop', 'default value is here', nil, deployment_name, {'whatever' => 'hello'})).to eq('provided prop')
      end
      it 'returns default value when manifest value is nil' do
        expect(disabled_client.prepare_and_get_property(nil, 'default value is here', nil, deployment_name)).to eq('default value is here')
        expect(disabled_client.prepare_and_get_property(nil, 'default value is here', nil, deployment_name, {})).to eq('default value is here')
        expect(disabled_client.prepare_and_get_property(nil, 'default value is here', nil, deployment_name, {'whatever' => 'hello'})).to eq('default value is here')
      end
    end

    describe '#generate_values' do
      it 'exists' do
        expect { disabled_client.generate_values(anything, anything) }.to_not raise_error
      end
    end
  end

  class SampleSuccessResponse < Net::HTTPOK
    attr_accessor :body

    def initialize
      super(nil, '200', nil)
    end
  end

  class SampleNotFoundResponse < Net::HTTPNotFound
    def initialize
      super(nil, '404', 'Not Found Brah')
    end
  end

  class SampleForbiddenResponse < Net::HTTPForbidden
    def initialize
      super(nil, '403', 'There was a problem.')
    end
  end
end
