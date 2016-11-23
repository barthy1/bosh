require 'bosh/director/api/controllers/base_controller'
require 'time'

module Bosh::Director
  module Api::Controllers
    class EventsController < BaseController
      EVENT_LIMIT = 200

      get '/' do
        content_type(:json)

        events = Models::Event.order_by(Sequel.desc(:id))

        if params['before_id']
          before_id = params['before_id'].to_i
          events = events.filter("id < ?", before_id)
        end

        if params['before_time']
          begin
            before_datetime = timestamp_filter_value(params['before_time'])
          rescue ArgumentError
            status(400)
            body("Invalid before parameter: '#{params['before_time']}' ")
            return
          end
          events = events.filter("timestamp < ?", before_datetime)
        end

        if params['after_time']
          begin
            after_datetime = timestamp_filter_value(params['after_time']) + 1
          rescue ArgumentError
            status(400)
            body("Invalid after parameter: '#{params['after_time']}' ")
            return
          end
          events = events.filter("timestamp >= ?", after_datetime)
        end

        if params['task']
          events = events.where(task: params['task'])
        end

        if params['deployment']
          events = events.where(deployment: params['deployment'])
        end

        if params['instance']
          events = events.where(instance: params['instance'])
        end

        events = events.limit(EVENT_LIMIT).map do |event|
          @event_manager.event_to_hash(event)
        end
        json_encode(events)
      end

      post '/', :consumes => [:json] do
        Config.logger.info("yulia: get post")
        @permission_authorizer.granted_or_raise(:director, :admin, token_scopes)
        payload = json_decode(request.body.read)
        if payload['action'].nil? || payload['object_type'].nil? || payload['object_name'].nil?
          raise ValidationInvalidType, 'Action, object_type, object_name are required'
        end

        error   = payload['error'].nil? ? nil : payload['error']
        context = payload['context'].nil? ? nil : payload['context']
        if !context.nil? && !context.kind_of?(Hash)
          raise ValidationInvalidType, 'Context must be a hash'
        end
        begin
          timestamp = payload['timestamp'].nil? ? nil : timestamp_filter_value(payload['timestamp'])
        rescue ArgumentError, "Invalid timestamp parameter: '#{payload['timestamp']}' "
        end

        @event_manager.create_event(
          {
            parent_id:   nil,
            timestamp:   timestamp,
            user:        current_user,
            action:      payload['action'],
            object_type: payload['object_type'],
            object_name: payload['object_name'],
            deployment:  payload['deployment'],
            instance:    payload['instance'],
            task:        nil,
            error:       error,
            context:     context
          })
      end

      private

      def timestamp_filter_value(value)
        return Time.at(value.to_i).utc if integer?(value)
        Time.parse(value)
      end

      def integer?(string)
        string =~ /\A[-+]?\d+\z/
      end
    end
  end
end
