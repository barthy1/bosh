module Bosh::Director
  module Jobs
    class DBJob
      attr_reader :job_class, :task_id

      def initialize(job_class, task_id, args)
        raise DirectorError, "Invalid director job class `#{job_class}'. It should have `perform' method."  unless job_class.instance_methods(false).include?(:perform)
        unless job_class.kind_of?(Class) &&
            job_class <= Jobs::BaseJob
          raise DirectorError, "Invalid director job class `#{job_class}'"
        end
        @job_class = job_class
        @task_id = task_id
        @args = args
        raise DirectorError, "Invalid director job class `#{job_class}'. It should specify queue value." unless queue_name
      end

      def perform
        @job_class.perform(@task_id, *@args)
      end

      def queue_name
        @job_class.instance_variable_get(:@queue) ||
            (@job_class.respond_to?(:queue) and @job_class.queue)
      end
    end
  end
end