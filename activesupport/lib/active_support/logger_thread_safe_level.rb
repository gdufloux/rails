# frozen_string_literal: true

require "active_support/concern"
require "active_support/core_ext/module/attribute_accessors"
require "concurrent"
require "fiber"

module ActiveSupport
  module LoggerThreadSafeLevel # :nodoc:
    extend ActiveSupport::Concern

    included do
      cattr_accessor :local_levels, default: Concurrent::Map.new(initial_capacity: 2), instance_accessor: false
    end

    Logger::Severity.constants.each do |severity|
      class_eval(<<-EOT, __FILE__, __LINE__ + 1)
        def #{severity.downcase}?                # def debug?
          Logger::#{severity} >= level           #   DEBUG >= level
        end                                      # end
      EOT
    end

    def after_initialize
      ActiveSupport::Deprecation.warn(
        "Logger don't need to call #after_initialize directly anymore. It will be deprecated without replacement in " \
        "Rails 6.1."
      )
    end

    def local_log_id
      Fiber.current.__id__
    end

    def local_level
      self.class.local_levels[local_log_id]
    end

    def local_level=(level)
      if level
        self.class.local_levels[local_log_id] = level
      else
        self.class.local_levels.delete(local_log_id)
      end
    end

    def level
      local_level || super
    end

    # Redefined to check severity against #level, and thus the thread-local level, rather than +@level+.
    # FIXME: Remove when the minimum Ruby version supports overriding Logger#level.
    def add(severity, message = nil, progname = nil, &block) # :nodoc:
      severity ||= UNKNOWN
      progname ||= @progname

      return true if @logdev.nil? || severity < level

      if message.nil?
        if block_given?
          message  = yield
        else
          message  = progname
          progname = @progname
        end
      end

      @logdev.write \
        format_message(format_severity(severity), Time.now, progname, message)
    end
  end
end
