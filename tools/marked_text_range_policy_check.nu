const root_dir = path self ..
const default_policy_source = "hisle/InputMethod/DefaultMarkedTextRangePolicy.swift"
const policy_source = "hisle/InputMethod/MarkedTextRangePolicy.swift"
const check_source = "tools/marked_text_range_policy_check.swift"
const check_output = "build/tools/marked_text_range_policy_check"

cd $root_dir

mkdir ([$root_dir "build" "tools"] | path join)

hide-env -i CC CXX LD SDKROOT NIX_CC NIX_CFLAGS_COMPILE NIX_CFLAGS_LINK NIX_LDFLAGS
^/usr/bin/xcrun swiftc $default_policy_source $policy_source $check_source -framework InputMethodKit -o $check_output
^$check_output
