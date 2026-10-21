# frozen_string_literal: true

module Settings::PendingChangesHelper
  def pending_change_types(change_set)
    @summary.groups(change_set).group_by { |group| group[:type] }.map do |type, groups|
      t("settings.pending_changes.types.#{type}", count: groups.sum { |group| group[:count] })
    end.join(" · ")
  end

  def pending_change_context(group)
    accounts = group[:accounts].map do |account|
      if account[:name].nil?
        t("settings.pending_changes.summary.account_unavailable")
      elsif account[:proposed]
        t("settings.pending_changes.summary.proposed_account", name: account[:name])
      else
        account[:name]
      end
    end
    return accounts.join(" → ") if accounts.any?
    return t("settings.pending_changes.summary.no_context") if group[:names].empty?

    names = group[:names].first(3).join(", ")
    remaining = group[:names].size - 3
    remaining.positive? ? t("settings.pending_changes.summary.more_names", names: names, count: remaining) : names
  end

  def pending_change_amount(group)
    return t("settings.pending_changes.summary.unspecified_amount") unless group[:amount]
    format_money(Money.new(group[:amount], group[:currency]))
  rescue Money::Currency::UnknownCurrencyError
    t("settings.pending_changes.summary.unspecified_amount")
  end

  def pending_change_states(group)
    group[:states].map do |state, count|
      t("settings.pending_changes.execution_states.#{state}", count: count)
    end.join(" · ")
  end
end
