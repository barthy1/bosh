module Bosh::Director
  class DeploymentManifestResolver

    extend ValidationHelper

    # returns a resolved deployment manifest
    # It will contain uninterpolated properties that will never get resolved
    def self.resolve_manifest(raw_deployment_manifest, resolve_interpolation)
      result_deployment_manifest = Bosh::Common::DeepCopy.copy(raw_deployment_manifest)
      self.inject_uninterpolated_properties!(result_deployment_manifest)

      if Bosh::Director::Config.config_server_enabled && resolve_interpolation
        ignored_subtrees = []
        ignored_subtrees << ['uninterpolated_properties']
        ignored_subtrees << ['instance_groups', Numeric.new, 'uninterpolated_properties']
        ignored_subtrees << ['instance_groups', Numeric.new, 'jobs', Numeric.new, 'uninterpolated_properties']
        ignored_subtrees << ['jobs', Numeric.new, 'uninterpolated_properties']
        ignored_subtrees << ['jobs', Numeric.new, 'templates', Numeric.new, 'uninterpolated_properties']
        result_deployment_manifest = Bosh::Director::ConfigServer::ConfigParser.parse(result_deployment_manifest, ignored_subtrees)
      end
      result_deployment_manifest
    end

    private

    def self.inject_uninterpolated_properties!(deployment_manifest)
      self.inject_uninterpolated_global_properties!(deployment_manifest)
      self.inject_instance_group_and_job_level_uninterpolated_properties!(deployment_manifest)
    end

    def self.inject_uninterpolated_global_properties!(deployment_manifest)
      self.copy_properties_to_uninterpolated_properties!(deployment_manifest)
    end

    def self.inject_instance_group_and_job_level_uninterpolated_properties!(deployment_manifest)
      outer_key = 'instance_groups'
      inner_key = 'jobs'

      if is_legacy_manifest?(deployment_manifest)
        outer_key = 'jobs'
        inner_key = 'templates'
      end

      instance_groups_list = safe_property(deployment_manifest, outer_key, :class => Array, :default => [])
      instance_groups_list.each do |instance_group_hash|
        self.copy_properties_to_uninterpolated_properties!(instance_group_hash)

        jobs_list = safe_property(instance_group_hash, inner_key, :class => Array, :default => [])
        jobs_list.each do |job_hash|
          self.copy_properties_to_uninterpolated_properties!(job_hash)
        end
      end
    end

    def self.copy_properties_to_uninterpolated_properties!(generic_hash)
      properties = safe_property(generic_hash, 'properties', :class => Hash, :optional => true)
      if properties
        generic_hash['uninterpolated_properties'] = Bosh::Common::DeepCopy.copy(properties)
      end
    end

    def self.is_legacy_manifest?(deployment_manifest)
      deployment_manifest['instance_groups'].nil?
    end
  end
end
