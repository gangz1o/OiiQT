require 'xcodeproj'

project_path = '/Users/gangz1o/ios-app/OiiQT/OiiQT.xcodeproj'
file_path = 'OiiQT/utils/NetworkManager.swift'
group_path = 'OiiQT/utils'

project = Xcodeproj::Project.open(project_path)

# Find or create strict group structure
# "OiiQT" group -> "utils" group
main_group = project.main_group
seed_pilot_group = main_group.find_subpath('OiiQT', false)

if seed_pilot_group
  utils_group = seed_pilot_group.find_subpath('utils', true) # Create if not exists
  
  # Check if file ref exists
  file_ref = utils_group.files.find { |f| f.path == 'NetworkManager.swift' }
  unless file_ref
    file_ref = utils_group.new_file('NetworkManager.swift')
  end

  # Add to target
  target = project.targets.first
  unless target.source_build_phase.files_references.include?(file_ref)
    target.add_file_references([file_ref])
  end

  project.save
  puts "Added NetworkManager.swift to project."
else
  puts "Error: Could not find OiiQT group."
end
