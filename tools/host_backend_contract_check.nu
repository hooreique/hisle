const root_dir = path self ..
const configuration_source = "hisle/App/BusyAppsSnapshot.swift"
const mode_source = "hisle/InputMethod/InputModeState.swift"
const marked_text_source = "hisle/InputMethod/MarkedTextState.swift"
const contract_source = "hisle/InputMethod/HostBackendContract.swift"
const check_source = "tools/host_backend_contract_check.swift"
const check_output = "build/tools/host_backend_contract_check"

cd $root_dir

mkdir ([$root_dir "build" "tools"] | path join)

hide-env -i CC CXX LD SDKROOT NIX_CC NIX_CFLAGS_COMPILE NIX_CFLAGS_LINK NIX_LDFLAGS
^/usr/bin/xcrun swiftc $configuration_source $mode_source $marked_text_source $contract_source $check_source -framework InputMethodKit -o $check_output
^$check_output
