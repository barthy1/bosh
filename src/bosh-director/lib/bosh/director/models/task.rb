# Copyright (c) 2009-2012 VMware, Inc.

module Bosh::Director::Models
  class Task < Sequel::Model(Bosh::Director::Config.db)
    many_to_many :teams

    def validate
      validates_presence [:state, :timestamp, :description]
    end

    def self.create_with_teams(attributes)
      teams = attributes.delete(:teams)
      task = create(attributes)
      task.teams = teams
      task
    end

    def teams=(teams)
      (teams || []).each do |t|
        self.add_team(t)
      end
    end

    # def event_output
    #   return "" if self.event_output_text.nil?
    # end
    #
    # def result_output
    #   return "" if self.result_output_text.nil?
    # end
    #
    # def event_output=(value)
    #   self.event_output_text=value.nil? ? "" : value
    # end
    #
    # def result_output=(value)
    #   self.result_output_text = value.nil? ? "" : value
    # end
  end
end
