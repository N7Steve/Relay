require "application_system_test_case"

# Regression coverage for the bug fixed alongside DS::Menu / DS::Popover's
# `fixed`-in-static-class change: a Turbo morph re-renders an open panel's
# content element back to its server-rendered (closed) state without going
# through the controller's own open/close methods. `show` used to be a plain
# instance property that a morph couldn't touch, so the next click toggled
# off an already-closed panel — swallowing the click. Deriving `show` from
# the content element's own `hidden` class (rather than tracked state) means
# it can't desync from what the DOM actually shows.
class DsOverlayMorphTest < ApplicationSystemTestCase
  setup do
    sign_in @user = users(:family_admin)
  end

  test "background morph preserves an open dialog but a successful submit releases it" do
    visit tags_url
    click_on I18n.t("tags.index.new"), match: :first
    assert_selector "#modal dialog[open]"

    assert page.evaluate_script(<<~JS)
      (() => {
        const frame = document.getElementById("modal");
        const event = new CustomEvent("turbo:before-morph-element", {
          bubbles: true, cancelable: true,
          detail: { newElement: document.createElement("turbo-frame") }
        });
        frame.dispatchEvent(event);
        return event.defaultPrevented;
      })()
    JS

    fill_in "tag_name", with: "Saved from a dialog"
    within "#modal" do
      find("[type='submit']").click
    end
    assert_no_selector "#modal dialog[open]"
    assert_text "Saved from a dialog"
  end

  test "DS::Menu reopens correctly after a morph resets it to hidden" do
    visit tags_url

    trigger = find("[aria-haspopup='menu']", match: :first)
    content_id = trigger["aria-controls"]

    trigger.click
    assert_selector "##{content_id}", visible: true
    assert_equal "true", trigger["aria-expanded"]

    simulate_morph_reset(content_id)

    trigger.click
    assert_selector "##{content_id}", visible: true
    assert_equal "true", trigger["aria-expanded"]
  end

  test "DS::Popover reopens correctly after a morph resets it to hidden" do
    visit root_url

    within_testid "user-menu" do
      trigger = find("[aria-haspopup='dialog']")
      content_id = trigger["aria-controls"]

      trigger.click
      assert_selector "##{content_id}", visible: true
      assert_equal "true", trigger["aria-expanded"]

      simulate_morph_reset(content_id)

      trigger.click
      assert_selector "##{content_id}", visible: true
      assert_equal "true", trigger["aria-expanded"]
    end
  end

  private
    # Mimics what idiomorph does to an open panel on a same-page Turbo morph:
    # the content element's class list is reconciled back to the always-hidden
    # server-rendered markup, and any inline style the controller applied
    # (position coordinates) is stripped — all without calling the Stimulus
    # controller's toggle()/close().
    def simulate_morph_reset(content_id)
      page.execute_script(<<~JS, content_id)
        const el = document.getElementById(arguments[0]);
        el.classList.add("hidden");
        el.removeAttribute("style");
      JS
    end
end
