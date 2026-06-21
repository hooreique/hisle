const root_dir = path self ..
const lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

let project = ($env.PROJECT? | default "hisle.xcodeproj")
let scheme = ($env.SCHEME? | default "hisle")
let configuration = ($env.CONFIGURATION? | default "Debug")
let destination = ($env.DESTINATION? | default "generic/platform=macOS")
let build_dir = ($env.BUILD_DIR? | default ([$root_dir "build"] | path join))
let product_name = ($env.PRODUCT_NAME? | default "hisle")
let app_name = $"($product_name).app"
let install_dir = ($env.INSTALL_DIR? | default ([$env.HOME "Library" "Input Methods"] | path join))
let developer_dir = ($env.XCODE_DEVELOPER_DIR? | default "/Applications/Xcode.app/Contents/Developer")

if ($install_dir | is-empty) {
    error make { msg: "INSTALL_DIR must not be empty" }
}

hide-env -i CC CXX LD SDKROOT NIX_CC NIX_CFLAGS_COMPILE NIX_CFLAGS_LINK NIX_LDFLAGS

if ($developer_dir | path exists) {
    $env.DEVELOPER_DIR = $developer_dir
}

cd $root_dir

^/usr/bin/xcodebuild -project $project -scheme $scheme -configuration $configuration -destination $destination $"SYMROOT=($build_dir)" build

let built_app = [$build_dir $configuration $app_name] | path join
let installed_app = [$install_dir $app_name] | path join

if not ($built_app | path exists) {
    print -e $"Built app not found: ($built_app)"
    exit 1
}

mkdir $install_dir
rm --recursive --force $installed_app
^/usr/bin/ditto $built_app $installed_app

^/usr/bin/codesign --verify --deep --strict $installed_app
^$lsregister -f -R $installed_app

try {
    ^/usr/bin/killall $product_name out+err> /dev/null
} catch {
}

print $"Installed ($installed_app)"
print "Add hisle in System Settings > Keyboard > Input Sources."
