use browser_repro_support.nu [cleanup-observer-job create-fresh-run-directory]

const root_dir = path self ..
const support_source = "tools/GuiTestSupport.swift"
const driver_source = "tools/chrome_ime_driver.swift"
const driver_output = "build/tools/chrome_ime_driver"
const observer_dir = "tools/chrome-ime"
const observer_source = "tools/chrome-ime/observer.mjs"
const observer_supervisor = "tools/chrome-ime/observer_supervisor.mjs"
const base_expected_artifacts = [
    "keys.jsonl",
    "dom-events.jsonl",
    "editor-chaos.jsonl",
    "ime.log",
    "runtime-identity.log",
    "final-state.json",
    "screenshot.png",
    "trace.zip",
    "environment.json",
]

def command-text [closure: closure] {
    let result = do $closure | complete
    if $result.exit_code == 0 {
        $result.stdout | str trim
    } else {
        ""
    }
}

def wait-for-file [file: string, process_file: string, description: string] {
    for _ in 0..450 {
        if ($file | path exists) {
            return
        }

        if ($process_file | path exists) {
            let process_result = open $process_file
            error make {
                msg: $"Timed out waiting for ($description); observer exited early with status ($process_result.exit_code)"
            }
        }

        sleep 100ms
    }

    error make { msg: $"Timed out waiting for ($description): ($file)" }
}

def wait-for-observer-exit [process_file: string] {
    for _ in 0..600 {
        if ($process_file | path exists) {
            return
        }
        sleep 100ms
    }

    error make { msg: $"Timed out waiting for observer process result: ($process_file)" }
}

def maybe-null [value: string] {
    if ($value | is-empty) {
        null
    } else {
        $value
    }
}

def env-first [names: list, fallback: string = ""] {
    for name in $names {
        let value = ($env | get -o $name | default "")
        if not ($value | is-empty) {
            return $value
        }
    }

    $fallback
}

cd $root_dir

