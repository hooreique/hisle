def require [condition: bool, message: string] {
    if not $condition {
        error make { msg: $message }
    }
}

const root_dir = path self ..

cd $root_dir

let configuration = ($env.CONFIGURATION? | default "Debug")
let build_dir = ($env.BUILD_DIR? | default ([$root_dir "build"] | path join))
let cli = [$build_dir $configuration "hisle.app" "Contents" "Helpers" "hisle"] | path join

require ($cli | path exists) $"Built hisle CLI is missing: ($cli)"

let temporary_template = [($env.TMPDIR? | default "/tmp") "hisle-cli-check.XXXXXX"] | path join
let temporary_root = ^/usr/bin/mktemp -d $temporary_template | str trim

try {
    let xdg_root = [$temporary_root "xdg"] | path join
    let home_root = [$temporary_root "home"] | path join
    let xdg_file = [$xdg_root "hisle" "busy-apps.txt"] | path join
    let home_file = [$home_root ".config" "hisle" "busy-apps.txt"] | path join

    let first_init = with-env { XDG_CONFIG_HOME: $xdg_root, HOME: $home_root } {
        do { ^$cli init } | complete
    }
    require ($first_init.exit_code == 0) $"XDG init failed: ($first_init.stderr | str trim)"
    require ($first_init.stdout == $"($xdg_file)\n") "XDG init path output was not exact"
    require ($first_init.stderr | is-empty) "XDG init wrote unexpected stderr"
    require ($xdg_file | path exists) "XDG init did not create busy-apps.txt"
    require ((^/usr/bin/stat -f '%z' $xdg_file | str trim) == "0") "XDG init file was not empty"

    "com.example.Existing\n" | save --force $xdg_file
    let repeated_init = with-env { XDG_CONFIG_HOME: $xdg_root, HOME: $home_root } {
        do { ^$cli init } | complete
    }
    require ($repeated_init.exit_code == 0) $"repeated init failed: ($repeated_init.stderr | str trim)"
    require ($repeated_init.stdout == $"($xdg_file)\n") "repeated init path output changed"
    require ((open --raw $xdg_file) == "com.example.Existing\n") "repeated init changed existing contents"

    let home_init = with-env { XDG_CONFIG_HOME: "", HOME: $home_root } {
        do { ^$cli init } | complete
    }
    require ($home_init.exit_code == 0) $"HOME init failed: ($home_init.stderr | str trim)"
    require ($home_init.stdout == $"($home_file)\n") "HOME init path output was not exact"
    require ($home_file | path exists) "HOME init did not create busy-apps.txt"

    let collision_root = [$temporary_root "collision"] | path join
    let collision_file = [$collision_root "hisle" "busy-apps.txt"] | path join
    mkdir $collision_file
    let collision_init = with-env { XDG_CONFIG_HOME: $collision_root, HOME: $home_root } {
        do { ^$cli init } | complete
    }
    require ($collision_init.exit_code == 73) "destination collision did not exit with status 73"
    require ($collision_init.stdout | is-empty) "destination collision wrote unexpected stdout"
    require (
        $collision_init.stderr | str contains $"hisle: could not initialize busy apps configuration at ($collision_file):"
    ) "destination collision stderr omitted the resolved path"

    let mode = do { ^$cli } | complete
    require ($mode.exit_code == 0) "no-argument mode command failed"
    require (($mode.stdout | str trim) in ["roman" "hangul"]) "no-argument mode output changed"

    let version = do { ^$cli --version } | complete
    let version_lines = $version.stdout | lines
    require ($version.exit_code == 0) "--version command failed"
    require (($version_lines | length) == 2) "--version output no longer has two lines"
    require (($version_lines | first) | str starts-with "hisle ") "--version lost the app version line"
    require (($version_lines | last) | str starts-with "hisle-core ") "--version lost the core version line"

    let help = do { ^$cli --help } | complete
    require ($help.exit_code == 0) "--help command failed"
    require ($help.stdout | str contains "init creates busy-apps.txt if missing and prints its path.") "help omitted init"
} finally {
    rm --recursive --force $temporary_root
}

print "hisle CLI check passed init, mode, version, and help contracts."
