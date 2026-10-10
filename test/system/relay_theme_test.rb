require "application_system_test_case"

class RelayThemeTest < ApplicationSystemTestCase
  setup do
    user = users(:family_admin)
    user.update!(theme: "relay")
    sign_in user
    visit transactions_url
    assert_selector "html[data-theme='dark'][data-palette='relay']"
  end

  test "gradient actions have white labels and icons with readable hover contrast" do
    action = find("a.button--primary", text: "New transaction")
    assert_equal "rgb(255, 255, 255)", action.evaluate_script("getComputedStyle(this).color")
    assert_equal "rgb(255, 255, 255)", action.find("svg").evaluate_script("getComputedStyle(this).color")
    assert_gradient_contrast action
    action.hover
    assert_gradient_contrast action

    action.click
    within "dialog[open]" do
      button = find("button.button--primary", match: :first)
      button.execute_script("this.disabled = true")
      assert_equal "none", button.evaluate_script("getComputedStyle(this).backgroundImage")
      refute_equal "rgb(255, 255, 255)", button.evaluate_script("getComputedStyle(this).color")
    end
  end

  test "bulk actions stay at the viewport bottom while the page scrolls" do
    assert_bulk_actions_position width: 1400, bottom: 24
  end

  test "mobile bulk actions stay above the bottom navigation while scrolling" do
    assert_bulk_actions_position width: 390, bottom: 80
  end

  test "filter popover paints above the transaction list" do
    find("#transaction-filters-button").click
    panel = find("#transaction-filters-menu")
    assert panel.evaluate_script(<<~JS)
      (() => {
        const rect = this.getBoundingClientRect();
        const topmost = document.elementFromPoint(rect.x + rect.width / 2, rect.bottom - 10);
        return this.contains(topmost);
      })()
    JS
  end

  private

    def assert_bulk_actions_position(width:, bottom:)
      20.times do |index|
        accounts(:depository).entries.create!(
          name: "Theme scroll entry #{index}", date: Date.current - index.days,
          amount: 10, currency: "USD", entryable: Transaction.new
        )
      end
      visit transactions_url
      page.current_window.resize_to(width, 800)
      find("#toggle-checkboxes-button").click if width < 1024
      find("[data-bulk-select-target='row']", match: :first).check
      bar = find("#entry-selection-bar > div")
      assert_in_delta bottom, bar.evaluate_script("window.innerHeight - this.getBoundingClientRect().bottom"), 1
      assert bar.evaluate_script(<<~JS)
        (() => {
          const rect = this.getBoundingClientRect();
          return this.contains(document.elementFromPoint(rect.x + rect.width / 2, rect.y + rect.height / 2));
        })()
      JS
      find("#main").execute_script("this.scrollTop = this.scrollHeight")
      assert_operator find("#main").evaluate_script("this.scrollTop"), :>, 0
      assert_in_delta bottom, bar.evaluate_script("window.innerHeight - this.getBoundingClientRect().bottom"), 1
    end

    def assert_gradient_contrast(element)
      # Read the actual compiled gradient stops and let the browser convert
      # their colour space to sRGB before computing WCAG relative luminance.
      ratios = element.evaluate_script(<<~'JS')
        (() => {
          const colors = getComputedStyle(this).backgroundImage.match(/(?:oklab|color|rgb)\([^)]*\)/g);
          const canvas = document.createElement("canvas");
          canvas.width = canvas.height = 1;
          const context = canvas.getContext("2d");
          return colors.map(color => {
            context.fillStyle = color;
            context.fillRect(0, 0, 1, 1);
            const rgb = Array.from(context.getImageData(0, 0, 1, 1).data).slice(0, 3).map(value => {
              const channel = value / 255;
              return channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
            });
            return 1.05 / (0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2] + 0.05);
          });
        })()
      JS
      assert_equal 2, ratios.length
      ratios.each { |ratio| assert_operator ratio, :>=, 4.5 }
    end
end
