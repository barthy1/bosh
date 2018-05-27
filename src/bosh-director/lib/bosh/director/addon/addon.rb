module Bosh::Director
  module Addon
    DEPLOYMENT_LEVEL = :deployment
    RUNTIME_LEVEL = :runtime

    class Addon
      extend ValidationHelper

      attr_reader :name

      def initialize(name, job_hashes, options)
        @name = name
        @addon_job_hashes = job_hashes
        @addon_level_properties = options.fetch(:addon_level_properties)
        @addon_include = options.fetch(:addon_include)
        @addon_exclude = options.fetch(:addon_exclude)
        @addon_includes = options.fetch(:addon_includes)
        @addon_excludes = options.fetch(:addon_excludes)
        @links_parser = Bosh::Director::Links::LinksParser.new
      end

      def jobs
        @addon_job_hashes
      end

      def properties
        @addon_level_properties
      end

      def self.parse(addon_hash, addon_level = RUNTIME_LEVEL)
        name = safe_property(addon_hash, 'name', :class => String)
        addon_job_hashes = safe_property(addon_hash, 'jobs', :class => Array, :default => [])
        parsed_addon_jobs = []
        addon_job_hashes.each do |addon_job_hash|
          parsed_addon_jobs << parse_and_validate_job(addon_job_hash)
        end

        include = safe_property(addon_hash, 'include', class: Hash, optional: true)
        exclude = safe_property(addon_hash, 'exclude', class: Hash, optional: true)
        includes = safe_property(addon_hash, 'includes', class: Array, default: [])
        excludes = safe_property(addon_hash, 'excludes', class: Array, default: [])

        if !include.nil? && !includes.empty?
          raise AddonSingleAndArrayFilter, 'Include and includes sections cannot be both specified. Please remove one of them'
        end
        if !exclude.nil? && !excludes.empty?
          raise AddonSingleAndArrayFilter, 'Exclude and excludes sections cannot be both specified. Please remove one of them'
        end

        options = {
          addon_level_properties: safe_property(addon_hash, 'properties', class: Hash, optional: true),
          addon_include: Filter.parse(include, :include, addon_level),
          addon_exclude: Filter.parse(exclude, :exclude, addon_level),
          addon_includes: parse_filters(includes, :include, addon_level),
          addon_excludes: parse_filters(excludes, :exclude, addon_level),
        }

        new(name, parsed_addon_jobs, options)
      end

      def applies?(deployment_name, deployment_teams, deployment_instance_group)
        if !@addon_includes.empty?
          addon_includes_applies = false
          @addon_includes.each do |addon_include|
            addon_includes_applies ||= addon_include.applies?(deployment_name, deployment_teams, deployment_instance_group)
          end
        else
          addon_includes_applies = true
        end

        addon_excludes_applies = false
        unless @addon_excludes.empty?
          @addon_excludes.each do |addon_exclude|
            addon_excludes_applies ||= addon_exclude.applies?(deployment_name, deployment_teams, deployment_instance_group)
          end
        end

        addon_includes_applies && !addon_excludes_applies &&
          @addon_include.applies?(deployment_name, deployment_teams, deployment_instance_group) &&
          !@addon_exclude.applies?(deployment_name, deployment_teams, deployment_instance_group)
      end

      def add_to_deployment(deployment)
        eligible_instance_groups = deployment.instance_groups.select do |instance_group|
          applies?(deployment.name, deployment.team_names, instance_group)
        end

        add_addon_jobs_to_instance_groups(deployment, eligible_instance_groups) unless eligible_instance_groups.empty?
      end

      def releases
        @addon_job_hashes.map do |addon|
          addon['release']
        end.uniq
      end

      def self.parse_filters(addon_filters, filter_type, addon_level)
        addon_filters.collect { |filter_hash| Filter.parse(filter_hash, filter_type, addon_level) }
      end

      private

      def self.parse_and_validate_job(addon_job)
        {
          'name' => safe_property(addon_job, 'name', :class => String),
          'release' => safe_property(addon_job, 'release', :class => String),
          'provides' => safe_property(addon_job, 'provides', class: Hash, default: {}),
          'consumes' => safe_property(addon_job, 'consumes', class: Hash, default: {}),
          'properties' => safe_property(addon_job, 'properties', class: Hash, optional: true),
        }
      end

      def add_addon_jobs_to_instance_groups(deployment, eligible_instance_groups)
        @addon_job_hashes.each do |addon_job_hash|
          deployment_release_version = deployment.release(addon_job_hash['release'])
          deployment_release_version.bind_model

          addon_job_object = DeploymentPlan::Job.new(deployment_release_version, addon_job_hash['name'], deployment.name)
          addon_job_object.bind_models

          eligible_instance_groups.each do |instance_group|
            instance_group_name = instance_group.name

            if addon_job_hash['properties']
              job_properties = addon_job_hash['properties']
            else
              job_properties = @addon_level_properties
            end

            addon_job_object.add_properties(job_properties, instance_group_name)

            @links_parser.parse_providers_from_job(addon_job_hash, deployment.model, addon_job_object.model, job_properties, instance_group_name)
            @links_parser.parse_consumers_from_job(addon_job_hash, deployment.model, addon_job_object.model, instance_group_name)

            instance_group.add_job(addon_job_object)
          end
        end
      end
    end
  end
end
