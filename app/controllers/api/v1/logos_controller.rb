# frozen_string_literal: true

# Active Storage serves stored logos only to a web session. Token clients such
# as the Android app read the same images here, under the API's own access rules.
class Api::V1::LogosController < Api::V1::BaseController
  CONTENT_TYPES = CustomLogoAttachable::ALLOWED_CUSTOM_LOGO_CONTENT_TYPES
  MAX_BYTES = 1.megabyte

  before_action -> { authorize_scope!(:read) }
  before_action -> { raise ActiveRecord::RecordNotFound unless valid_uuid?(params[:id]) }

  def account
    account = current_resource_owner.family.accounts.accessible_by(current_resource_owner).find(params[:id])
    return serve_small(account.custom_logo) if account.custom_logo.attached?

    serve(account.logo.attached? ? account.logo.blob : nil)
  end

  def merchant
    customization = current_resource_owner.family.merchant_customizations.find_by!(merchant_id: params[:id])
    serve_small(customization.custom_logo)
  end

  # Profile pictures of the family's members, shown next to their transfers.
  def user
    member = current_resource_owner.family.users.find(params[:id])
    serve_small(member.profile_image)
  end

  private
    def serve_small(attachment)
      raise ActiveRecord::RecordNotFound unless attachment.attached? && attachment.content_type.in?(CONTENT_TYPES)

      serve(attachment.variant(:small).processed.image.blob)
    end

    def serve(blob)
      raise ActiveRecord::RecordNotFound unless blob && blob.content_type.in?(CONTENT_TYPES) && blob.byte_size <= MAX_BYTES

      send_data blob.download, type: blob.content_type, disposition: "inline"
    rescue ActiveStorage::FileNotFoundError
      raise ActiveRecord::RecordNotFound
    end
end