let browser_kind = ($env.HISLE_BROWSER_KIND? | default "chrome")
if not ($browser_kind in ["chrome" "firefox"]) {
    error make { msg: $"Unsupported HISLE_BROWSER_KIND: ($browser_kind)" }
}
let browser_label = if $browser_kind == "firefox" { "Firefox" } else { "Chrome" }
let browser_slug = if $browser_kind == "firefox" { "firefox" } else { "chrome" }
let browser_prefix = if $browser_kind == "firefox" { "HISLE_FIREFOX" } else { "HISLE_CHROME" }
let expected_artifacts = if $browser_kind == "firefox" {
    $base_expected_artifacts | where $it != "trace.zip"
} else {
    $base_expected_artifacts
}
let seed = ($env.SEED? | default "1")
let iterations = ($env.ITERATIONS? | default "1")
let scenario = env-first [$"($browser_prefix)_SCENARIO" "HISLE_CHROME_SCENARIO"] "standard"
let stale_selection_annyeonghaseyo = $scenario == "stale-selection-annyeonghaseyo"
let target_kind_env = env-first [$"($browser_prefix)_TARGET" "HISLE_CHROME_TARGET"]
let target_kind = if ($target_kind_env | is-empty) {
    if $stale_selection_annyeonghaseyo { "contenteditable" } else { "textarea" }
} else {
    $target_kind_env
}
let initial_text_env = env-first [$"($browser_prefix)_INITIAL_TEXT" "HISLE_CHROME_INITIAL_TEXT"]
let initial_text = if ($initial_text_env | is-empty) {
    if $stale_selection_annyeonghaseyo { "가나다라마바사" } else { "" }
} else {
    $initial_text_env
}
let initial_caret_env = env-first [$"($browser_prefix)_INITIAL_CARET" "HISLE_CHROME_INITIAL_CARET"]
let initial_caret = if ($initial_caret_env | is-empty) {
    if $stale_selection_annyeonghaseyo { "3" } else { "" }
} else {
    $initial_caret_env
}
let initial_selection_env = env-first [$"($browser_prefix)_INITIAL_SELECTION" "HISLE_CHROME_INITIAL_SELECTION"]
let initial_selection = if ($initial_selection_env | is-empty) {
    if $stale_selection_annyeonghaseyo { "0:7" } else { "" }
} else {
    $initial_selection_env
}
let initial_double_click_env = env-first [$"($browser_prefix)_INITIAL_DOUBLE_CLICK" "HISLE_CHROME_INITIAL_DOUBLE_CLICK"]
let initial_double_click = if ($initial_double_click_env | is-empty) {
    if $stale_selection_annyeonghaseyo { "1" } else { "" }
} else {
    $initial_double_click_env
}
let initial_render = env-first [$"($browser_prefix)_INITIAL_RENDER" "HISLE_CHROME_INITIAL_RENDER"]
let move_after_composition_caret = env-first [$"($browser_prefix)_MOVE_AFTER_COMPOSITION_CARET" "HISLE_CHROME_MOVE_AFTER_COMPOSITION_CARET"]
let move_after_input_caret = env-first [$"($browser_prefix)_MOVE_AFTER_INPUT_CARET" "HISLE_CHROME_MOVE_AFTER_INPUT_CARET"]
let click_after_input_caret = env-first [$"($browser_prefix)_CLICK_AFTER_INPUT_CARET" "HISLE_CHROME_CLICK_AFTER_INPUT_CARET"]
let drag_selection = env-first [$"($browser_prefix)_DRAG_SELECTION" "HISLE_CHROME_DRAG_SELECTION"]
let force_render_on_composition_end = env-first [$"($browser_prefix)_FORCE_RENDER_ON_COMPOSITION_END" "HISLE_CHROME_FORCE_RENDER_ON_COMPOSITION_END"]
let editor_chaos_env = env-first [$"($browser_prefix)_EDITOR_CHAOS" "HISLE_CHROME_EDITOR_CHAOS"]
let editor_chaos = if ($editor_chaos_env | is-empty) {
    if $stale_selection_annyeonghaseyo { "restore-initial-selection" } else { "" }
} else {
    $editor_chaos_env
}
let chaos_delay = env-first [$"($browser_prefix)_CHAOS_DELAY_MS" "HISLE_CHROME_CHAOS_DELAY_MS"]
let allow_mismatch = env-first [$"($browser_prefix)_ALLOW_MISMATCH" "HISLE_CHROME_ALLOW_MISMATCH"]
let expected_value_env = ($env.EXPECTED_VALUE? | default "")
let expected_value = if ($expected_value_env | is-empty) {
    if $stale_selection_annyeonghaseyo { "안녕하세요" } else { "" }
} else {
    $expected_value_env
}
let skip_focus_click = env-first [$"($browser_prefix)_SKIP_FOCUS_CLICK" "HISLE_CHROME_SKIP_FOCUS_CLICK"]
let click_initial_caret = env-first [$"($browser_prefix)_CLICK_INITIAL_CARET" "HISLE_CHROME_CLICK_INITIAL_CARET"]
let run_id_env = ($env.RUN_ID? | default "")
let run_id = if ($run_id_env | is-empty) {
    $"(date now | format date "%Y%m%d-%H%M%S")-(random chars --length 6)"
} else {
    $run_id_env
}
let run_dir = [$root_dir "build" $"($browser_slug)-ime" $run_id] | path join
let ready_file = [$run_dir "observer-ready.json"] | path join
let observer_process_file = [$run_dir "observer-process.json"] | path join
let observer_pid_file = [$run_dir "observer.pid"] | path join
let observer_stdout_file = [$run_dir "observer.stdout.log"] | path join
let observer_stderr_file = [$run_dir "observer.stderr.log"] | path join
let driver_stdout_file = [$run_dir "driver.stdout.log"] | path join
let driver_stderr_file = [$run_dir "driver.stderr.log"] | path join
let observer_port = ($env.OBSERVER_PORT? | default (random int 30000..55000 | into string))
let remote_debugging_port = if $browser_kind == "chrome" {
    $env.CHROME_REMOTE_DEBUGGING_PORT? | default (random int 55001..60999 | into string)
} else {
    ""
}
let default_firefox_executable = "/Applications/Firefox.app/Contents/MacOS/firefox"
let browser_path = if $browser_kind == "firefox" {
    let configured = env-first ["FIREFOX_PATH" "HISLE_FIREFOX_PATH"]
    if not ($configured | is-empty) {
        $configured
    } else if ($default_firefox_executable | path exists) {
        $default_firefox_executable
    } else {
        ""
    }
} else {
    $env.CHROME_PATH? | default ""
}
let keep_open = env-first [$"($browser_prefix)_KEEP_OPEN" "HISLE_CHROME_KEEP_OPEN"]

create-fresh-run-directory $run_dir
mkdir ([$root_dir "build" "tools"] | path join)

