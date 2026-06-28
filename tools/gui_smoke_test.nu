const root_dir = path self ..
const support_source = "tools/GuiTestSupport.swift"
const driver_source = "tools/gui_smoke_driver.swift"
const driver_output = "build/tools/gui_smoke_driver"

cd $root_dir

mkdir ([$root_dir "build" "tools"] | path join)

hide-env -i CC CXX LD SDKROOT NIX_CC NIX_CFLAGS_COMPILE NIX_CFLAGS_LINK NIX_LDFLAGS
^/usr/bin/xcrun swiftc $support_source $driver_source -o $driver_output
^$driver_output
