# Historical queued extraction stops locally; original PDF and extracted rows stay intact.
class ProcessPdfJob < ApplicationJob
  queue_as :medium_priority

  def perform(pdf_import)
    return unless pdf_import.is_a?(PdfImport)

    pdf_import.with_lock do
      if pdf_import.importing? && pdf_import.rows_count.zero?
        pdf_import.update!(status: :failed, error: I18n.t("imports.pdf_import.ai_retired"))
      end
    end
  end
end
