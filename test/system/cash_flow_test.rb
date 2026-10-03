require "application_system_test_case"

class CashFlowTest < ApplicationSystemTestCase
  include EntriesTestHelper

  setup do
    @user = users(:family_admin)
    @month = Date.current.beginning_of_month
    @user.update!(preferences: @user.preferences.merge("preview_features_enabled" => true))
    parent = @user.family.categories.create!(name: "Sankey Shopping", color: "#123456")
    child = @user.family.categories.create!(name: "Sankey Groceries", parent: parent)
    account = @user.family.accounts.create!(name: "Sankey checking", currency: "USD", balance: 0, accountable: Depository.new)
    create_transaction(account: account, category: parent, amount: 100, date: @month)
    create_transaction(account: account, category: child, amount: 50, date: @month)
  end

  test "loads the dashboard graph, expands, zooms, and preserves transaction date filters" do
    sign_in @user
    visit root_path(start_date: @month.iso8601, end_date: Date.current.iso8601)
    chart = find("#cashflow-preview [data-preview-sankey-chart-target='chart']", match: :first)
    assert_selector "#cashflow-preview svg .sankey-link"
    assert page.evaluate_script("performance.getEntriesByType('resource').some(e => e.name.includes('/dashboard/cash_flow?'))")
    within "#cashflow-preview" do
      click_button "Expand", enable_aria_label: true
    end
    within "#cashflow-preview-expanded-dialog" do
      assert_selector "svg .sankey-link"
    end
    gradients = page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll('#cashflow-preview linearGradient')).map(g => g.id)
    JS
    assert_selector "#cashflow-preview [data-preview-sankey-chart-target='chart'] svg", count: 2
    assert gradients.any?
    assert_equal gradients.uniq, gradients
    assert page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll('#cashflow-preview .sankey-link')).every(link => {
        const id = link.getAttribute('stroke').slice(5, -1);
        return link.ownerSVGElement.querySelector(`[id="${id}"]`);
      })
    JS
    page.execute_script("document.querySelector('#cashflow-preview-expanded-dialog').close()")
    parent = chart.find("svg text", text: "Sankey Shopping", match: :first)
    parent.find(:xpath, "..").find("path").click
    assert_selector "[data-preview-sankey-chart-target='zoomOutButton']:not([hidden])"
    find("[data-preview-sankey-chart-target='zoomOutButton']", match: :first).click
    chart.find("svg text", text: "Sankey Groceries", match: :first).find(:xpath, "..").find("path").click
    assert_current_path(%r{/transactions\?})
    query = Rack::Utils.parse_nested_query(URI.parse(page.current_url).query)
    assert_equal [ "Sankey Groceries" ], query.dig("q", "categories")
    assert_equal @month.iso8601, query.dig("q", "start_date")
    assert_equal Date.current.iso8601, query.dig("q", "end_date")
  end

  test "bars labels Enter and Space share zoom and transaction actions" do
    sign_in @user
    [ :bar, :label, :enter, :space ].each do |activation|
      visit root_path(start_date: @month.iso8601, end_date: Date.current.iso8601)
      chart = find("#cashflow-preview [data-preview-sankey-chart-target='chart']", match: :first)
      parent = chart.find("g[role='button'][tabindex='0'][aria-label^='Sankey Shopping,']")
      activate_node(parent, activation)
      assert_selector "[data-preview-sankey-chart-target='zoomOutButton']:not([hidden])"
      assert_selector "g[aria-label^='Sankey Shopping,']:focus" if [ :enter, :space ].include?(activation)
      assert_equal "false", find("[data-section-key='cashflow_sankey']")["aria-grabbed"]
      find("[data-preview-sankey-chart-target='zoomOutButton']", match: :first).send_keys(:enter)
      assert_selector "g[aria-label^='Sankey Shopping,']:focus"
      leaf = chart.find("g[role='link'][tabindex='0'][aria-label^='Sankey Groceries,']")
      activate_node(leaf, activation)
      assert_current_path(%r{/transactions\?})
      query = Rack::Utils.parse_nested_query(URI.parse(page.current_url).query)
      assert_equal [ "Sankey Groceries" ], query.dig("q", "categories")
      assert_equal @month.iso8601, query.dig("q", "start_date")
      assert_equal Date.current.iso8601, query.dig("q", "end_date")
    end
  end

  test "closing the expanded chart returns focus to Expand after keyboard zoom" do
    sign_in @user
    [ :escape, :close_button ].each do |closing|
      visit root_path(start_date: @month.iso8601, end_date: Date.current.iso8601)
      expand = find("#cashflow-preview [data-sankey-preview-target='expandButton']")
      expand.send_keys(:enter)
      within "#cashflow-preview-expanded-dialog[open]" do
        find("g[role='button'][aria-label^='Sankey Shopping,']").send_keys(:enter)
        assert_selector "g[aria-label^='Sankey Shopping,']:focus"
        if closing == :escape
          find("g:focus").send_keys(:escape)
        else
          find("button[data-action='DS--dialog#close']").click
        end
      end
      assert_no_selector "#cashflow-preview-expanded-dialog[open]"
      assert_selector "#cashflow-preview [data-sankey-preview-target='expandButton']:focus"
      assert_selector "[data-section-key='cashflow_sankey'][draggable='true']"
    end
  end

  test "spending without income renders the deficit cash flow expense path" do
    date = Date.new(2001, 2, 1)
    category = @user.family.categories.find_by!(name: "Sankey Shopping")
    account = @user.family.accounts.find_by!(name: "Sankey checking")
    create_transaction(account: account, category: category, amount: 160, date: date)
    sign_in @user
    visit root_path(start_date: date.iso8601, end_date: date.iso8601)
    chart = find("#cashflow-preview [data-preview-sankey-chart-target='chart']", match: :first)
    [ "Deficit", "Cash Flow", "Sankey Shopping" ].each do |name|
      assert_selector "#cashflow-preview g[aria-label='#{name}, $160.00']"
    end
    links = chart.all(".sankey-link").map do |link|
      assert link["d"].present?
      link.evaluate_script("[this.__data__.source.id, this.__data__.target.id, this.__data__.value]")
    end
    assert_equal [
      [ "cash_flow_node", "expense_#{category.id}", 160 ],
      [ "deficit_node", "cash_flow_node", 160 ]
    ].sort, links.sort
  end

  test "preview structural labels and tooltips use the user locale" do
    @user.update!(locale: "es")
    sign_in @user
    chart = find("#cashflow-preview [data-preview-sankey-chart-target='chart']", match: :first)
    assert_selector "#cashflow-preview svg text", text: "Flujo de caja"
    assert_selector "#cashflow-preview svg text", text: "Déficit"
    chart.find("svg text", text: "Déficit", match: :first).hover
    assert_selector ".chart-tooltip.ph-no-capture", text: "Déficit"
    assert_selector "#cashflow-preview svg text", text: "Sankey Groceries"
    account = @user.family.accounts.find_by!(name: "Sankey checking")
    create_transaction(account: account, amount: -1000, date: @month)
    visit root_path(start_date: @month.iso8601, end_date: Date.current.iso8601)
    assert_selector "#cashflow-preview svg text", text: "Superávit"
  end

  test "failed load can retry and an empty range clears old chart data" do
    sign_in @user
    assert_selector "#cashflow-preview svg .sankey-link"
    page.execute_script(<<~JS)
      window.originalCashFlowFetch = window.fetch;
      window.fetch = (url, options) => String(url).includes('/dashboard/cash_flow')
        ? Promise.resolve(new Response('{}', {status: 503})) : window.originalCashFlowFetch(url, options);
      document.querySelector('[data-action="cash-flow#load"]').click();
    JS
    assert_selector "[data-cash-flow-target='error']:not([hidden])"
    assert_selector "#cashflow-sankey-chart svg .sankey-link"
    assert_no_selector "[data-preview-sankey-chart-target='chart'] svg"
    page.execute_script("window.fetch = window.originalCashFlowFetch")
    within "[data-cash-flow-target='error']" do
      click_button "Try again"
    end
    assert_selector "#cashflow-preview svg .sankey-link"
    visit root_path(start_date: "1900-01-01", end_date: "1900-01-02")
    assert_selector "[data-cash-flow-target='empty']:not([hidden])"
    assert_no_selector "#cashflow-sankey-chart svg .sankey-link"
    assert_no_selector "[data-preview-sankey-chart-target='chart'] svg"
  end

  test "preview navigation and expansion never call an injected analytics client" do
    sign_in @user
    visit root_path(start_date: @month.iso8601, end_date: Date.current.iso8601)
    assert_selector "#cashflow-preview svg .sankey-link"
    assert_no_selector "#cashflow-preview-feedback-dialog"
    assert_no_selector "[data-action='sankey-preview#feedback']"
    page.execute_script("window.relayTelemetryCalls = []; window.posthog = { capture: (...args) => window.relayTelemetryCalls.push(args), init: (...args) => window.relayTelemetryCalls.push(args) };")
    within "#cashflow-preview" do
      click_button "Expand", enable_aria_label: true
    end
    assert_selector "#cashflow-preview-expanded-dialog svg .sankey-link"
    assert_equal [], page.evaluate_script("window.relayTelemetryCalls")
  end

  private
    def activate_node(node, activation)
      case activation
      when :bar then node.find("path").click
      when :label then node.find("text", match: :first).click
      else node.send_keys(activation)
      end
    end
end
