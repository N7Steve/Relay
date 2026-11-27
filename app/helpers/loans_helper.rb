module LoansHelper
  # The two policies Loan::Insurance knows how to charge. Listed here rather
  # than built from the constant so each one carries a translated label.
  def loan_insurance_rate_type_options
    [
      [ t("loans.form.insurance_rate_type_level_term"), Loan::Insurance::LEVEL_TERM ],
      [ t("loans.form.insurance_rate_type_decreasing_life"), Loan::Insurance::DECREASING_LIFE ]
    ]
  end

  # How leveraged the loan was at drawdown, as a design-system colour. Bands are
  # Loan's; the colours are this layer's.
  def loan_leverage_band_class(band)
    {
      conservative: "text-success",
      moderate: "text-warning",
      high: "text-destructive"
    }.fetch(band, "text-secondary")
  end

  # The rate types the form offers, plus the loan's own when a provider wrote
  # one the form does not know (#100 decision 8). Without it the select has no
  # matching option, the browser submits the first one, and saving any other
  # field silently turns an "arm" loan into a fixed one.
  def loan_rate_type_options(loan)
    options = [
      [ t("loans.form.rate_type_fixed"), Loan::FIXED_RATE_TYPE ],
      [ t("loans.form.rate_type_variable"), "variable" ],
      [ t("loans.form.rate_type_adjustable"), "adjustable" ]
    ]
    return options if loan.rate_type.blank? || options.any? { |_, value| value == loan.rate_type }

    options << [ loan.rate_type.titleize, loan.rate_type ]
  end

  # A rate as Spanish lenders quote it: three decimals, no trailing zeros
  # beyond two ("1,50 %", "3,839 %").
  def loan_rate_percentage(rate)
    return t("loans.tabs.rates.unknown") if rate.nil?

    number_to_percentage(rate, precision: 3, strip_insignificant_zeros: true)
  end

  # How a revision's rate was built, in one line: "Euríbor 12M 3,239 % (oct 2026)
  # + diferencial 1,80 % − bonificaciones 1,20 %".
  def loan_rate_composition(revision)
    parts = if revision.variable?
      index = t("reference_rates.indexes.#{revision.reference_index}", default: revision.reference_index.to_s)
      month = revision.index_month ? l(revision.index_month, format: :month_year) : nil
      [
        t("loans.tabs.rates.composition.index", index: index, value: loan_rate_percentage(revision.index_value),
                                                month: month ? " (#{month})" : ""),
        t("loans.tabs.rates.composition.spread", value: loan_rate_percentage(revision.spread))
      ]
    else
      [ t("loans.tabs.rates.composition.fixed", value: loan_rate_percentage(revision.base_rate)) ]
    end
    parts << t("loans.tabs.rates.composition.bonuses", value: loan_rate_percentage(revision.bonus_points)) if revision.bonus_points.to_d.positive?
    parts.join(" ")
  end

  # A scenario figure, which may be Money, a bare amount or missing.
  def loan_money(currency, amount)
    return "—" if amount.nil?

    format_money(amount.is_a?(Money) ? amount : Money.new(amount, currency))
  end

  def loan_outcome_value(currency, value)
    value.is_a?(Date) ? l(value, format: :long) : loan_money(currency, value)
  end

  def loan_rate_revision_status(revision, as_of:)
    if revision.new_record?
      revision.effective_on > as_of ? :projected : :pending
    else
      revision.confirmed? ? :confirmed : :calculated
    end
  end

  def loan_rate_revision_tone(status)
    { projected: :neutral, pending: :warning, calculated: :info, confirmed: :success }.fetch(status, :neutral)
  end
end
