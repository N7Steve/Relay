class DS::Checkbox < DesignSystemComponent
  attr_reader :form, :method, :label, :checked_value, :unchecked_value, :opts

  def initialize(form:, method:, label:, checked_value: "1", unchecked_value: "0", **opts)
    @form, @method, @label = form, method, label
    @checked_value, @unchecked_value = checked_value, unchecked_value
    @opts = opts
  end
end
