# frozen_string_literal: true

class Mcp::ApplyChangeSetJob < ApplicationJob
  queue_as :default

  retry_on ActiveRecord::Deadlocked, attempts: 5 do |job, error|
    job.arguments.first.fail_application!(error)
  end

  def perform(change_set)
    change_set.apply!
  end
end
