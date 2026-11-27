# Records the rate revisions that have come due on loans with structured rate
# periods, keeps their scheduled instalments at the amount now due, and
# recalculates the account when a new rate changes the interest it posts.
class ReviewLoanRatesJob < ApplicationJob
  queue_as :scheduled

  def perform(loan_id = nil)
    loans = Loan.where(id: Loan::RatePeriod.select(:loan_id)).includes(:account)
    loans = loans.where(id: loan_id) if loan_id

    loans.find_each do |loan|
      next if loan.account.nil?

      begin
        created = loan.rate_reviewer.record_due!
        loan.sync_scheduled_payments!
        loan.account.sync_later if created.any?
      rescue => error
        DebugLogEntry.capture(
          category: "loan_rate_review", level: "error", message: "#{error.class}: #{error.message}",
          source: self.class.name, account: loan.account
        )
      end
    end
  end
end
