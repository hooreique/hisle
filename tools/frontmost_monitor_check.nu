const root_dir = path self ..
const monitor_source = "hisle-cli/FrontmostApplicationMonitor.swift"
const check_source = "tools/frontmost_monitor_check.swift"
const check_output = "build/tools/frontmost_monitor_check"

cd $root_dir

mkdir ([$root_dir "build" "tools"] | path join)

hide-env -i CC CXX LD SDKROOT NIX_CC NIX_CFLAGS_COMPILE NIX_CFLAGS_LINK NIX_LDFLAGS
^/usr/bin/xcrun swiftc $monitor_source $check_source -o $check_output
^$check_output
