Sequel.migration do
  change do
    alter_table(:tasks) do
      add_column(:event_output, String, :text => true, :default => '')
      add_column(:result_output, String, :text => true, :default => '')
    end
  end
end
