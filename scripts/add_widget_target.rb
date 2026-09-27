# Adds (or repairs) the StreakWidget WidgetKit extension target in ios/Runner.xcodeproj.
#
#   ruby scripts/add_widget_target.rb
#
# Idempotent by construction: it finds or creates the target and then applies every setting,
# the embed phase and the phase order unconditionally. Re-running it is how you fix a project
# that an earlier version of this script got wrong.
#
# **Why a script rather than a hand-edited pbxproj.** Adding an app extension touches a
# PBXNativeTarget, three XCBuildConfigurations, a sources phase, a frameworks phase, a
# PBXContainerItemProxy, a PBXTargetDependency, an embed-extensions copy phase on Runner, and a
# handful of PBXFileReferences and groups -- every one keyed by a 24-character hex UUID. Done by
# hand that is an enormous diff nobody can review and nobody can reproduce. Done here it is a
# program you can read, and `xcodeproj` (already installed; CocoaPods depends on it) makes the
# UUIDs.
#
# Two things here were learned the hard way, from a build failure and a crash. Both are worth
# reading before changing anything:
#
#   1. The embed phase must run *before* Flutter's `Thin Binary` script, or the build dies in a
#      dependency cycle. See hoist_above_thin_binary.
#   2. The base configuration must be `Generated.xcconfig` and NOT Flutter's `Debug.xcconfig` /
#      `Release.xcconfig`. See BASE_CONFIG.

require "xcodeproj"

PROJECT = "ios/Runner.xcodeproj"
TARGET_NAME = "StreakWidget"
BUNDLE_ID = "com.unicorn.bookwormFriends.StreakWidget"
TEAM = "58P4CVB7L8"
DEPLOYMENT = "15.0"

# Flutter's *generated* xcconfig, deliberately, and not Debug/Release.xcconfig.
#
# **Choosing the wrong one of these crashes the widget at launch, silently.** Flutter's
# Debug.xcconfig opens with
#
#   #include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.debug.xcconfig"
#
# so basing the extension on it hands the extension every one of Runner's pod linker flags. The
# appex then links app_tracking_transparency, flutter_local_notifications and the rest, while
# those frameworks are embedded in `Runner.app/Frameworks` where an appex's @rpath cannot reach
# them. dyld kills the extension at launch with "Library not loaded", WidgetKit quietly drops it,
# and the only symptom is that the widget never appears in the gallery -- no build error, and
# `pluginkit` still lists it as registered.
#
# Generated.xcconfig carries FLUTTER_BUILD_NAME and FLUTTER_BUILD_NUMBER (which is what lets
# Info.plist read the version out of pubspec.yaml instead of holding a second copy) and no
# linker flags whatsoever, which is exactly the set this target wants.
BASE_CONFIG = "Flutter/Generated.xcconfig".freeze

# Moves the embed phase in front of Flutter's Thin Binary script.
#
# **Without this the build fails with "Cycle inside Runner".** Thin Binary runs
# xcode_backend.sh against the built Runner.app, and Xcode infers the whole bundle directory as
# its input. An embed phase appended after it writes Runner.app/PlugIns/StreakWidget.appex into
# that same directory, so the script depends on the bundle and the bundle depends on the script.
# Xcode reports this as a raw cycle trace naming neither phase, which is why the reason lives
# here rather than being rediscovered.
def hoist_above_thin_binary(runner, phase)
  thin = runner.build_phases.index { |p| p.display_name == "Thin Binary" }
  return if thin.nil?

  current = runner.build_phases.index(phase)
  return if current && current < thin

  runner.build_phases.delete(phase)
  runner.build_phases.insert(thin, phase)
end

def embed_phase(runner)
  runner.build_phases.find do |phase|
    phase.is_a?(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase) &&
      phase.display_name == "Embed App Extensions"
  end
end

def configure(project, target)
  base = project.files.find { |f| f.path&.end_with?(BASE_CONFIG) }
  raise "#{BASE_CONFIG} not found in the project; run flutter pub get" unless base

  target.build_configurations.each do |config|
    config.base_configuration_reference = base

    settings = config.build_settings
    settings["PRODUCT_BUNDLE_IDENTIFIER"] = BUNDLE_ID
    settings["PRODUCT_NAME"] = "$(TARGET_NAME)"
    settings["INFOPLIST_FILE"] = "#{TARGET_NAME}/Info.plist"
    settings["CODE_SIGN_ENTITLEMENTS"] = "#{TARGET_NAME}/#{TARGET_NAME}.entitlements"
    settings["CODE_SIGN_STYLE"] = "Automatic"
    settings["DEVELOPMENT_TEAM"] = TEAM
    settings["IPHONEOS_DEPLOYMENT_TARGET"] = DEPLOYMENT
    settings["TARGETED_DEVICE_FAMILY"] = "1,2"
    settings["SWIFT_VERSION"] = "5.0"
    settings["SKIP_INSTALL"] = "YES"
    settings["GENERATE_INFOPLIST_FILE"] = "NO"
    settings["ENABLE_USER_SCRIPT_SANDBOXING"] = "NO"
    settings["CURRENT_PROJECT_VERSION"] = "$(FLUTTER_BUILD_NUMBER)"
    settings["MARKETING_VERSION"] = "$(FLUTTER_BUILD_NAME)"
    # Belt and braces against the crash described on BASE_CONFIG: this target links SwiftUI and
    # WidgetKit and nothing else, so anything arriving in these two from an inherited pod
    # xcconfig is a bug. Stated rather than assumed, because the failure mode is invisible.
    settings["OTHER_LDFLAGS"] = ""
    settings["FRAMEWORK_SEARCH_PATHS"] = "$(inherited)"
    settings.delete("INFOPLIST_KEY_UILaunchScreen_Generation")
    settings["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone" if config.name == "Debug"
  end
end

project = Xcodeproj::Project.open(PROJECT)
runner = project.targets.find { |t| t.name == "Runner" }
raise "Runner target not found" unless runner

target = project.targets.find { |t| t.name == TARGET_NAME }
created = target.nil?

if created
  target = project.new_target(
    :app_extension,
    TARGET_NAME,
    :ios,
    DEPLOYMENT,
    project.products_group,
    :swift
  )

  # A group pointing at the real directory rather than a synthetic one, so the files appear in
  # Xcode where they actually are on disk.
  group = project.main_group.find_subpath(TARGET_NAME, true)
  group.set_source_tree("SOURCE_ROOT")
  group.set_path(TARGET_NAME)

  %w[StreakWidget.swift StreakSnapshot.swift StreakFlameGeometry.swift].each do |name|
    target.add_file_references([group.new_reference(name)])
  end
  # Not compiled, but worth being visible beside what they configure.
  %w[Info.plist StreakWidget.entitlements].each { |name| group.new_reference(name) }

  runner.add_dependency(target)
end

configure(project, target)

embed = embed_phase(runner)
unless embed
  embed = runner.new_copy_files_build_phase("Embed App Extensions")
  embed.symbol_dst_subfolder_spec = :plug_ins
end
unless embed.files_references.include?(target.product_reference)
  build_file = embed.add_file_reference(target.product_reference)
  build_file.settings = { "ATTRIBUTES" => ["RemoveHeadersOnCopy"] }
end
hoist_above_thin_binary(runner, embed)

project.save
puts created ? "Added #{TARGET_NAME} (#{BUNDLE_ID})." : "Repaired #{TARGET_NAME} configuration."
