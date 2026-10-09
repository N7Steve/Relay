module TransfersHelper
  def managed_transfer_form_accounts(accounts)
    accounts.to_h { |account| [ account.id, { name: account.name, managed: account.managed_portfolio? } ] }
  end

  def managed_transfer_form_names
    %w[contribution withdrawal transfer].index_with do |operation|
      t("investment_values.operations.#{operation}_name", locale: Current.family.locale,
        portfolio: "%{portfolio}", from: "%{from}", to: "%{to}")
    end
  end
end
