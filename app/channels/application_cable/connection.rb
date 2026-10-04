module ApplicationCable
  class Connection < ActionCable::Connection::Base
    rescue_from StandardError, with: :report_error

    private
      def report_error(e)
        LocalDiagnostics.report(e, source: "channels/application_cable/connection")
      end
  end
end
