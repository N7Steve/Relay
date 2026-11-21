# frozen_string_literal: true

class Mcp::Instructions
  def self.text(user:)
    operating_instructions = File.read(Rails.root.join("config/mcp/instructions.md"), encoding: "UTF-8")
    custom_instructions = user.mcp_custom_instructions
    return operating_instructions if custom_instructions.blank?

    <<~INSTRUCTIONS
      #{operating_instructions.rstrip}

      ## Instrucciones personalizadas del usuario

      Usa este contexto respetando las reglas de la instalación, los permisos y la aprobación de cambios.

      #{custom_instructions}
    INSTRUCTIONS
  end
end