let has_playwright_core = ([$root_dir $observer_dir "node_modules" "playwright-core" "package.json"] | path join) | path exists
let has_selenium_webdriver = ([$root_dir $observer_dir "node_modules" "selenium-webdriver" "package.json"] | path join) | path exists
if not ($has_playwright_core and $has_selenium_webdriver) {
    print $"Installing ($browser_label) IME observer Node dependencies..."
    if (([$root_dir $observer_dir "package-lock.json"] | path join) | path exists) {
        ^npm --prefix $observer_dir ci --ignore-scripts --no-audit --no-fund
    } else {
        ^npm --prefix $observer_dir install --ignore-scripts --no-audit --no-fund
    }
}

print $"Compiling ($browser_label) IME Swift driver..."
hide-env -i CC CXX LD SDKROOT NIX_CC NIX_CFLAGS_COMPILE NIX_CFLAGS_LINK NIX_LDFLAGS
^/usr/bin/xcrun swiftc $support_source $driver_source -o $driver_output

let macos_version = command-text { ^/usr/bin/sw_vers -productVersion }
let hisle_cli = [$env.HOME "Library" "Input Methods" "hisle.app" "Contents" "Helpers" "hisle"] | path join
let hisle_cli_version = if ($hisle_cli | path exists) {
    command-text { ^$hisle_cli --version }
} else {
    ""
}
let default_chrome_executable = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
let browser_version_executable = if not ($browser_path | is-empty) {
    $browser_path
} else if ($browser_kind == "chrome" and ($default_chrome_executable | path exists)) {
    $default_chrome_executable
} else {
    ""
}
let browser_version = if not ($browser_version_executable | is-empty) {
    command-text { ^$browser_version_executable --version }
} else {
    ""
}

print $"Writing ($browser_label) IME artifacts to ($run_dir)"
let observer_job = job spawn --description $"hisle ($browser_slug) ime observer" {
    let result = do {
        with-env {
            RUN_DIR: $run_dir
            RUN_ID: $run_id
            OBSERVER_PORT: $observer_port
            HISLE_WRAPPER_PID: ($nu.pid | into string)
            HISLE_BROWSER_KIND: $browser_kind
            CHROME_REMOTE_DEBUGGING_PORT: $remote_debugging_port
            CHROME_PATH: (if $browser_kind == "chrome" { $browser_path } else { "" })
            FIREFOX_PATH: (if $browser_kind == "firefox" { $browser_path } else { "" })
            ITERATIONS: $iterations
            EXPECTED_VALUE: $expected_value
            HISLE_CHROME_TARGET: $target_kind
            HISLE_FIREFOX_TARGET: $target_kind
            HISLE_CHROME_INITIAL_TEXT: $initial_text
            HISLE_FIREFOX_INITIAL_TEXT: $initial_text
            HISLE_CHROME_INITIAL_CARET: $initial_caret
            HISLE_FIREFOX_INITIAL_CARET: $initial_caret
            HISLE_CHROME_INITIAL_SELECTION: $initial_selection
            HISLE_FIREFOX_INITIAL_SELECTION: $initial_selection
            HISLE_CHROME_INITIAL_DOUBLE_CLICK: $initial_double_click
            HISLE_FIREFOX_INITIAL_DOUBLE_CLICK: $initial_double_click
            HISLE_CHROME_INITIAL_RENDER: $initial_render
            HISLE_FIREFOX_INITIAL_RENDER: $initial_render
            HISLE_CHROME_MOVE_AFTER_COMPOSITION_CARET: $move_after_composition_caret
            HISLE_FIREFOX_MOVE_AFTER_COMPOSITION_CARET: $move_after_composition_caret
            HISLE_CHROME_MOVE_AFTER_INPUT_CARET: $move_after_input_caret
            HISLE_FIREFOX_MOVE_AFTER_INPUT_CARET: $move_after_input_caret
            HISLE_CHROME_CLICK_AFTER_INPUT_CARET: $click_after_input_caret
            HISLE_FIREFOX_CLICK_AFTER_INPUT_CARET: $click_after_input_caret
            HISLE_CHROME_DRAG_SELECTION: $drag_selection
            HISLE_FIREFOX_DRAG_SELECTION: $drag_selection
            HISLE_CHROME_FORCE_RENDER_ON_COMPOSITION_END: $force_render_on_composition_end
            HISLE_FIREFOX_FORCE_RENDER_ON_COMPOSITION_END: $force_render_on_composition_end
            HISLE_CHROME_EDITOR_CHAOS: $editor_chaos
            HISLE_FIREFOX_EDITOR_CHAOS: $editor_chaos
            HISLE_CHROME_CHAOS_DELAY_MS: $chaos_delay
            HISLE_FIREFOX_CHAOS_DELAY_MS: $chaos_delay
            HISLE_CHROME_ALLOW_MISMATCH: $allow_mismatch
            HISLE_FIREFOX_ALLOW_MISMATCH: $allow_mismatch
            HISLE_CHROME_KEEP_OPEN: $keep_open
            HISLE_FIREFOX_KEEP_OPEN: $keep_open
        } {
            ^node $observer_supervisor $observer_source
        }
    } | complete

    $result.stdout | save --force $observer_stdout_file
    $result.stderr | save --force $observer_stderr_file
    { exit_code: $result.exit_code } | to json | save --force $observer_process_file
}

