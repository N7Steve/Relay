# frozen_string_literal: true

require "test_helper"

class Api::V1::LogosControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @family = @user.family
    @user.api_keys.active.destroy_all
    @api_key = ApiKey.create!(user: @user, name: "Logo key", scopes: [ "read" ], source: "web",
      display_key: "logo_read_#{SecureRandom.hex(8)}")

    @outsider = users(:family_member)
    @outsider.update!(family: families(:empty))
    @outsider.api_keys.active.destroy_all
    @outsider_key = ApiKey.create!(user: @outsider, name: "Outsider key", scopes: [ "read" ], source: "web",
      display_key: "logo_outsider_#{SecureRandom.hex(8)}")

    @account = accounts(:depository)
    @merchant = @family.merchants.create!(name: "Logo merchant")
  end

  test "requires authentication" do
    get api_v1_account_logo_url(@account)

    assert_response :unauthorized
  end

  test "serves the small custom bank logo to token clients" do
    attach_logo(@account.custom_logo)

    get api_v1_account_logo_url(@account), headers: api_headers(@api_key)

    assert_response :success
    assert_equal "image/webp", response.media_type
    assert_operator response.body.bytesize, :positive?
  end

  test "falls back to the stored provider bank logo" do
    attach_logo(@account.logo)

    get api_v1_account_logo_url(@account), headers: api_headers(@api_key)

    assert_response :success
    assert_equal "image/png", response.media_type
  end

  test "returns not found for accounts without a stored logo or outside the family" do
    get api_v1_account_logo_url(@account), headers: api_headers(@api_key)
    assert_response :not_found

    attach_logo(@account.custom_logo)
    get api_v1_account_logo_url(@account), headers: api_headers(@outsider_key)
    assert_response :not_found

    get api_v1_account_logo_url(id: "not-a-uuid"), headers: api_headers(@api_key)
    assert_response :not_found
  end

  test "serves the family custom merchant logo only to that family" do
    customization = @family.merchant_customizations.create!(merchant: @merchant)
    attach_logo(customization.custom_logo)

    get api_v1_merchant_logo_url(@merchant), headers: api_headers(@api_key)
    assert_response :success
    assert_equal "image/webp", response.media_type

    get api_v1_merchant_logo_url(@merchant), headers: api_headers(@outsider_key)
    assert_response :not_found
  end

  test "returns not found for merchants without a custom logo" do
    get api_v1_merchant_logo_url(@merchant), headers: api_headers(@api_key)

    assert_response :not_found
  end

  private
    def attach_logo(attachment)
      file_fixture("profile_image.png").open("rb") do |image|
        attachment.attach(io: image, filename: "logo.png", content_type: "image/png")
      end
    end
end
