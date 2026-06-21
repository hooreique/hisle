const root_dir = path self ..

let project = ($env.PROJECT? | default "hisle.xcodeproj")
let scheme = ($env.SCHEME? | default "hisle")
let configuration = ($env.CONFIGURATION? | default "Debug")
let destination = ($env.DESTINATION? | default "generic/platform=macOS")
let build_dir = ($env.BUILD_DIR? | default ([$root_dir "build"] | path join))
let product_name = ($env.PRODUCT_NAME? | default "hisle")
let app_name = $"($product_name).app"
let package_dir = ($env.PACKAGE_DIR? | default ([$build_dir "dist"] | path join))
let staging_dir = [$build_dir "package" $"($product_name)-dmg"] | path join
let developer_dir = ($env.XCODE_DEVELOPER_DIR? | default "/Applications/Xcode.app/Contents/Developer")

let volume_name_env = ($env.DMG_VOLUME_NAME? | default "")
let volume_name = if ($volume_name_env | is-empty) {
    $product_name
} else {
    $volume_name_env
}

hide-env -i CC CXX LD SDKROOT NIX_CC NIX_CFLAGS_COMPILE NIX_CFLAGS_LINK NIX_LDFLAGS

if ($developer_dir | path exists) {
    $env.DEVELOPER_DIR = $developer_dir
}

let code_sign_style = ($env.CODE_SIGN_STYLE? | default "")
let code_sign_identity = ($env.CODE_SIGN_IDENTITY? | default "")
let development_team = ($env.DEVELOPMENT_TEAM? | default "")
let other_code_sign_flags = ($env.OTHER_CODE_SIGN_FLAGS? | default "")
let xcode_build_settings = [$"SYMROOT=($build_dir)"]
let xcode_build_settings = if ($code_sign_style | is-empty) {
    $xcode_build_settings
} else {
    $xcode_build_settings | append $"CODE_SIGN_STYLE=($code_sign_style)"
}
let xcode_build_settings = if ($code_sign_identity | is-empty) {
    $xcode_build_settings
} else {
    $xcode_build_settings | append $"CODE_SIGN_IDENTITY=($code_sign_identity)"
}
let xcode_build_settings = if ($development_team | is-empty) {
    $xcode_build_settings
} else {
    $xcode_build_settings | append $"DEVELOPMENT_TEAM=($development_team)"
}
let xcode_build_settings = if ($other_code_sign_flags | is-empty) {
    $xcode_build_settings
} else {
    $xcode_build_settings | append $"OTHER_CODE_SIGN_FLAGS=($other_code_sign_flags)"
}

cd $root_dir

^/usr/bin/xcodebuild -project $project -scheme $scheme -configuration $configuration -destination $destination ...$xcode_build_settings build

let built_app = [$build_dir $configuration $app_name] | path join

if not ($built_app | path exists) {
    print -e $"Built app not found: ($built_app)"
    exit 1
}

^/usr/bin/codesign --verify --deep --strict $built_app

let info_plist = [$built_app "Contents" "Info.plist"] | path join
let marketing_version = if ($info_plist | path exists) {
    ^/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" $info_plist | str trim
} else {
    "unknown"
}

let default_dmg_name = if $configuration == "Release" {
    $"($product_name)-($marketing_version).dmg"
} else {
    $"($product_name)-($marketing_version)-($configuration).dmg"
}

let dmg_name_env = ($env.DMG_NAME? | default "")
let dmg_name = if ($dmg_name_env | is-empty) {
    $default_dmg_name
} else {
    $dmg_name_env
}

let dmg_path = [$package_dir $dmg_name] | path join

rm --recursive --force $staging_dir
mkdir $staging_dir
mkdir $package_dir

^/usr/bin/ditto $built_app ([$staging_dir $app_name] | path join)

let install_note = $"Install hisle

Copy ($app_name) to:

    ~/Library/Input Methods

Then open System Settings > Keyboard, add hisle as an input source, and select it from the input menu.

Terminal equivalent:

    mkdir -p \"$HOME/Library/Input Methods\"
    ditto \"/Volumes/($volume_name)/($app_name)\" \"$HOME/Library/Input Methods/($app_name)\"

Remove:

    rm -rf \"$HOME/Library/Input Methods/($app_name)\"
"

$install_note | save --force ([$staging_dir "Install.txt"] | path join)

rm --force $dmg_path

^/usr/bin/hdiutil create -volname $volume_name -srcfolder $staging_dir -ov -format UDZO $dmg_path

let dmg_sign_identity = ($env.DMG_SIGN_IDENTITY? | default "")
if not ($dmg_sign_identity | is-empty) {
    ^/usr/bin/codesign --force --sign $dmg_sign_identity --timestamp $dmg_path
    ^/usr/bin/codesign --verify --verbose=4 $dmg_path
}

^/usr/bin/hdiutil verify $dmg_path

print $"Packaged ($dmg_path)"
