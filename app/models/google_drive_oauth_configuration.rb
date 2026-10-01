class GoogleDriveOauthConfiguration < ApplicationRecord
  include Encryptable

  belongs_to :family
  belongs_to :user

  encrypts :client_id if encryption_ready?
  encrypts :client_secret if encryption_ready?

  validates :client_id, :client_secret, presence: true
  validates :user_id, uniqueness: true
  validate :user_belongs_to_family

  after_save :require_reauthorization, if: :saved_change_to_oauth_credentials?

  def update_credentials(attributes)
    assign_attributes(client_id: attributes[:client_id])
    self.client_secret = attributes[:client_secret] if attributes[:client_secret].present?
    save
  end

  private
    def saved_change_to_oauth_credentials?
      saved_change_to_client_id? || saved_change_to_client_secret?
    end

    def require_reauthorization
      connection = user.google_drive_connection
      return unless connection

      connection.update_columns(status: "requires_reauthorization", updated_at: Time.current)
      connection.export_schedules.where(status: "active").update_all(
        status: "needs_attention",
        last_error_code: "reauthorization_required",
        updated_at: Time.current
      )
    end

    def user_belongs_to_family
      errors.add(:user, :invalid) if user.present? && family_id.present? && user.family_id != family_id
    end
end
