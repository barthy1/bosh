require 'spec_helper'

describe Bosh::Director::JobUpdater do
  subject(:job_updater) { described_class.new(deployment_plan, job, links_resolver, disk_manager) }
  let(:disk_manager) { BD::DiskManager.new(cloud, logger)}
  let(:cloud) { instance_double(Bosh::Clouds) }

  let(:ip_provider) {instance_double('Bosh::Director::DeploymentPlan::IpProvider')}
  let(:skip_drain) {instance_double('Bosh::Director::DeploymentPlan::SkipDrain')}

  let(:deployment_plan) { instance_double('Bosh::Director::DeploymentPlan::Planner', {
      ip_provider: ip_provider,
      skip_drain: skip_drain
    }) }

  let(:job) do
    instance_double('Bosh::Director::DeploymentPlan::Job', {
      name: 'job_name',
      update: update_config,
      unneeded_instances: [],
      obsolete_instance_plans: []
    })
  end

  let(:links_resolver) { instance_double('Bosh::Director::DeploymentPlan::LinksResolver') }

  let(:update_config) do
    instance_double('Bosh::Director::DeploymentPlan::UpdateConfig', {
      canaries: 1,
      max_in_flight: 1,
    })
  end

  describe 'update' do
    let(:needed_instance_plans) { [] }
    before { allow(job).to receive(:needed_instance_plans).and_return(needed_instance_plans) }
    before { allow(links_resolver).to receive(:resolve) }

    let(:update_error) { RuntimeError.new('update failed') }

    let(:instance_deleter) { instance_double('Bosh::Director::InstanceDeleter') }
    before { allow(Bosh::Director::InstanceDeleter).to receive(:new).and_return(instance_deleter) }

    context 'when job is up to date' do
      let(:needed_instance_plans) do
        instance_plan = BD::DeploymentPlan::InstancePlan.new(
          instance: instance_double(BD::DeploymentPlan::Instance),
          desired_instance: BD::DeploymentPlan::DesiredInstance.new(nil, 'started', nil),
          existing_instance: nil
        )
        allow(instance_plan).to receive(:changed?) { false }
        allow(instance_plan).to receive(:changes) { [] }
        allow(instance_plan).to receive(:persist_current_spec)
        [instance_plan]
      end

      it 'should not begin the updating job event stage' do
        job_updater.update

        check_event_log do |events|
          expect(events).to be_empty
        end
      end

      it 'persists the full spec to the database in case something that is not sent to the vm changes' do
        expect(needed_instance_plans.first).to receive(:persist_current_spec)
        job_updater.update
      end
    end

    context 'when job needs to be updated' do
      let(:canary_model) { instance_double('Bosh::Director::Models::Instance', to_s: "job_name/fake_uuid (1)") }
      let(:changed_instance_model) { instance_double('Bosh::Director::Models::Instance', to_s: "job_name/fake_uuid (2)") }
      let(:canary) { instance_double('Bosh::Director::DeploymentPlan::Instance', index: 1, model: canary_model) }
      let(:changed_instance) { instance_double('Bosh::Director::DeploymentPlan::Instance', index: 2, model: changed_instance_model) }
      let(:unchanged_instance) do
        instance_double('Bosh::Director::DeploymentPlan::Instance', index: 3)
      end
      let(:canary_plan) do
        plan = BD::DeploymentPlan::InstancePlan.new(
          instance: canary,
          desired_instance:  BD::DeploymentPlan::DesiredInstance.new(nil, 'started', nil),
          existing_instance: nil
        )
        allow(plan).to receive(:changed?) { true }
        allow(plan).to receive(:changes) { ['dns']}
        plan
      end
      let(:changed_instance_plan) do
        plan = BD::DeploymentPlan::InstancePlan.new(
          instance: changed_instance,
          desired_instance:  BD::DeploymentPlan::DesiredInstance.new(nil, 'started', nil),
          existing_instance: BD::Models::Instance.make
        )
        allow(plan).to receive(:changed?) { true }
        allow(plan).to receive(:changes) { ['network']}
        plan
      end
      let(:unchanged_instance_plan) do
        plan = BD::DeploymentPlan::InstancePlan.new(
          instance: unchanged_instance,
          desired_instance: BD::DeploymentPlan::DesiredInstance.new(nil, 'started', nil),
          existing_instance: BD::Models::Instance.make
        )
        allow(plan).to receive(:changed?) { false }
        allow(plan).to receive(:changes) { [] }
        allow(plan).to receive(:persist_current_spec)
        plan
      end

      let(:needed_instance_plans) { [canary_plan, changed_instance_plan, unchanged_instance_plan] }

      let(:canary_updater) { instance_double('Bosh::Director::InstanceUpdater') }
      let(:changed_updater) { instance_double('Bosh::Director::InstanceUpdater') }
      let(:unchanged_updater) { instance_double('Bosh::Director::InstanceUpdater') }

      before do
        allow(Bosh::Director::InstanceUpdater).to receive(:new_instance_updater)
                                                    .with(ip_provider)
                                                    .and_return(canary_updater, changed_updater, unchanged_updater)
      end

      it 'should update changed job instances with canaries' do
        expect(canary_updater).to receive(:update).with(canary_plan, canary: true)
        expect(changed_updater).to receive(:update).with(changed_instance_plan)
        expect(unchanged_updater).to_not receive(:update)

        job_updater.update

        check_event_log do |events|
          [
            updating_stage_event(index: 1, total: 2, task: 'job_name/fake_uuid (1) (canary)', state: 'started'),
            updating_stage_event(index: 1, total: 2, task: 'job_name/fake_uuid (1) (canary)', state: 'finished'),
            updating_stage_event(index: 2, total: 2, task: 'job_name/fake_uuid (2)', state: 'started'),
            updating_stage_event(index: 2, total: 2, task: 'job_name/fake_uuid (2)', state: 'finished'),
          ].each_with_index do |expected_event, index|
            expect(events[index]).to include(expected_event)
          end
        end
      end

      it 'should not continue updating changed job instances if canaries failed' do
        expect(canary_updater).to receive(:update).with(canary_plan, canary: true).and_raise(update_error)
        expect(changed_updater).to_not receive(:update)
        expect(unchanged_updater).to_not receive(:update)

        expect { job_updater.update }.to raise_error(update_error)

        check_event_log do |events|
          [
            updating_stage_event(index: 1, total: 2, task: 'job_name/fake_uuid (1) (canary)', state: 'started'),
            updating_stage_event(index: 1, total: 2, task: 'job_name/fake_uuid (1) (canary)', state: 'failed'),
          ].each_with_index do |expected_event, index|
            expect(events[index]).to include(expected_event)
          end
        end
      end

      it 'should raise an error if updating changed jobs instances failed' do
        expect(canary_updater).to receive(:update).with(canary_plan, canary: true)
        expect(changed_updater).to receive(:update).with(changed_instance_plan).and_raise(update_error)
        expect(unchanged_updater).to_not receive(:update)

        expect { job_updater.update }.to raise_error(update_error)

        check_event_log do |events|
          [
            updating_stage_event(index: 1, total: 2, task: 'job_name/fake_uuid (1) (canary)', state: 'started'),
            updating_stage_event(index: 1, total: 2, task: 'job_name/fake_uuid (1) (canary)', state: 'finished'),
            updating_stage_event(index: 2, total: 2, task: 'job_name/fake_uuid (2)', state: 'started'),
            updating_stage_event(index: 2, total: 2, task: 'job_name/fake_uuid (2)', state: 'failed'),
          ].each_with_index do |expected_event, index|
            expect(events[index]).to include(expected_event)
          end
        end
      end
    end

    context 'when the job has unneeded instances' do
      let(:instance) { instance_double('Bosh::Director::DeploymentPlan::Instance') }
      let(:instance_plan) { BD::DeploymentPlan::InstancePlan.new(existing_instance: nil, desired_instance: nil, instance: instance) }
      before { allow(job).to receive(:unneeded_instances).and_return([instance]) }
      before { allow(job).to receive(:obsolete_instance_plans).and_return([instance_plan]) }

      it 'should delete the unneeded instances' do
        allow(Bosh::Director::Config.event_log).to receive(:begin_stage).and_call_original
        expect(Bosh::Director::Config.event_log).to receive(:begin_stage).
          with('Deleting unneeded instances', 1, ['job_name'])
        expect(instance_deleter).to receive(:delete_instance_plans).
          with([instance_plan], instance_of(Bosh::Director::EventLog::Stage), { max_threads: 1 })

        job_updater.update
      end
    end

    context 'when the job has no unneeded instances' do
      before { allow(job).to receive(:unneeded_instances).and_return([]) }

      it 'should not delete instances if there are not any unneeded instances' do
        expect(instance_deleter).to_not receive(:delete_instance_plans)
        job_updater.update
      end
    end

    def updating_stage_event(options)
      {
        'stage' => 'Updating job',
        'tags' => ['job_name'],
        'index' => options[:index],
        'total' => options[:total],
        'task' => options[:task],
        'state' => options[:state]
      }
    end
  end
end
