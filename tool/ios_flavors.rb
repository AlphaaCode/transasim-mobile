# Wires every brand under brands/ into the iOS project as a Flutter flavor:
# Debug-<slug>, Release-<slug> and Profile-<slug> build configurations based on
# ios/Flutter/<slug>.xcconfig, the brand's asset catalog in the Runner target,
# and a shared "<slug>" scheme. The iOS counterpart of a productFlavor in
# android/app/build.gradle.kts.
#
# Idempotent: run it again after adding a brand and only what is missing is
# added. Needs a Mac and the xcodeproj gem, which ships with CocoaPods:
#
#   ruby tool/ios_flavors.rb
#
# A new brand needs, before running it: ios/Flutter/<slug>.xcconfig and
# ios/Runner/Brands/Brand-<slug>.xcassets (copy an existing brand's, then change
# every value). test/core/brand_wiring_test.dart says what is still missing.
require 'xcodeproj'
require 'fileutils'

ROOT = File.expand_path('..', __dir__)
IOS = File.join(ROOT, 'ios')
BUILD_TYPES = %w[Debug Release Profile].freeze
# Base configuration each build type copies. Flutter's template has no
# Profile.xcconfig; its Profile is a Release build with the profile engine.
SCHEME_ACTIONS = {
  'TestAction' => 'Debug', 'LaunchAction' => 'Debug', 'ProfileAction' => 'Profile',
  'AnalyzeAction' => 'Debug', 'ArchiveAction' => 'Release'
}.freeze

slugs = Dir.children(File.join(ROOT, 'brands'))
           .select { |d| File.directory?(File.join(ROOT, 'brands', d)) }.sort
project = Xcodeproj::Project.open(File.join(IOS, 'Runner.xcodeproj'))
runner = project.targets.find { |t| t.name == 'Runner' }
flutter_group = project.main_group.children.find { |g| g.display_name == 'Flutter' }
runner_group = project.main_group.children.find { |g| g.display_name == 'Runner' }
brands_group = runner_group.children.find { |g| g.display_name == 'Brands' } ||
               runner_group.new_group('Brands', 'Brands')

# Socle settings every Runner configuration shares, flavored or not.
runner.build_configurations.each do |c|
  c.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
  c.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  # No brand's catalog unless the brand's xcconfig names it in
  # INCLUDED_SOURCE_FILE_NAMES: an unflavored build has no icon and fails,
  # instead of shipping one client's icon under another's name.
  c.build_settings['EXCLUDED_SOURCE_FILE_NAMES'] = 'Brand-*.xcassets'
end
unless runner_group.files.any? { |f| f.path == 'Runner.entitlements' }
  runner_group.new_reference('Runner.entitlements')
end

slugs.each do |slug|
  xcconfig = "Flutter/#{slug}.xcconfig"
  catalog = "Brand-#{slug}.xcassets"
  [xcconfig, "Runner/Brands/#{catalog}"].each do |f|
    abort "missing ios/#{f} for brand #{slug}" unless File.exist?(File.join(IOS, f))
  end

  xcconfig_ref = flutter_group.files.find { |f| f.path == xcconfig } ||
                 flutter_group.new_reference(xcconfig)
  unless brands_group.files.any? { |f| f.path == catalog }
    runner.resources_build_phase.add_file_reference(brands_group.new_reference(catalog))
  end

  BUILD_TYPES.each do |type|
    name = "#{type}-#{slug}"
    [project, *project.targets].each do |owner|
      list = owner.build_configuration_list
      next if list[name]

      base = list[type]
      copy = project.new(Xcodeproj::Project::Object::XCBuildConfiguration)
      copy.name = name
      copy.build_settings = Marshal.load(Marshal.dump(base.build_settings))
      copy.base_configuration_reference = base.base_configuration_reference
      list.build_configurations << copy
    end
    flavored = runner.build_configuration_list[name]
    flavored.base_configuration_reference = xcconfig_ref
    # A target-level value would override the xcconfig's.
    flavored.build_settings.delete('PRODUCT_BUNDLE_IDENTIFIER')
    flavored.build_settings.delete('DEVELOPMENT_TEAM')
  end

  scheme_path = File.join(Xcodeproj::XCScheme.shared_data_dir(project.path), "#{slug}.xcscheme")
  next if File.exist?(scheme_path)

  # A copy of Runner's, so the Flutter "prepare" pre-action and the LLDB init
  # file come with it; only the configurations change.
  scheme = Xcodeproj::XCScheme.new(File.join(Xcodeproj::XCScheme.shared_data_dir(project.path), 'Runner.xcscheme'))
  SCHEME_ACTIONS.each do |action, type|
    scheme.doc.root.elements[action].attributes['buildConfiguration'] = "#{type}-#{slug}"
  end
  scheme.save_as(project.path, slug, true)
end

project.save
puts "iOS flavors: #{slugs.join(', ')}"
