# Narrative uses the same deterministic facts as the financial generators.
class Insight::BodyWriter
  def initialize(family)
    @family = family
  end

  def write(generated_insight)
    I18n.t("insights.templates.#{generated_insight.template_key}",
           **generated_insight.facts.symbolize_keys)
  end
end
