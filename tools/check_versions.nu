const root_dir = path self ..

cd $root_dir

def fail [message: string] {
    error make { msg: $message }
}

let app_version_path = "hisle/Config/HisleVersion.xcconfig"
let core_version_path = "hisle-core/Sources/HisleCore/HisleCoreVersion.swift"
let core_root_path = "hisle-core/Sources/HisleCore/HisleCore.swift"
let project_path = "hisle.xcodeproj/project.pbxproj"

for path in [$app_version_path $core_version_path $core_root_path $project_path] {
    if not ($path | path exists) {
        fail $"Missing version check input: ($path)"
    }
}

let app_version_contents = open --raw $app_version_path
let marketing_version_lines = (
    $app_version_contents
    | lines
    | where {|line| $line =~ '^\s*MARKETING_VERSION\s*=\s*[0-9]+(\.[0-9]+){0,2}\s*$' }
)
let build_version_lines = (
    $app_version_contents
    | lines
    | where {|line| $line =~ '^\s*CURRENT_PROJECT_VERSION\s*=\s*[0-9]+\s*$' }
)

if ($marketing_version_lines | length) != 1 {
    fail $"Expected exactly one MARKETING_VERSION declaration in ($app_version_path)"
}

if ($build_version_lines | length) != 1 {
    fail $"Expected exactly one CURRENT_PROJECT_VERSION declaration in ($app_version_path)"
}

let project_contents = open --raw $project_path
if ($project_contents | str contains "MARKETING_VERSION =") {
    fail $"Move app MARKETING_VERSION declarations out of ($project_path) and into ($app_version_path)"
}

if ($project_contents | str contains "CURRENT_PROJECT_VERSION =") {
    fail $"Move app CURRENT_PROJECT_VERSION declarations out of ($project_path) and into ($app_version_path)"
}

let core_version_contents = open --raw $core_version_path
let core_version_lines = (
    $core_version_contents
    | lines
    | where {|line| $line =~ '^\s*static let version = "[^"]+"\s*$' }
)

if ($core_version_lines | length) != 1 {
    fail $"Expected exactly one HisleCore.version declaration in ($core_version_path)"
}

let core_root_contents = open --raw $core_root_path
if ($core_root_contents | str contains "version") {
    fail $"Keep HisleCore.version in ($core_version_path), not ($core_root_path)"
}

print $"App version source: ($app_version_path)"
print $"Core version source: ($core_version_path)"
