# Load after the canonical relay tasks. Prerequisites forward the named arguments
# and keep Rake's once-per-invocation behavior when both names are requested.
Rake::Task.tasks.select { |task| task.name.start_with?("relay:") }.each do |relay_task|
  desc "Compatibility alias for #{relay_task.name}"
  task relay_task.name.sub(/\Arelay:/, "sure:"), relay_task.arg_names => [ relay_task.name ]
end