try {
wait-for-file $ready_file $observer_process_file $"($browser_label) observer readiness"
let ready = open $ready_file
let ready_url = $"http://127.0.0.1:($ready.observer_port)/ready"
let finish_url = $"http://127.0.0.1:($ready.observer_port)/finish"
let ready_probe = do {
    ^/usr/bin/curl --fail --silent --show-error --max-time 5 $ready_url
} | complete
if $ready_probe.exit_code != 0 {
    error make { msg: $"Observer readiness check failed: ($ready_probe.stderr | str trim)" }
}
let ready_response = $ready_probe.stdout | from json
if not $ready_response.ok {
    error make { msg: $"Observer readiness check failed: ($ready_response | to json --raw)" }
}

print "Running Swift HID driver..."
let driver_result = do {
    with-env {
        HISLE_BROWSER_KIND: $browser_kind
        HISLE_CHROME_TARGET: $target_kind
        HISLE_FIREFOX_TARGET: $target_kind
        HISLE_CHROME_SCENARIO: $scenario
        HISLE_FIREFOX_SCENARIO: $scenario
        HISLE_CHROME_DELAY_MIN_MS: (env-first [$"($browser_prefix)_DELAY_MIN_MS" "HISLE_CHROME_DELAY_MIN_MS"])
        HISLE_FIREFOX_DELAY_MIN_MS: (env-first [$"($browser_prefix)_DELAY_MIN_MS" "HISLE_CHROME_DELAY_MIN_MS"])
        HISLE_CHROME_DELAY_MAX_MS: (env-first [$"($browser_prefix)_DELAY_MAX_MS" "HISLE_CHROME_DELAY_MAX_MS"])
        HISLE_FIREFOX_DELAY_MAX_MS: (env-first [$"($browser_prefix)_DELAY_MAX_MS" "HISLE_CHROME_DELAY_MAX_MS"])
        HISLE_CHROME_IDLE_MS: (env-first [$"($browser_prefix)_IDLE_MS" "HISLE_CHROME_IDLE_MS"])
        HISLE_FIREFOX_IDLE_MS: (env-first [$"($browser_prefix)_IDLE_MS" "HISLE_CHROME_IDLE_MS"])
        HISLE_CHROME_SKIP_FOCUS_CLICK: $skip_focus_click
        HISLE_FIREFOX_SKIP_FOCUS_CLICK: $skip_focus_click
        HISLE_CHROME_CLICK_INITIAL_CARET: $click_initial_caret
        HISLE_FIREFOX_CLICK_INITIAL_CARET: $click_initial_caret
        HISLE_CHROME_CLICK_SCREEN_DX: (env-first [$"($browser_prefix)_CLICK_SCREEN_DX" "HISLE_CHROME_CLICK_SCREEN_DX"])
        HISLE_FIREFOX_CLICK_SCREEN_DX: (env-first [$"($browser_prefix)_CLICK_SCREEN_DX" "HISLE_CHROME_CLICK_SCREEN_DX"])
        HISLE_CHROME_CLICK_SCREEN_DY: (env-first [$"($browser_prefix)_CLICK_SCREEN_DY" "HISLE_CHROME_CLICK_SCREEN_DY"])
        HISLE_FIREFOX_CLICK_SCREEN_DY: (env-first [$"($browser_prefix)_CLICK_SCREEN_DY" "HISLE_CHROME_CLICK_SCREEN_DY"])
        EXPECTED_VALUE: $expected_value
    } {
        ^$driver_output --run-dir $run_dir --ready-file $ready_file --seed $seed --iterations $iterations
    }
} | complete

$driver_result.stdout | save --force $driver_stdout_file
$driver_result.stderr | save --force $driver_stderr_file

if not ($driver_result.stdout | str trim | is-empty) {
    print ($driver_result.stdout | str trim)
}
if not ($driver_result.stderr | str trim | is-empty) {
    print -e ($driver_result.stderr | str trim)
}

let finish_payload = {
    reason: "driver-finished"
    driver_exit_code: $driver_result.exit_code
} | to json --raw
let finish_result = do {
    ^/usr/bin/curl --fail --silent --show-error --max-time 90 --header "content-type: application/json" --data $finish_payload $finish_url
} | complete

if $finish_result.exit_code != 0 {
    error make { msg: $"Observer finish request failed: ($finish_result.stderr | str trim). Artifacts: ($run_dir)" }
}

let finish_response = $finish_result.stdout | from json

wait-for-observer-exit $observer_process_file
let observer_result = open $observer_process_file

let driver_state_file = [$run_dir "driver-state.json"] | path join
let driver_state = if ($driver_state_file | path exists) {
    open $driver_state_file
} else {
    {}
}

{
    run_directory_schema_version: 1
    run_id: $run_id
    seed: ($seed | into int)
    iteration_count: ($iterations | into int)
    target_kind: $target_kind
    scenario: $scenario
    initial_text: $initial_text
    initial_caret: (maybe-null $initial_caret)
    initial_selection: (maybe-null $initial_selection)
    initial_double_click: ($initial_double_click == "1")
    initial_render: (maybe-null $initial_render)
    move_after_composition_caret: (maybe-null $move_after_composition_caret)
    move_after_input_caret: (maybe-null $move_after_input_caret)
    drag_selection: (maybe-null $drag_selection)
    force_render_on_composition_end: ($force_render_on_composition_end == "1")
    editor_chaos: $editor_chaos
    chaos_delay_milliseconds: (maybe-null $chaos_delay)
    allow_mismatch: ($allow_mismatch == "1")
    expected_value_override: (maybe-null $expected_value)
    skip_focus_click: ($skip_focus_click == "1")
    click_initial_caret: ($click_initial_caret == "1")
    macos_version: $macos_version
    browser_kind: $browser_kind
    browser_path: (maybe-null $browser_path)
    browser_version: (if not ($ready.browser_version? | default "" | is-empty) { $ready.browser_version } else { maybe-null $browser_version })
    chrome_path: (if $browser_kind == "chrome" { maybe-null $browser_path } else { null })
    chrome_version: (if $browser_kind == "chrome" { if not ($ready.chrome_version? | default "" | is-empty) { $ready.chrome_version } else { maybe-null $browser_version } } else { null })
    firefox_path: (if $browser_kind == "firefox" { maybe-null $browser_path } else { null })
    firefox_version: (if $browser_kind == "firefox" { if not ($ready.firefox_version? | default "" | is-empty) { $ready.firefox_version } else { maybe-null $browser_version } } else { null })
    hisle_cli_version: (maybe-null $hisle_cli_version)
    active_input_source_before_selection: ($driver_state.active_input_source_before_selection? | default null)
    selected_input_source_id: "hooreique.inputmethod.hisle.main"
    observer_readiness_time: ($ready.ready_wall_clock_timestamp? | default null)
    driver_start_time: ($driver_state.driver_start_time? | default null)
    observer_port: $ready.observer_port
    chrome_remote_debugging_port: (if $browser_kind == "chrome" { $remote_debugging_port } else { null })
    expected_artifacts: $expected_artifacts
} | to json | save --force ([$run_dir "environment.json"] | path join)

if $driver_result.exit_code != 0 {
    error make { msg: $"($browser_label) IME Swift driver failed with status ($driver_result.exit_code). Artifacts: ($run_dir)" }
}

if not $finish_response.ok {
    error make {
        msg: $"($browser_label) IME final state did not match expected value. Artifacts: ($run_dir)"
    }
}

if $observer_result.exit_code != 0 {
    error make { msg: $"($browser_label) IME observer failed with status ($observer_result.exit_code). Artifacts: ($run_dir)" }
}

print $"($browser_label) IME repro passed. Artifacts: ($run_dir)"
} finally {
    cleanup-observer-job $observer_job $observer_pid_file
}
