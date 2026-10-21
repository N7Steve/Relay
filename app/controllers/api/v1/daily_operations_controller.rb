# frozen_string_literal: true

class Api::V1::DailyOperationsController < Api::V1::BaseController
  def create
    arguments = params.fetch(:arguments, ActionController::Parameters.new)
    raise Api::Input::Invalid, "arguments must be an object" unless arguments.is_a?(ActionController::Parameters)

    render json: Api::DailyOperations.new(access: api_access).call(
      request.path_parameters.fetch(:operation), arguments.to_unsafe_h
    )
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => error
    render_validation_error(error.record.errors.full_messages.join(", ").presence || error.message)
  end
end
