require 'spec_helper'

module Bosh::Director
  describe DeploymentManifestResolver do
    let(:raw_manifest) do
      {
        'releases' => [
          {'name' => 'release_1', 'version' => 'v1'},
          {'name' => 'release_2', 'version' => 'v2'}
        ],
        'instance_groups' => [
          {
            'name' => 'logs',
            'jobs' => [
              {'name' => 'mysql', 'properties' => {'foo' => 'foo_value', 'bar' => {'smurf' => 'blue'}}},
              {'name' => '((job_name))'}
            ],
            'properties' => {'a' => ['123', 45, '((secret_key))']}
          }
        ],
        'properties' => {
          'global_property' => '((something))'
        }
      }
    end

    describe '#resolve_manifest' do
      context 'when config server is disabled' do
        before do
          allow(Bosh::Director::Config).to receive(:config_server_enabled).and_return(false)
        end

        it 'injects uninterpolated properties in the manifest without resolving any values' do
          actual_manifest = Bosh::Director::DeploymentManifestResolver.resolve_manifest(raw_manifest, true)
          expect(actual_manifest).to eq(
           {
             'releases' => [
               {'name' => 'release_1', 'version' => 'v1'},
               {'name' => 'release_2', 'version' => 'v2'}
             ],
             'instance_groups' => [
               {
                 'name' => 'logs',
                 'jobs' => [
                   {'name' => 'mysql',
                    'properties' => {'foo' => 'foo_value', 'bar' => {'smurf' => 'blue'}},
                    'uninterpolated_properties' => {'foo' => 'foo_value', 'bar' => {'smurf' => 'blue'}}
                   },
                   {'name' => '((job_name))'}
                 ],
                 'properties' => {'a' => ['123', 45, '((secret_key))']},
                 'uninterpolated_properties' => {'a' => ['123', 45, '((secret_key))']}
               }
             ],
             'properties' => {
               'global_property' => '((something))'
             },
             'uninterpolated_properties' => {
               'global_property' => '((something))'
             }
           }
         )
        end

        it 'works with legacy deployment manifests' do
          raw_manifest['jobs'] = raw_manifest['instance_groups']
          raw_manifest.delete('instance_groups')

          raw_manifest['jobs'][0]['templates'] = raw_manifest['jobs'][0]['jobs']
          raw_manifest['jobs'][0].delete('jobs')

          actual_manifest = Bosh::Director::DeploymentManifestResolver.resolve_manifest(raw_manifest, true)
          expect(actual_manifest).to eq(
             {
               'releases' => [
                 {'name' => 'release_1', 'version' => 'v1'},
                 {'name' => 'release_2', 'version' => 'v2'}
               ],
               'jobs' => [
                 {
                   'name' => 'logs',
                   'templates' => [
                     {'name' => 'mysql',
                      'properties' => {'foo' => 'foo_value', 'bar' => {'smurf' => 'blue'}},
                      'uninterpolated_properties' => {'foo' => 'foo_value', 'bar' => {'smurf' => 'blue'}}
                     },
                     {'name' => '((job_name))'}
                   ],
                   'properties' => {'a' => ['123', 45, '((secret_key))']},
                   'uninterpolated_properties' => {'a' => ['123', 45, '((secret_key))']}
                 }
               ],
               'properties' => {
                 'global_property' => '((something))'
               },
               'uninterpolated_properties' => {
                 'global_property' => '((something))'
               }
             }
           )
        end
      end

      context 'when config server is enabled' do
        let(:injected_manifest) do
          {
            'releases' => [
              {'name' => 'release_1', 'version' => 'v1'},
              {'name' => 'release_2', 'version' => 'v2'}
            ],
            'instance_groups' => [
              {
                'name' => 'logs',
                'jobs' => [
                  {
                    'name' => 'mysql',
                    'properties' => {'foo' => 'foo_value', 'bar' => {'smurf' => 'blue'}},
                    'uninterpolated_properties' => {'foo' => 'foo_value', 'bar' => {'smurf' => 'blue'}}
                  },
                  {
                    'name' => '((job_name))'
                  }
                ],
                'properties' =>  {'a' => ['123', 45, '((secret_key))']},
                'uninterpolated_properties' => {'a' => ['123', 45, '((secret_key))']}
              }
            ],
            'properties' => {
              'global_property' => '((something))'
            },
            'uninterpolated_properties' => {
              'global_property' => '((something))'
            }
          }
        end

        let(:resolved_manifest) do
          {
            'releases' => [
              {'name' => 'release_1', 'version' => 'v1'},
              {'name' => 'release_2', 'version' => 'v2'}
            ],
            'instance_groups' => [
              {
                'name' => 'logs',
                'jobs' => [
                  {
                    'name' => 'mysql',
                    'properties' => {'foo' => 'foo_value', 'bar' => {'smurf' => 'blue'}},
                    'uninterpolated_properties' => {'foo' => '((foo_place_holder))', 'bar' => {'smurf' => '((smurf_placeholder))'}}
                  },
                  {
                    'name' => '((job_name))'
                  }
                ],
                'properties' => {'a' => ['123', 45, 'secret']},
                'uninterpolated_properties' => {'a' => ['123', 45, '((secret_key))']}
              }
            ],
            'properties' => {
              'global_property' => 'something'
            },
            'uninterpolated_properties' => {
              'global_property' => '((something))'
            }
          }
        end

        let(:my_numeric) {Numeric.new}
        let(:ignored_subtrees) do
          ignored_subtrees = []
          ignored_subtrees << ['uninterpolated_properties']
          ignored_subtrees << ['instance_groups', Numeric.new, 'uninterpolated_properties']
          ignored_subtrees << ['instance_groups', Numeric.new, 'jobs', Numeric.new, 'uninterpolated_properties']
          ignored_subtrees << ['jobs', Numeric.new, 'uninterpolated_properties']
          ignored_subtrees << ['jobs', Numeric.new, 'templates', Numeric.new, 'uninterpolated_properties']
          ignored_subtrees
        end

        before do
          allow(Bosh::Director::Config).to receive(:config_server_enabled).and_return(true)
          allow(Numeric).to receive(:new).and_return(my_numeric)
        end

        it 'injects uninterpolated properties in the the manifest and resolve the values' do
          expect(Bosh::Director::ConfigServer::ConfigParser).to receive(:parse).with(injected_manifest, ignored_subtrees).and_return(resolved_manifest)
          actual_manifest = Bosh::Director::DeploymentManifestResolver.resolve_manifest(raw_manifest, true)

          expect(actual_manifest).to eq(resolved_manifest)
        end

        it 'injects uninterpolated properties in the the manifest but does not resolve the values' do
          expect(Bosh::Director::ConfigServer::ConfigParser).to_not receive(:parse)
          actual_manifest = Bosh::Director::DeploymentManifestResolver.resolve_manifest(raw_manifest, false)
          expect(actual_manifest).to eq(
             {
               'releases' => [
                 {'name' => 'release_1', 'version' => 'v1'},
                 {'name' => 'release_2', 'version' => 'v2'}
               ],
               'instance_groups' => [
                 {
                   'name' => 'logs',
                   'jobs' => [
                     {'name' => 'mysql',
                      'properties' => {'foo' => 'foo_value', 'bar' => {'smurf' => 'blue'}},
                      'uninterpolated_properties' => {'foo' => 'foo_value', 'bar' => {'smurf' => 'blue'}}
                     },
                     {'name' => '((job_name))'}
                   ],
                   'properties' => {'a' => ['123', 45, '((secret_key))']},
                   'uninterpolated_properties' => {'a' => ['123', 45, '((secret_key))']}
                 }
               ],
               'properties' => {
                 'global_property' => '((something))'
               },
               'uninterpolated_properties' => {
                 'global_property' => '((something))'
               }
             }
           )
        end
      end
    end
  end
end
