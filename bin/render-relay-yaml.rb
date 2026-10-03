#!/usr/bin/env ruby
# Keep the self-contained TrueNAS bootstrap updater in sync with its source.
require "pathname"

root = Pathname.new(__dir__).parent
path = root.join("compose.truenas.folder.yml")
marker = "# Generated from bin/update-relay.sh by bin/render-relay-yaml.rb.\n"
template = path.read.split(marker, 2).first
script = root.join("bin/update-relay.sh").read
content = script.lines.map { |line| line.strip.empty? ? "\n" : "      #{line.gsub('$', '$$')}" }.join
path.write(template + marker + "# Docker Compose expands $$ to a literal $ in config content.\nconfigs:\n  relay-updater:\n    content: |\n" + content)
