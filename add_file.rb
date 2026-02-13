require 'xcodeproj'

project_path = '/Users/gangz1o/ios-app/SeedPilot/SeedPilot.xcodeproj'
file_path = 'SeedPilot/models/QBittorrentClient.swift'
group_path = 'SeedPilot/models'

project = Xcodeproj::Project.open(project_path)

# Find the group
group = project.main_group.find_subpath(group_path, false)
unless group
  puts "Creating group #{group_path}"
  group = project.main_group.new_group('models', 'SeedPilot/models')
end

# Check if file already exists in group
file_ref = group.files.find { |f| f.path == 'QBittorrentClient.swift' }
unless file_ref
  file_ref = group.new_file('QBittorrentClient.swift')
  puts "Added file reference to group"
end

# Add to target
target = project.targets.first
unless target
  puts "No target found"
  exit 1
end

# Add to build sources
unless target.source_build_phase.files_references.include?(file_ref)
  target.source_build_phase.add_file_reference(file_ref)
  puts "Added file to target #{target.name}"
end

project.save
puts "Project saved"
