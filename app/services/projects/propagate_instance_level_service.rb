# frozen_string_literal: true

module Projects
  class PropagateInstanceLevelService
    BATCH_SIZE = 100

    def self.propagate(*args)
      new(*args).propagate
    end

    def initialize(instance_level_service)
      @instance_level_service = instance_level_service
    end

    def propagate
      return unless @instance_level_service.active?

      Rails.logger.info("Propagating services for instance_level_service #{@instance_level_service.id}") # rubocop:disable Gitlab/RailsLogger

      propagate_projects_with_instance_level_service
    end

    private

    def propagate_projects_with_instance_level_service
      loop do
        batch = Project.uncached { project_ids_batch }

        bulk_create_from_instance_level_service(batch) unless batch.empty?

        break if batch.size < BATCH_SIZE
      end
    end

    def bulk_create_from_instance_level_service(batch)
      service_list = batch.map do |project_id|
        service_hash.values << project_id
      end

      Project.transaction do
        bulk_insert_services(service_hash.keys << 'project_id', service_list)
        run_callbacks(batch)
      end
    end

    def project_ids_batch
      Project.connection.select_values(
        <<-SQL
          SELECT id
          FROM projects
          WHERE NOT EXISTS (
            SELECT true
            FROM services
            WHERE services.project_id = projects.id
            AND services.type = '#{@instance_level_service.type}'
          )
          AND projects.pending_delete = false
          AND projects.archived = false
          LIMIT #{BATCH_SIZE}
      SQL
      )
    end

    def bulk_insert_services(columns, values_array)
      ActiveRecord::Base.connection.execute(
        <<-SQL.strip_heredoc
          INSERT INTO services (#{columns.join(', ')})
          VALUES #{values_array.map { |tuple| "(#{tuple.join(', ')})" }.join(', ')}
      SQL
      )
    end

    def service_hash
      @service_hash ||=
        begin
          instance_hash = @instance_level_service.as_json(methods: :type).except('id', 'instance', 'project_id')

          instance_hash.each_with_object({}) do |(key, value), service_hash|
            value = value.is_a?(Hash) ? value.to_json : value

            service_hash[ActiveRecord::Base.connection.quote_column_name(key)] =
              ActiveRecord::Base.connection.quote(value)
          end
        end
    end

    # rubocop: disable CodeReuse/ActiveRecord
    def run_callbacks(batch)
      if active_external_issue_tracker?
        Project.where(id: batch).update_all(has_external_issue_tracker: true)
      end

      if active_external_wiki?
        Project.where(id: batch).update_all(has_external_wiki: true)
      end
    end
    # rubocop: enable CodeReuse/ActiveRecord

    def active_external_issue_tracker?
      @instance_level_service.issue_tracker? && !@instance_level_service.default
    end

    def active_external_wiki?
      @instance_level_service.type == 'ExternalWikiService'
    end
  end
end