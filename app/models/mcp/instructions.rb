# frozen_string_literal: true

class Mcp::Instructions
  def self.text
    File.read(Rails.root.join("config/mcp/instructions.md"), encoding: "UTF-8")
  end
end
