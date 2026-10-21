# frozen_string_literal: true

class Mcp::ApplyChangeSetJob < ApplicationJob
  queue_as :default

  def perform(change_set)
    change_set.apply!
  end
end
