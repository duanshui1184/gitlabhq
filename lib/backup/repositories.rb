# frozen_string_literal: true

require 'yaml'

module Backup
  class Repositories < Task
    extend ::Gitlab::Utils::Override

    def initialize(progress, strategy:, max_concurrency: 1, max_storage_concurrency: 1)
      super(progress)

      @strategy = strategy
      @max_concurrency = max_concurrency
      @max_storage_concurrency = max_storage_concurrency
    end

    override :dump
    def dump(path)
      strategy.start(:create, path)

      # gitaly-backup is designed to handle concurrency on its own. So we want
      # to avoid entering the buggy concurrency code here when gitaly-backup
      # is enabled.
      if (max_concurrency <= 1 && max_storage_concurrency <= 1) || !strategy.parallel_enqueue?
        return enqueue_consecutive
      end

      if max_concurrency < 1 || max_storage_concurrency < 1
        puts "GITLAB_BACKUP_MAX_CONCURRENCY and GITLAB_BACKUP_MAX_STORAGE_CONCURRENCY must have a value of at least 1".color(:red)
        exit 1
      end

      check_valid_storages!

      semaphore = Concurrent::Semaphore.new(max_concurrency)
      errors = Queue.new

      threads = Gitlab.config.repositories.storages.keys.map do |storage|
        Thread.new do
          Rails.application.executor.wrap do
            enqueue_storage(storage, semaphore, max_storage_concurrency: max_storage_concurrency)
          rescue StandardError => e
            errors << e
          end
        end
      end

      ActiveSupport::Dependencies.interlock.permit_concurrent_loads do
        threads.each(&:join)
      end

      raise errors.pop unless errors.empty?
    ensure
      strategy.finish!
    end

    override :restore
    def restore(path)
      strategy.start(:restore, path)
      enqueue_consecutive

    ensure
      strategy.finish!

      cleanup_snippets_without_repositories
      restore_object_pools
    end

    override :human_name
    def human_name
      _('repositories')
    end

    private

    attr_reader :strategy, :max_concurrency, :max_storage_concurrency

    def check_valid_storages!
      repository_storage_klasses.each do |klass|
        if klass.excluding_repository_storage(Gitlab.config.repositories.storages.keys).exists?
          raise Error, "repositories.storages in gitlab.yml does not include all storages used by #{klass}"
        end
      end
    end

    def repository_storage_klasses
      [ProjectRepository, SnippetRepository]
    end

    def enqueue_consecutive
      enqueue_consecutive_projects
      enqueue_consecutive_snippets
    end

    def enqueue_consecutive_projects
      project_relation.find_each(batch_size: 1000) do |project|
        enqueue_project(project)
      end
    end

    def enqueue_consecutive_snippets
      Snippet.find_each(batch_size: 1000) { |snippet| enqueue_snippet(snippet) }
    end

    def enqueue_storage(storage, semaphore, max_storage_concurrency:)
      errors = Queue.new
      queue = InterlockSizedQueue.new(1)

      threads = Array.new(max_storage_concurrency) do
        Thread.new do
          Rails.application.executor.wrap do
            while container = queue.pop
              ActiveSupport::Dependencies.interlock.permit_concurrent_loads do
                semaphore.acquire
              end

              begin
                enqueue_container(container)
              rescue StandardError => e
                errors << e
                break
              ensure
                semaphore.release
              end
            end
          end
        end
      end

      enqueue_records_for_storage(storage, queue, errors)

      raise errors.pop unless errors.empty?
    ensure
      queue.close
      ActiveSupport::Dependencies.interlock.permit_concurrent_loads do
        threads.each(&:join)
      end
    end

    def enqueue_container(container)
      case container
      when Project
        enqueue_project(container)
      when Snippet
        enqueue_snippet(container)
      end
    end

    def enqueue_project(project)
      strategy.enqueue(project, Gitlab::GlRepository::PROJECT)
      strategy.enqueue(project, Gitlab::GlRepository::WIKI)
      strategy.enqueue(project, Gitlab::GlRepository::DESIGN)
    end

    def enqueue_snippet(snippet)
      strategy.enqueue(snippet, Gitlab::GlRepository::SNIPPET)
    end

    def enqueue_records_for_storage(storage, queue, errors)
      records_to_enqueue(storage).each do |relation|
        relation.find_each(batch_size: 100) do |project|
          break unless errors.empty?

          queue.push(project)
        end
      end
    end

    def records_to_enqueue(storage)
      [projects_in_storage(storage), snippets_in_storage(storage)]
    end

    def projects_in_storage(storage)
      project_relation.id_in(ProjectRepository.for_repository_storage(storage).select(:project_id))
    end

    def project_relation
      Project.includes(:route, :group, namespace: :owner)
    end

    def snippets_in_storage(storage)
      Snippet.id_in(SnippetRepository.for_repository_storage(storage).select(:snippet_id))
    end

    def restore_object_pools
      PoolRepository.includes(:source_project).find_each do |pool|
        progress.puts " - Object pool #{pool.disk_path}..."

        pool.source_project ||= pool.member_projects.first&.root_of_fork_network
        unless pool.source_project
          progress.puts " - Object pool #{pool.disk_path}... " + "[SKIPPED]".color(:cyan)
          next
        end

        pool.state = 'none'
        pool.save

        pool.schedule
      end
    end

    # Snippets without a repository should be removed because they failed to import
    # due to having invalid repositories
    def cleanup_snippets_without_repositories
      invalid_snippets = []

      Snippet.find_each(batch_size: 1000).each do |snippet|
        response = Snippets::RepositoryValidationService.new(nil, snippet).execute
        next if response.success?

        snippet.repository.remove
        progress.puts("Snippet #{snippet.full_path} can't be restored: #{response.message}")

        invalid_snippets << snippet.id
      end

      Snippet.id_in(invalid_snippets).delete_all
    end

    class InterlockSizedQueue < SizedQueue
      extend ::Gitlab::Utils::Override

      override :pop
      def pop(*)
        ActiveSupport::Dependencies.interlock.permit_concurrent_loads do
          super
        end
      end

      override :push
      def push(*)
        ActiveSupport::Dependencies.interlock.permit_concurrent_loads do
          super
        end
      end
    end
  end
end

Backup::Repositories.prepend_mod_with('Backup::Repositories')
