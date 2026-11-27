module Transaction::Splittable
  extend ActiveSupport::Concern

  def splittable?
    !investment_value_adjustment? && !loan_interest? && !transfer? && !entry.split_child? && !entry.split_parent? && !entry.excluded?
  end
end
