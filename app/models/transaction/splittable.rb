module Transaction::Splittable
  extend ActiveSupport::Concern

  def splittable?
    !investment_value_adjustment? && !transfer? && !entry.split_child? && !entry.split_parent? && !pending? && !entry.excluded?
  end
end
