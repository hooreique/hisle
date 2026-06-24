const root_dir = path self ..
const support_source = "tools/GuiTestSupport.swift"
const driver_source = "tools/chrome_ime_driver.swift"
const driver_output = "build/tools/chrome_ime_driver"
const observer_dir = "tools/chrome-ime"
const observer_source = "tools/chrome-ime/observer.mjs"
const expected_artifacts = [
    "keys.jsonl",
    "dom-events.jsonl",
    "editor-chaos.jsonl",
    "ime.log",
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

cd $root_dir

let seed = ($env.SEED? | default "1")
let iterations = ($env.ITERATIONS? | default "1")
let target_kind = ($env.HISLE_CHROME_TARGET? | default "textarea")
let scenario = ($env.HISLE_CHROME_SCENARIO? | default "standard")
let initial_text = ($env.HISLE_CHROME_INITIAL_TEXT? | default "")
let initial_caret = ($env.HISLE_CHROME_INITIAL_CARET? | default "")
let initial_render = ($env.HISLE_CHROME_INITIAL_RENDER? | default "")
let move_after_composition_caret = ($env.HISLE_CHROME_MOVE_AFTER_COMPOSITION_CARET? | default "")
let move_after_input_caret = ($env.HISLE_CHROME_MOVE_AFTER_INPUT_CARET? | default "")
let click_after_input_caret = ($env.HISLE_CHROME_CLICK_AFTER_INPUT_CARET? | default "")
let force_render_on_composition_end = ($env.HISLE_CHROME_FORCE_RENDER_ON_COMPOSITION_END? | default "")
let editor_chaos = ($env.HISLE_CHROME_EDITOR_CHAOS? | default "")
let chaos_delay = ($env.HISLE_CHROME_CHAOS_DELAY_MS? | default "")
let allow_mismatch = ($env.HISLE_CHROME_ALLOW_MISMATCH? | default "")
let expected_value = ($env.EXPECTED_VALUE? | default "")
let skip_focus_click = ($env.HISLE_CHROME_SKIP_FOCUS_CLICK? | default "")
let click_initial_caret = ($env.HISLE_CHROME_CLICK_INITIAL_CARET? | default "")
let run_id_env = ($env.RUN_ID? | default "")
let run_id = if ($run_id_env | is-empty) {
    $"(date now | format date "%Y%m%d-%H%M%S")-(random chars --length 6)"
} else {
    $run_id_env
}
let run_dir = [$root_dir "build" "chrome-ime" $run_id] | path join
let ready_file = [$run_dir "observer-ready.json"] | path join
let observer_process_file = [$run_dir "observer-process.json"] | path join
let observer_stdout_file = [$run_dir "observer.stdout.log"] | path join
let observer_stderr_file = [$run_dir "observer.stderr.log"] | path join
let driver_stdout_file = [$run_dir "driver.stdout.log"] | path join
let driver_stderr_file = [$run_dir "driver.stderr.log"] | path join
let observer_port = ($env.OBSERVER_PORT? | default (random int 30000..55000 | into string))
let remote_debugging_port = ($env.CHROME_REMOTE_DEBUGGING_PORT? | default (random int 55001..60999 | into string))
let chrome_path = ($env.CHROME_PATH? | default "")
let keep_open = ($env.HISLE_CHROME_KEEP_OPEN? | default "")

mkdir $run_dir
mkdir ([$root_dir "build" "tools"] | path join)

if not (([$root_dir $observer_dir "node_modules" "playwright-core" "package.json"] | path join) | path exists) {
    print "Installing Chrome IME observer Node dependencies..."
    if (([$root_dir $observer_dir "package-lock.json"] | path join) | path exists) {
        ^npm --prefix $observer_dir ci --ignore-scripts --no-audit --no-fund
    } else {
        ^npm --prefix $observer_dir install --ignore-scripts --no-audit --no-fund
    }
}

print "Compiling Chrome IME Swift driver..."
^swiftc $support_source $driver_source -o $driver_output

let macos_version = command-text { ^/usr/bin/sw_vers -productVersion }
let hisle_cli = [$env.HOME "Library" "Input Methods" "hisle.app" "Contents" "Helpers" "hisle"] | path join
let hisle_cli_version = if ($hisle_cli | path exists) {
    command-text { ^$hisle_cli --version }
} else {
    ""
}
let default_chrome_executable = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
let chrome_version_executable = if not ($chrome_path | is-empty) {
    $chrome_path
} else if ($default_chrome_executable | path exists) {
    $default_chrome_executable
} else {
    ""
}
let chrome_version = if not ($chrome_version_executable | is-empty) {
    command-text { ^$chrome_version_executable --version }
} else {
    ""
}

print $"Writing Chrome IME artifacts to ($run_dir)"
let observer_job = job spawn --description "hisle chrome ime observer" {
    let result = do {
        with-env {
            RUN_DIR: $run_dir
            RUN_ID: $run_id
            OBSERVER_PORT: $observer_port
            CHROME_REMOTE_DEBUGGING_PORT: $remote_debugging_port
            CHROME_PATH: $chrome_path
            ITERATIONS: $iterations
            EXPECTED_VALUE: $expected_value
            HISLE_CHROME_TARGET: $target_kind
            HISLE_CHROME_INITIAL_TEXT: $initial_text
            HISLE_CHROME_INITIAL_CARET: $initial_caret
            HISLE_CHROME_INITIAL_RENDER: $initial_render
            HISLE_CHROME_MOVE_AFTER_COMPOSITION_CARET: $move_after_composition_caret
            HISLE_CHROME_MOVE_AFTER_INPUT_CARET: $move_after_input_caret
            HISLE_CHROME_CLICK_AFTER_INPUT_CARET: $click_after_input_caret
            HISLE_CHROME_FORCE_RENDER_ON_COMPOSITION_END: $force_render_on_composition_end
            HISLE_CHROME_EDITOR_CHAOS: $editor_chaos
            HISLE_CHROME_CHAOS_DELAY_MS: $chaos_delay
            HISLE_CHROME_ALLOW_MISMATCH: $allow_mismatch
            HISLE_CHROME_KEEP_OPEN: $keep_open
        } {
            ^node $observer_source
        }
    } | complete

    $result.stdout | save --force $observer_stdout_file
    $result.stderr | save --force $observer_stderr_file
    { exit_code: $result.exit_code } | to json | save --force $observer_process_file
}

wait-for-file $ready_file $observer_process_file "Chrome observer readiness"
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
        HISLE_CHROME_TARGET: $target_kind
        HISLE_CHROME_SCENARIO: $scenario
        HISLE_CHROME_DELAY_MIN_MS: ($env.HISLE_CHROME_DELAY_MIN_MS? | default "")
        HISLE_CHROME_DELAY_MAX_MS: ($env.HISLE_CHROME_DELAY_MAX_MS? | default "")
        HISLE_CHROME_IDLE_MS: ($env.HISLE_CHROME_IDLE_MS? | default "")
        HISLE_CHROME_SKIP_FOCUS_CLICK: $skip_focus_click
        HISLE_CHROME_CLICK_INITIAL_CARET: $click_initial_caret
        HISLE_CHROME_CLICK_SCREEN_DX: ($env.HISLE_CHROME_CLICK_SCREEN_DX? | default "")
        HISLE_CHROME_CLICK_SCREEN_DY: ($env.HISLE_CHROME_CLICK_SCREEN_DY? | default "")
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
    initial_render: (maybe-null $initial_render)
    move_after_composition_caret: (maybe-null $move_after_composition_caret)
    move_after_input_caret: (maybe-null $move_after_input_caret)
    force_render_on_composition_end: ($force_render_on_composition_end == "1")
    editor_chaos: $editor_chaos
    chaos_delay_milliseconds: (maybe-null $chaos_delay)
    allow_mismatch: ($allow_mismatch == "1")
    expected_value_override: (maybe-null $expected_value)
    skip_focus_click: ($skip_focus_click == "1")
    click_initial_caret: ($click_initial_caret == "1")
    macos_version: $macos_version
    chrome_path: (maybe-null $chrome_path)
    chrome_version: (if not ($ready.chrome_version? | default "" | is-empty) { $ready.chrome_version } else { maybe-null $chrome_version })
    hisle_cli_version: (maybe-null $hisle_cli_version)
    active_input_source_before_selection: ($driver_state.active_input_source_before_selection? | default null)
    selected_input_source_id: "hooreique.inputmethod.hisle.main"
    observer_readiness_time: ($ready.ready_wall_clock_timestamp? | default null)
    driver_start_time: ($driver_state.driver_start_time? | default null)
    observer_port: $ready.observer_port
    chrome_remote_debugging_port: $remote_debugging_port
    expected_artifacts: $expected_artifacts
} | to json | save --force ([$run_dir "environment.json"] | path join)

if $driver_result.exit_code != 0 {
    error make { msg: $"Chrome IME Swift driver failed with status ($driver_result.exit_code). Artifacts: ($run_dir)" }
}

if not $finish_response.ok {
    error make {
        msg: $"Chrome IME final state did not match expected value. Artifacts: ($run_dir)"
    }
}

if $observer_result.exit_code != 0 {
    error make { msg: $"Chrome IME observer failed with status ($observer_result.exit_code). Artifacts: ($run_dir)" }
}

print $"Chrome IME repro passed. Artifacts: ($run_dir)"
