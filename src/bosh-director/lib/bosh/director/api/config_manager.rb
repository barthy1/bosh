module Bosh
  module Director
    module Api
      class ConfigManager
        def initialize
          @tasks_config_manager = TasksConfigManager.new
        end

        def create(type, name, config_yaml, team_id = nil)
          config = Bosh::Director::Models::Config.new(
            type: type,
            name: name,
            content: config_yaml,
            team_id: team_id,
          )
          config.save
          @tasks_config_manager.rebuild_groups if type == 'tasks'
          config
        end

        def find(type: nil, name: nil, limit: 1)
          dataset = Bosh::Director::Models::Config.where(deleted: false)
          dataset = dataset.where(type: type) if type
          dataset = dataset.where(name: name) if name

          return find_latest(dataset) if limit == 1

          combinations = dataset.group(:type, :name)
            .order(:type)
            .order_append { Sequel.case([[{ name: 'default' }, 1]], 2) }
            .order_append(:name).select_map([:type, :name])

          combinations.flat_map do |type, name|
            Bosh::Director::Models::Config.where(deleted: false, name: name, type: type)
              .order(Sequel.desc(:id))
              .limit(limit).all
          end
        end

        def find_max_id
          dataset = Bosh::Director::Models::Config
          configs = dataset.where(id: dataset.select { max(:id) }).all

          configs.empty? ? 0 : configs[0][:id]
        end

        def find_by_id(id)
          config = Bosh::Director::Models::Config[id]
          raise ConfigNotFound, "Config #{id} not found" if config.nil? || config.deleted
          config
        end

        def delete(type, name)
          config = Bosh::Director::Models::Config
            .where(type: type, name: name, deleted: false)
            .update(deleted: true)
          @tasks_config_manager.rebuild_groups if type == 'tasks'
          config
        end

        def delete_by_id(id)
          Bosh::Director::Models::Config
            .where(id: id, deleted: false)
            .update(deleted: true)
        end

        private

        def find_latest(dataset)
          dataset = dataset.where(id: dataset.select { max(:id) }.group(:type, :name))
          dataset
            .order(:type)
            .order_append {Sequel.case([[{name: 'default'}, 1]], 2)}
            .order_append(:name)
            .order_append(Sequel.desc(:id))
            .all
        end

        def integer?(param)
          param.to_s == param.to_i.to_s
        end
      end
    end
  end
end
