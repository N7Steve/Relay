require "application_system_test_case"

class Settings::ProvidersTest < ApplicationSystemTestCase
  setup do
    @user = users(:family_admin)
    @family = families(:dylan_family)
    @family.enable_banking_items.destroy_all
    login_as @user
  end

  test "shows status pill on section header for a configured provider" do
    create_enable_banking_connection

    visit settings_providers_path

    within("details", text: "Enable Banking") do
      assert_text "Connected"
    end
  end


  test "connected providers are grouped under Your connections in alphabetical title order" do
    create_enable_banking_connection

    visit settings_providers_path

    titles = all("details").map { |d| d.find("summary h3", match: :first).text.squish }
    assert_equal titles.sort_by(&:downcase), titles, "Connection panels should render alphabetically by title"

    connections_heading = page.find(:xpath, "//h2[contains(translate(normalize-space(), 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), 'your connections')]")
    available_heading = page.find(:xpath, "//h2[contains(translate(normalize-space(), 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), 'available')]")
    connections_y = connections_heading.native.location.y
    available_y = available_heading.native.location.y

    assert_operator connections_y, :<, page.find("details", text: "Enable Banking").native.location.y
    assert_operator page.find("details", text: "Enable Banking").native.location.y, :<, available_y
  end

  test "expanding a section still works as expected" do
    create_enable_banking_connection

    visit settings_providers_path

    section = find("details#enable_banking-connection")
    section.find("summary").click if section.matches_selector?("details[open]")
    assert_selector "details:not([open])", text: "Enable Banking"

    find("details", text: "Enable Banking").find("summary").click

    assert_selector "details[open]", text: "Enable Banking"
    within("details[open]", text: "Enable Banking") do
      assert_text "Application ID"
    end
  end

  test "groups providers into Your connections and Available with counts" do
    create_enable_banking_connection

    visit settings_providers_path

    connections_heading = find(:xpath, "//h2[contains(translate(., 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), 'your connections')]")
    normalized = connections_heading.text.squish
    assert_match(/Your connections .*· \d+/i, normalized)

    connections_y = connections_heading.native.location.y
    available_heading = find(:xpath, "//h2[contains(translate(., 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), 'available')]")
    available_y = available_heading.native.location.y
    enable_banking_y = find("details", text: "Enable Banking").native.location.y

    assert_operator connections_y, :<, enable_banking_y, "Your connections heading should appear above Enable Banking section"
    assert_operator enable_banking_y, :<, available_y, "Enable Banking should appear above Available heading"

    # Enable Banking is the only retained connector, so nothing else is available once it is connected.
    assert_text I18n.t("settings.providers.groups.empty_available")
  end

  test "action needed group is absent when no providers have issues" do
    create_enable_banking_connection

    visit settings_providers_path

    assert_selector "h2", text: /\AYour connections/i
    assert_no_selector "h2", text: /\AAction needed/i
  end

  test "enable banking with expiring session appears in your connections and auto-opens" do
    item = EnableBankingItem.new(
      family: @family,
      name: "Test Bank",
      country_code: "DE",
      application_id: "test-app-id",
      session_id: "test-session",
      session_expires_at: 5.days.from_now
    )
    # Skip certificate validation for test purposes
    item.save!(validate: false)

    visit settings_providers_path

    assert_selector "h2", text: /\AYour connections/i

    # Auto-expanded warning sections hide compact meta behind `group-open:hidden`;
    # collapse once so the re-consent copy is visible again.
    enable = find("details", text: /Enable Banking/)
    enable.find("summary").click if enable.matches_selector?(":open")

    assert_selector "details:not([open])", text: /Enable Banking/
    assert_text "Re-consent needed in 5 days"
  end

  test "search input filters provider cards by name" do
    visit settings_providers_path

    find('[data-providers-filter-target="input"]').set("Enable Banking")

    assert_selector "a[data-providers-filter-target='card']", text: /Enable Banking/i
    assert_no_selector "[data-providers-filter-target='card']", text: /Apple Wallet/i
  end


  test "search shows the empty filter message when no provider matches" do
    visit settings_providers_path

    find('[data-providers-filter-target="input"]').set("zzz_no_match_zzz")

    assert_selector '[data-providers-filter-target="empty"]', text: I18n.t("settings.providers.empty_filter")
    assert_no_selector "a[data-providers-filter-target='card']", visible: true
  end

  test "available providers render as a card grid" do
    visit settings_providers_path

    within available_provider_cards_container do
      assert_text "Enable Banking"
      assert_selector "a[data-turbo-frame='drawer']", minimum: 1
    end
  end

  test "clicking a provider card opens the connect drawer" do
    visit settings_providers_path

    within available_provider_cards_container do
      find("a[data-turbo-frame='drawer']", text: "Enable Banking").click
    end

    assert_selector "dialog[open]"
    assert_text "Application ID"
  end


  test "clear filters button resets search input and chip state" do
    visit settings_providers_path

    find('[data-providers-filter-target="input"]').set("zzz_no_match_zzz")
    assert_selector '[data-providers-filter-target="empty"]', visible: true

    click_on I18n.t("settings.providers.clear_filter")

    assert_no_selector '[data-providers-filter-target="empty"]', visible: true
    assert_equal "", find('[data-providers-filter-target="input"]').value
    assert_selector "a[data-providers-filter-target='card']", text: /Enable Banking/i
  end

  test "warn-state connection row carries warning outline class" do
    item = EnableBankingItem.new(
      family: @family,
      name: "Test Bank",
      country_code: "DE",
      application_id: "test-app-id",
      session_id: "test-session",
      session_expires_at: 5.days.from_now
    )
    item.save!(validate: false)

    visit settings_providers_path

    details = find("details", text: /Enable Banking/)
    assert_includes details[:class], "border-warning/25"
  end

  test "retired connectors do not appear in the connection catalog" do
    visit settings_providers_path
    RetiredAccountConnector::PREFIXES.each do |prefix|
      assert_no_selector "a[href*='#{prefix.underscore}_items']"
    end
    assert_no_selector "script[src*='cdn.plaid.com']", visible: :all
    page.save_screenshot(Rails.root.join("tmp/screenshots/phase7-provider-catalog.png"))
  end

  private
    def create_enable_banking_connection
      EnableBankingItem.create!(family: @family, name: "Test Bank", country_code: "ES",
        application_id: "test-app", client_certificate: "test-cert", session_id: "test-session",
        session_expires_at: 30.days.from_now)
    end

    # Card grid rendered after the `#available` group heading (following sibling div.grid)
    def available_provider_cards_container
      find("#available").find(:xpath, "following-sibling::div[contains(concat(' ', normalize-space(@class), ' '), ' grid ')]")
    end
end
