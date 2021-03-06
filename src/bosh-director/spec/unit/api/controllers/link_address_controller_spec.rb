require 'spec_helper'
require 'rack/test'

module Bosh::Director
  module Api
    describe Controllers::LinkAddressController do
      include Rack::Test::Methods

      subject(:app) { described_class.new(config) }
      let(:config) do
        config = Config.load_hash(SpecHelper.spec_get_director_config)
        identity_provider = Support::TestIdentityProvider.new(config.get_uuid_provider)
        allow(config).to receive(:identity_provider).and_return(identity_provider)
        config
      end

      let(:deployment) { Models::Deployment.make }

      let(:external_consumer) do
        Bosh::Director::Models::Links::LinkConsumer.create(
          deployment: deployment,
          instance_group: '',
          name: 'external_consumer_1',
          type: 'external',
        )
      end

      let(:external_consumer_intent) do
        Bosh::Director::Models::Links::LinkConsumerIntent.create(
          link_consumer: external_consumer,
          original_name: 'link_name',
          type: 'link_type',
        )
      end

      let!(:link) do
        Bosh::Director::Models::Links::Link.create(
          link_consumer_intent: external_consumer_intent,
          link_content: '{"deployment_name": "dep_foo", "instance_group": "ig_bar", "default_network": "baz", "domain": "bosh"}',
          name: 'external_consumer_link',
        )
      end

      before do
        App.new(config)
      end

      context 'when the user is lacking permissions' do
        before do
          basic_authorize 'dev-team-member', 'dev-team-member'
        end

        it 'returns an "unauthorized" response' do
          get "/?link_id=#{link.id}"
          expect(last_response.status).to eq(401)
        end
      end

      context 'when the user has read permissions' do
        before do
          basic_authorize 'reader', 'reader'
        end

        context 'when the link id is not specified' do
          it 'should return a "bad request" response' do
            get '/'
            expect(last_response.status).to eq(400)
            expect(JSON.parse(last_response.body)['description']).to eq('Link id is required')
          end
        end

        context 'when link does not exist' do
          it 'should return link not found' do
            get '/?link_id=1337'
            expect(last_response.status).to eq(404)
            expect(JSON.parse(last_response.body)['description']).to eq('Could not find a link with id 1337')
          end
        end

        context 'when link exists' do
          it 'should return the address in a hash' do
            get "/?link_id=#{link.id}"
            expect(last_response.status).to eq(200)
            response = JSON.parse(last_response.body)
            expect(response).to eq('address' => 'q-s0.ig-bar.baz.dep-foo.bosh')
          end

          context 'when a single az is specified' do
            before do
              Models::LocalDnsEncodedAz.create(name: 'z1')
              Models::LocalDnsEncodedAz.create(name: 'z2')
            end

            it 'should return the address with the az information' do
              get "/?link_id=#{link.id}&azs[]=z1"
              expect(last_response.status).to eq(200)
              response = JSON.parse(last_response.body)
              expect(response).to eq('address' => 'q-a1s0.ig-bar.baz.dep-foo.bosh')
            end

            context 'when the az is specified as not an array' do
              it 'should raise an error' do
                get "/?link_id=#{link.id}&azs=z1"
                expect(last_response.status).to eq(400)
                response = JSON.parse(last_response.body)
                expect(response["description"]).to eq('`azs` param must be array type: `azs[]=`')
              end
            end
          end

          context 'when multiple azs are specified' do
            before do
              Models::LocalDnsEncodedAz.create(name: 'z1')
              Models::LocalDnsEncodedAz.create(name: 'z2')
            end

            it 'should return the address with the az information' do
              get "/?link_id=#{link.id}&azs[]=z1&azs[]=z2"
              expect(last_response.status).to eq(200)
              response = JSON.parse(last_response.body)
              expect(response).to eq('address' => 'q-a1a2s0.ig-bar.baz.dep-foo.bosh')
            end
          end

          context 'when "healthy" status is specified' do
            it 'should return the query address with the status information' do
              get "/?link_id=#{link.id}&status=healthy"
              expect(last_response.status).to eq(200)
              response = JSON.parse(last_response.body)
              expect(response).to eq('address' => 'q-s3.ig-bar.baz.dep-foo.bosh')
            end
          end

          context 'when "unhealthy" status is specified' do
            it 'should return the query address with the status information' do
              get "/?link_id=#{link.id}&status=unhealthy"
              expect(last_response.status).to eq(200)
              response = JSON.parse(last_response.body)
              expect(response).to eq('address' => 'q-s1.ig-bar.baz.dep-foo.bosh')
            end
          end

          context 'when "all" status is specified' do
            it 'should return the query address with the status information' do
              get "/?link_id=#{link.id}&status=all"
              expect(last_response.status).to eq(200)
              response = JSON.parse(last_response.body)
              expect(response).to eq('address' => 'q-s4.ig-bar.baz.dep-foo.bosh')
            end
          end

          context 'when "default" status is specified' do
            it 'should return the query address with the status information' do
              get "/?link_id=#{link.id}&status=default"
              expect(last_response.status).to eq(200)
              response = JSON.parse(last_response.body)
              expect(response).to eq('address' => 'q-s0.ig-bar.baz.dep-foo.bosh')
            end
          end

          context 'when an invalid status is specified' do
            it 'should return a 400 bad request' do
              get "/?link_id=#{link.id}&status=foobar"
              expect(last_response.status).to eq(400)
              response = JSON.parse(last_response.body)
              expect(response["description"]).to eq('status must be a one of: ["healthy", "unhealthy", "all", "default"]')
            end
          end

          context 'when an invalid status is specified (array)' do
            it 'should return a 400 bad request' do
              get "/?link_id=#{link.id}&status[]=healthy"
              expect(last_response.status).to eq(400)
              response = JSON.parse(last_response.body)
              expect(response["description"]).to eq('status must be a one of: ["healthy", "unhealthy", "all", "default"]')
            end
          end

          context 'and the link is manual' do
            let(:provider) do
              Bosh::Director::Models::Links::LinkProvider.create(
                deployment: deployment,
                instance_group: 'instance_group',
                name: 'manual_provider_name',
                type: 'manual',
                )
            end

            let(:provider_intent) do
              Models::Links::LinkProviderIntent.create(
                name: 'manual_link_name',
                link_provider: provider,
                shared: true,
                consumable: true,
                type: 'spaghetti',
                original_name: 'napolean',
                content: {}.to_json,
                )
            end

            let!(:link) do
              Bosh::Director::Models::Links::Link.create(
                link_provider_intent: provider_intent,
                link_consumer_intent: external_consumer_intent,
                link_content: link_content.to_json,
                name: 'napolean',
                )
            end

            let(:link_content) do
              {
                'address' => '192.168.1.254'
              }
            end

            it 'returns the manual link address content' do
              get "/?link_id=#{link.id}"
              expect(last_response.status).to eq(200)
              response = JSON.parse(last_response.body)
              expect(response).to eq('address' => '192.168.1.254')
            end
          end
        end
      end

      context 'when the user has admin permissions' do
        before do
          basic_authorize 'admin', 'admin'
        end

        context 'when the link id is not specified' do
          it 'should return a "bad request" response' do
            get '/'
            expect(last_response.status).to eq(400)
            expect(JSON.parse(last_response.body)['description']).to eq('Link id is required')
          end
        end

        context 'when link does not exist' do
          it 'should return link not found' do
            get '/?link_id=1337'
            expect(last_response.status).to eq(404)
            expect(JSON.parse(last_response.body)['description']).to eq('Could not find a link with id 1337')
          end
        end

        context 'when link exists' do
          it 'should return the address in a hash' do
            get "/?link_id=#{link.id}"
            expect(last_response.status).to eq(200)
            response = JSON.parse(last_response.body)
            expect(response).to eq('address' => 'q-s0.ig-bar.baz.dep-foo.bosh')
          end
        end
      end
    end
  end
end
