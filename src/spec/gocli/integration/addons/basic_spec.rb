require 'spec_helper'

describe 'basic functionality', type: :integration do
  with_reset_sandbox_before_each

  context 'in runtime configs' do
    it 'allows addons to be added to specific deployments' do
      runtime_config = Bosh::Spec::Deployments.runtime_config_with_addon_includes
      runtime_config['addons'][0]['include'] = { 'jobs' => [
        { 'name' => 'foobar', 'release' => 'bosh-release' },
      ] }
      runtime_config['addons'][0]['exclude'] = { 'deployments' => ['dep2'] }

      runtime_config_file = yaml_file('runtime_config.yml', runtime_config)
      expect(bosh_runner.run("update-runtime-config #{runtime_config_file.path}")).to include('Succeeded')

      bosh_runner.run("upload-release #{spec_asset('bosh-release-0+dev.1.tgz')}")
      bosh_runner.run("upload-release #{spec_asset('dummy2-release.tgz')}")

      upload_stemcell
      upload_cloud_config(cloud_config_hash: Bosh::Spec::NewDeployments.simple_cloud_config)

      manifest_hash = Bosh::Spec::NewDeployments.simple_manifest_with_instance_groups

      # deploy Deployment1
      manifest_hash['name'] = 'dep1'
      deploy_simple_manifest(manifest_hash: manifest_hash)

      foobar_instance = director.instance('foobar', '0', deployment_name: 'dep1')

      expect(File.exist?(foobar_instance.job_path('dummy_with_properties'))).to eq(true)
      template = foobar_instance.read_job_template('dummy_with_properties', 'bin/dummy_with_properties_ctl')
      expect(template).to include("echo 'prop_value'")

      # deploy Deployment2
      manifest_hash['name'] = 'dep2'
      deploy_simple_manifest(manifest_hash: manifest_hash)

      foobar_instance = director.instance('foobar', '0', deployment_name: 'dep2')

      expect(File.exist?(foobar_instance.job_path('dummy_with_properties'))).to eq(false)

      expect(File.exist?(foobar_instance.job_path('foobar'))).to eq(true)
    end

    it 'allows addons to be added to specific deployments listed in includes section' do
      runtime_config = Bosh::Spec::Deployments.runtime_config_with_addon_includes_section

      runtime_config_file = yaml_file('runtime_config.yml', runtime_config)
      expect(bosh_runner.run("update-runtime-config #{runtime_config_file.path}")).to include('Succeeded')

      bosh_runner.run("upload-release #{spec_asset('bosh-release-0+dev.1.tgz')}")
      bosh_runner.run("upload-release #{spec_asset('dummy2-release.tgz')}")

      upload_stemcell
      upload_cloud_config(cloud_config_hash: Bosh::Spec::NewDeployments.simple_cloud_config)

      manifest_hash = Bosh::Spec::NewDeployments.simple_manifest_with_instance_groups

      manifest_hash['instance_groups'][1] =
        Bosh::Spec::NewDeployments.simple_instance_group(
          name: 'foobar_without_packages',
          jobs: [{ 'name' => 'foobar_without_packages', 'release' => 'bosh-release' }],
          instances: 1,
        )

      # deploy Deployment1
      manifest_hash['name'] = 'dep1'
      deploy_simple_manifest(manifest_hash: manifest_hash)

      foobar_instance = director.instance('foobar', '0', deployment_name: 'dep1')
      expect(File.exist?(foobar_instance.job_path('foobar'))).to eq(true)
      expect(File.exist?(foobar_instance.job_path('dummy_with_properties'))).to eq(true)
      template = foobar_instance.read_job_template('dummy_with_properties', 'bin/dummy_with_properties_ctl')
      expect(template).to include("echo 'prop_value'")

      foobar_without_packages_instance = director.instance('foobar_without_packages', '0', deployment_name: 'dep1')
      expect(File.exist?(foobar_without_packages_instance.job_path('dummy_with_properties'))).to eq(false)
      expect(File.exist?(foobar_without_packages_instance.job_path('foobar_without_packages'))).to eq(true)

      # deploy Deployment2
      manifest_hash['name'] = 'dep2'
      deploy_simple_manifest(manifest_hash: manifest_hash)

      foobar_instance = director.instance('foobar', '0', deployment_name: 'dep2')
      expect(File.exist?(foobar_instance.job_path('dummy_with_properties'))).to eq(true)
      expect(File.exist?(foobar_instance.job_path('foobar'))).to eq(true)
      template = foobar_instance.read_job_template('dummy_with_properties', 'bin/dummy_with_properties_ctl')
      expect(template).to include("echo 'prop_value'")

      foobar_without_packages_instance = director.instance('foobar_without_packages', '0', deployment_name: 'dep2')
      expect(File.exist?(foobar_without_packages_instance.job_path('dummy_with_properties'))).to eq(true)
      expect(File.exist?(foobar_without_packages_instance.job_path('foobar_without_packages'))).to eq(true)
      template = foobar_without_packages_instance.read_job_template('dummy_with_properties', 'bin/dummy_with_properties_ctl')
      expect(template).to include("echo 'prop_value'")
    end

    it 'allows addons to be added to specific deployments not listed in excludes section' do
      runtime_config = Bosh::Spec::Deployments.runtime_config_with_addon_excludes_section

      runtime_config_file = yaml_file('runtime_config.yml', runtime_config)
      expect(bosh_runner.run("update-runtime-config #{runtime_config_file.path}")).to include('Succeeded')

      bosh_runner.run("upload-release #{spec_asset('bosh-release-0+dev.1.tgz')}")
      bosh_runner.run("upload-release #{spec_asset('dummy2-release.tgz')}")

      upload_stemcell
      upload_cloud_config(cloud_config_hash: Bosh::Spec::NewDeployments.simple_cloud_config)

      manifest_hash = Bosh::Spec::NewDeployments.simple_manifest_with_instance_groups

      manifest_hash['instance_groups'][1] =
        Bosh::Spec::NewDeployments.simple_instance_group(
          name: 'foobar_without_packages',
          jobs: [{ 'name' => 'foobar_without_packages', 'release' => 'bosh-release' }],
          instances: 1,
        )

      # deploy Deployment1
      manifest_hash['name'] = 'dep1'
      deploy_simple_manifest(manifest_hash: manifest_hash)

      foobar_instance = director.instance('foobar', '0', deployment_name: 'dep1')
      expect(File.exist?(foobar_instance.job_path('foobar'))).to eq(true)
      expect(File.exist?(foobar_instance.job_path('dummy_with_properties'))).to eq(false)

      foobar_without_packages_instance = director.instance('foobar_without_packages', '0', deployment_name: 'dep1')
      expect(File.exist?(foobar_without_packages_instance.job_path('dummy_with_properties'))).to eq(true)
      expect(File.exist?(foobar_without_packages_instance.job_path('foobar_without_packages'))).to eq(true)
      template = foobar_without_packages_instance.read_job_template('dummy_with_properties', 'bin/dummy_with_properties_ctl')
      expect(template).to include("echo 'prop_value'")

      # deploy Deployment2
      manifest_hash['name'] = 'dep2'
      deploy_simple_manifest(manifest_hash: manifest_hash)

      foobar_instance = director.instance('foobar', '0', deployment_name: 'dep2')
      expect(File.exist?(foobar_instance.job_path('dummy_with_properties'))).to eq(false)
      expect(File.exist?(foobar_instance.job_path('foobar'))).to eq(true)

      foobar_without_packages_instance = director.instance('foobar_without_packages', '0', deployment_name: 'dep2')
      expect(File.exist?(foobar_without_packages_instance.job_path('dummy_with_properties'))).to eq(false)
      expect(File.exist?(foobar_without_packages_instance.job_path('foobar_without_packages'))).to eq(true)
    end

    it 'allows addons to be added for specific stemcell operating systems' do
      runtime_config_file = yaml_file(
        'runtime_config.yml',
        Bosh::Spec::Deployments.runtime_config_with_addon_includes_stemcell_os,
      )
      expect(bosh_runner.run("update-runtime-config #{runtime_config_file.path}")).to include('Succeeded')

      bosh_runner.run("upload-release #{spec_asset('bosh-release-0+dev.1.tgz')}")
      bosh_runner.run("upload-release #{spec_asset('dummy2-release.tgz')}")

      upload_stemcell # name: ubuntu-stemcell, os: toronto-os
      upload_stemcell_2 # name: centos-stemcell, os: toronto-centos

      manifest_hash = Bosh::Spec::NewDeployments.stemcell_os_specific_addon_manifest
      manifest_hash['stemcells'] = [
        {
          'alias' => 'toronto',
          'os' => 'toronto-os',
          'version' => 'latest',
        },
        {
          'alias' => 'centos',
          'os' => 'toronto-centos',
          'version' => 'latest',
        },
      ]

      cloud_config_hash = Bosh::Spec::NewDeployments.simple_cloud_config
      cloud_config_hash['vm_types'] = [
        { 'name' => 'a', 'cloud_properties' => {} },
        { 'name' => 'b', 'cloud_properties' => {} },
      ]
      upload_cloud_config(cloud_config_hash: cloud_config_hash)

      deploy_simple_manifest(manifest_hash: manifest_hash)

      instances = director.instances

      addon_instance = instances.detect { |instance| instance.instance_group_name == 'has-addon-vm' }
      expect(File.exist?(addon_instance.job_path('foobar'))).to eq(true)
      expect(File.exist?(addon_instance.job_path('dummy'))).to eq(true)

      no_addon_instance = instances.detect { |instance| instance.instance_group_name == 'no-addon-vm' }
      expect(File.exist?(no_addon_instance.job_path('foobar'))).to eq(true)
      expect(File.exist?(no_addon_instance.job_path('dummy'))).to eq(false)
    end

    it 'allows addons to be added for specific networks' do
      runtime_config_file = yaml_file('runtime_config.yml', Bosh::Spec::Deployments.runtime_config_with_addon_includes_network)
      expect(bosh_runner.run("update-runtime-config #{runtime_config_file.path}")).to include('Succeeded')

      bosh_runner.run("upload-release #{spec_asset('bosh-release-0+dev.1.tgz')}")
      bosh_runner.run("upload-release #{spec_asset('dummy2-release.tgz')}")

      upload_stemcell

      cloud_config_hash = Bosh::Spec::NewDeployments.simple_cloud_config
      cloud_config_hash['networks'] = [
        { 'name' => 'a', 'subnets' => [Bosh::Spec::NewDeployments.subnet] },
        { 'name' => 'b', 'subnets' => [Bosh::Spec::NewDeployments.subnet] },
      ]
      upload_cloud_config(cloud_config_hash: cloud_config_hash)

      manifest_hash = Bosh::Spec::NewDeployments.test_release_manifest_with_stemcell
      manifest_hash['instance_groups'] = [
        Bosh::Spec::NewDeployments.simple_instance_group(network_name: 'a', name: 'has-addon-vm', instances: 1),
        Bosh::Spec::NewDeployments.simple_instance_group(network_name: 'b', name: 'no-addon-vm', instances: 1),
      ]
      deploy_simple_manifest(manifest_hash: manifest_hash)

      instances = director.instances

      addon_instance = instances.detect { |instance| instance.instance_group_name == 'has-addon-vm' }
      expect(File.exist?(addon_instance.job_path('foobar'))).to eq(true)
      expect(File.exist?(addon_instance.job_path('dummy'))).to eq(true)

      no_addon_instance = instances.detect { |instance| instance.instance_group_name == 'no-addon-vm' }
      expect(File.exist?(no_addon_instance.job_path('foobar'))).to eq(true)
      expect(File.exist?(no_addon_instance.job_path('dummy'))).to eq(false)
    end

    it 'allows addons to be excluded for specific lifecycle type' do
      runtime_config_file = yaml_file('runtime_config.yml', Bosh::Spec::Deployments.runtime_config_with_addon_excludes_lifecycle)
      expect(bosh_runner.run("update-runtime-config #{runtime_config_file.path}")).to include('Succeeded')

      bosh_runner.run("upload-release #{spec_asset('dummy2-release.tgz')}")

      manifest_hash = Bosh::Spec::NewDeployments.simple_manifest_with_instance_groups
      manifest_hash['instance_groups'][1] = Bosh::Spec::NewDeployments.simple_errand_instance_group.merge(
        'name' => 'errand',
      )

      prepare_for_deploy
      deploy_simple_manifest(manifest_hash: manifest_hash)

      bosh_runner.run('run-errand -d simple  errand --keep-alive')
      instances = director.instances

      no_addon_instance = instances.detect { |instance| instance.instance_group_name == 'errand' }
      expect(File.exist?(no_addon_instance.job_path('dummy'))).to eq(false)

      addon_instance = instances.detect { |instance| instance.instance_group_name == 'foobar' }
      expect(File.exist?(addon_instance.job_path('dummy'))).to eq(true)
    end
  end

  context 'in deployent manifests' do
    it 'allows addon to be added and ensures that addon job properties are properly assigned' do
      manifest_hash = Bosh::Spec::NewDeployments.manifest_with_addons

      bosh_runner.run("upload-release #{spec_asset('bosh-release-0+dev.1.tgz')}")
      bosh_runner.run("upload-release #{spec_asset('dummy2-release.tgz')}")

      upload_stemcell
      upload_cloud_config(cloud_config_hash: Bosh::Spec::NewDeployments.simple_cloud_config)
      deploy_simple_manifest(manifest_hash: manifest_hash)

      foobar_instance = director.instance('foobar', '0')

      expect(File.exist?(foobar_instance.job_path('dummy_with_properties'))).to eq(true)
      expect(File.exist?(foobar_instance.job_path('foobar'))).to eq(true)

      template = foobar_instance.read_job_template('dummy_with_properties', 'bin/dummy_with_properties_ctl')
      expect(template).to include("echo 'prop_value'")
    end

    it 'allows to apply exclude rules' do
      manifest_hash = Bosh::Spec::NewDeployments.manifest_with_addons
      manifest_hash['addons'][0]['exclude'] = { 'jobs' => [{ 'name' => 'foobar_without_packages', 'release' => 'bosh-release' }] }
      manifest_hash['instance_groups'][1] = Bosh::Spec::NewDeployments.simple_instance_group(
        name: 'foobar_without_packages',
        jobs: [{ 'name' => 'foobar_without_packages', 'release' => 'bosh-release' }],
        instances: 1,
      )

      bosh_runner.run("upload-release #{spec_asset('bosh-release-0+dev.1.tgz')}")
      bosh_runner.run("upload-release #{spec_asset('dummy2-release.tgz')}")

      upload_stemcell

      upload_cloud_config(cloud_config_hash: Bosh::Spec::NewDeployments.simple_cloud_config)
      deploy_simple_manifest(manifest_hash: manifest_hash)

      foobar_instance = director.instance('foobar', '0')
      expect(File.exist?(foobar_instance.job_path('dummy_with_properties'))).to eq(true)
      expect(File.exist?(foobar_instance.job_path('foobar'))).to eq(true)

      foobar_without_packages_instance = director.instance('foobar_without_packages', '0')
      expect(File.exist?(foobar_without_packages_instance.job_path('dummy_with_properties'))).to eq(false)
      expect(File.exist?(foobar_without_packages_instance.job_path('foobar_without_packages'))).to eq(true)
    end
  end

  context 'in both deployment manifest and runtime config' do
    it 'applies rules from both deployment manifest and from runtime config' do
      runtime_config = Bosh::Spec::Deployments.runtime_config_with_addon
      runtime_config['addons'][0]['include'] = { 'jobs' => [
        { 'name' => 'foobar', 'release' => 'bosh-release' },
      ] }

      runtime_config_file = yaml_file('runtime_config.yml', runtime_config)
      expect(bosh_runner.run("update-runtime-config #{runtime_config_file.path}")).to include('Succeeded')

      manifest_hash = Bosh::Spec::NewDeployments.complex_manifest_with_addon

      bosh_runner.run("upload-release #{spec_asset('bosh-release-0+dev.1.tgz')}")
      bosh_runner.run("upload-release #{spec_asset('dummy2-release.tgz')}")

      upload_stemcell # name: ubuntu-stemcell, os: toronto-os
      upload_stemcell_2 # name: centos-stemcell, os: toronto-centos

      cloud_config_hash = Bosh::Spec::NewDeployments.simple_os_specific_cloud_config
      upload_cloud_config(cloud_config_hash: cloud_config_hash)
      deploy_simple_manifest(manifest_hash: manifest_hash)

      instances = director.instances

      rc_addon_instance = instances.detect { |instance| instance.instance_group_name == 'has-rc-addon-vm' }
      depl_rc_addons_instance = instances.detect { |instance| instance.instance_group_name == 'has-depl-rc-addons-vm' }
      depl_addon_instance = instances.detect { |instance| instance.instance_group_name == 'has-depl-addon-vm' }

      expect(File.exist?(rc_addon_instance.job_path('dummy_with_properties'))).to eq(true)
      expect(File.exist?(rc_addon_instance.job_path('foobar'))).to eq(true)
      expect(File.exist?(rc_addon_instance.job_path('dummy'))).to eq(false)

      expect(File.exist?(depl_rc_addons_instance.job_path('dummy_with_properties'))).to eq(true)
      expect(File.exist?(depl_rc_addons_instance.job_path('foobar'))).to eq(true)
      expect(File.exist?(depl_rc_addons_instance.job_path('dummy'))).to eq(true)

      expect(File.exist?(depl_addon_instance.job_path('dummy_with_properties'))).to eq(false)
      expect(File.exist?(depl_addon_instance.job_path('foobar_without_packages'))).to eq(true)
      expect(File.exist?(depl_addon_instance.job_path('dummy'))).to eq(true)
    end
  end
end
