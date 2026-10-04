class SweepExpiredGoalPledgesJob < ApplicationJob
  queue_as :scheduled

  # Per-record rescue so one bad pledge (lock contention, missing FK,
  # stale row) doesn't abort the sweep and leave the rest open forever.
  # The outer rescue catches query-phase failures (DB blip, OOM mid-cursor)
  # so a single bad batch surfaces to local diagnostics rather than disappearing into
  # Sidekiq's generic retry log. Re-raise after reporting so the retry
  # behaviour still kicks in.
  def perform
    GoalPledge.open_and_expired_now.find_each do |pledge|
      pledge.expire!
    rescue => e
      Rails.logger.error("SweepExpiredGoalPledgesJob: pledge ##{pledge.id} expire failed: #{e.class}: #{e.message}")
      LocalDiagnostics.report(e, source: "jobs/sweep_expired_goal_pledges_job")
    end
  rescue StandardError => e
    Rails.logger.error("SweepExpiredGoalPledgesJob: cursor failed: #{e.class}: #{e.message}")
    LocalDiagnostics.report(e, source: "jobs/sweep_expired_goal_pledges_job")
    raise
  end
end
