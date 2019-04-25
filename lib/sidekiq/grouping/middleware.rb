module Sidekiq
  module Grouping
    class Middleware
      def call(worker_class, msg, queue, redis_pool = nil)
        return yield if (defined?(Sidekiq::Testing) && Sidekiq::Testing.inline?)

        if worker_class.is_a?(String)
          worker_class = worker_class.camelize.constantize rescue nil
          if worker_class.nil?
            return yield
          end
        end

        options = worker_class.get_sidekiq_options

        batch =
          options.key?('batch_flush_size') ||
          options.key?('batch_flush_interval') ||
          options.key?('batch_size')

        passthrough =
          msg['args'] &&
          msg['args'].is_a?(Array) &&
          msg['args'].try(:first) == true

        retrying = msg["failed_at"].present?

        return yield unless batch

        if !(passthrough || retrying)
          add_to_batch(worker_class, queue, msg, redis_pool)
        else
          msg['args'].shift if passthrough
          yield
        end
      end

      private

      def add_to_batch(worker_class, queue, msg, redis_pool = nil)
        Sidekiq::Grouping::Batch
          .new(worker_class.name, queue, redis_pool)
          .add(msg['args'])

        nil
      end
    end
  end
end
