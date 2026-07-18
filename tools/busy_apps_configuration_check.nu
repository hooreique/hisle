const root_dir = path self ..
const configuration_source = "hisle/App/BusyAppsSnapshot.swift"
const check_source = "tools/busy_apps_configuration_check.swift"
const check_output = "build/tools/busy_apps_configuration_check"

cd $root_dir

mkdir ([$root_dir "build" "tools"] | path join)

hide-env -i CC CXX LD SDKROOT NIX_CC NIX_CFLAGS_COMPILE NIX_CFLAGS_LINK NIX_LDFLAGS
^/usr/bin/xcrun swiftc $configuration_source $check_source -o $check_output
^$check_output
