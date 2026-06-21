const root_dir = path self ..
const driver_source = "tools/gui_smoke_driver.swift"
const driver_output = "build/tools/gui_smoke_driver"

cd $root_dir

mkdir ([$root_dir "build" "tools"] | path join)

^swiftc $driver_source -o $driver_output
^$driver_output
