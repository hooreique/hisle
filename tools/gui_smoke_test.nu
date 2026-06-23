const root_dir = path self ..
const support_source = "tools/GuiTestSupport.swift"
const driver_source = "tools/gui_smoke_driver.swift"
const driver_output = "build/tools/gui_smoke_driver"

cd $root_dir

mkdir ([$root_dir "build" "tools"] | path join)

^swiftc $support_source $driver_source -o $driver_output
^$driver_output
