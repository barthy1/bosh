require 'bosh/director/api/controllers/base_controller'

module Bosh::Director
  module Api::Controllers
    class EventsController < BaseController
      EVENT_LIMIT = 200

      get '/' do
        content_type(:json)

        events = Models::Event.order_by(Sequel.desc(:id))

        if params['before_id']
          before_id = params['before_id'].to_i
          events = events.filter("id < ?", before_id).limit(EVENT_LIMIT)
        end

        events = events.map do |event|
          @event_manager.event_to_hash(event)
        end
        json_encode(events)
      end
    end
  end
end
