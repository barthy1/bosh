module Bosh::Director
  class TaskDBWriter
    def initialize(column, task_id)
      @column_name = column
      @task_id = task_id
      @task = Models::Task[@task_id]
    end

    def write(text)
      Config.logger.info("yulia! task_id write #{@task_id}")
      Config.logger.info("yulia! write event #{text}")
      @task[@column_name] = "#{@task[@column_name]}#{text}"
      @task.save
     # Config.logger.info("yulia! task #{@task.inspect}")
    end
  end
end
