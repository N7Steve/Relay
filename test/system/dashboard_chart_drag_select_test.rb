require "application_system_test_case"

class DashboardChartDragSelectTest < ApplicationSystemTestCase
  setup do
    @user = users(:family_admin)
  end

  test "net worth shows monetary references and uses the plot height for a large increase" do
    sign_in @user
    assert_selector "#netWorthChart .value-axis .tick text"

    # Reproduce the reported 5,000 → 50,000 increase independently of fixtures.
    page.execute_script <<~JS
      const chart = document.querySelector("#netWorthChart");
      const data = JSON.parse(chart.dataset.timeSeriesChartDataValue);
      data.values.forEach((point, index) => {
        point.value.amount = 5000 + 45000 * index / (data.values.length - 1);
      });
      chart.dataset.timeSeriesChartDataValue = JSON.stringify(data);
      requestAnimationFrame(() => document.dispatchEvent(new Event("turbo:load")));
    JS

    assert_selector "#netWorthChart .value-axis .tick text", text: /60/
    assert_operator find("#netWorthChart").rect.height, :>=, 300
    assert_operator page.all("#netWorthChart .date-axis .tick").size, :>=, 2
    fraction = page.evaluate_script <<~JS
      (() => {
        const chart = document.querySelector("#netWorthChart");
        const line = chart.querySelector("path[stroke-linejoin]");
        const overlay = chart.querySelector(".overlay");
        return line.getBBox().height / overlay.getBBox().height;
      })()
    JS
    assert_operator fraction, :>=, 0.7
    assert_operator fraction, :<=, 1

    page.current_window.resize_to(390, 844)
    assert_selector "#netWorthChart .date-axis .tick", count: 2
    assert page.evaluate_script(<<~JS)
      (() => {
        const labels = [...document.querySelectorAll("#netWorthChart .date-axis text")];
        return labels[0].getBoundingClientRect().right < labels[1].getBoundingClientRect().left;
      })()
    JS
  end

  test "dragging across the net worth chart navigates to the dragged date range instead of reordering the card" do
    sign_in @user

    original_order = page.all("[data-section-key]").map { |el| el["data-section-key"] }

    # The net worth chart sits inside a `<section draggable="true">` used by
    # dashboard-sortable for card reordering. Without an explicit
    # `draggable="false"` on the chart container, this same gesture would be
    # hijacked by the native HTML5 drag-and-drop instead of the chart's brush.
    drag_across find("#netWorthChart .drag-select-brush .overlay", visible: :all)

    assert_current_path(%r{/\?.*start_date=.*end_date=})

    # Some sections (e.g. the outflows donut) hide themselves when the
    # selected range has no matching data — that's expected, so only assert
    # that whatever sections persist keep their relative order (i.e. nothing
    # got dragged to a new position).
    new_order = page.all("[data-section-key]").map { |el| el["data-section-key"] }
    common_keys = original_order & new_order
    assert_equal common_keys, new_order & common_keys
  end
end
