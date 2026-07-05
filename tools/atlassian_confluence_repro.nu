const root_dir = path self ..
const support_source = "tools/GuiTestSupport.swift"
const driver_source = "tools/atlassian_confluence_driver.swift"
const driver_output = "build/tools/atlassian_confluence_driver"
const observer_dir = "tools/chrome-ime"
const observer_source = "tools/chrome-ime/atlassian_observer.mjs"
const expected_artifacts = [
    "keys.jsonl",
    "dom-events.jsonl",
    "console.jsonl",
    "ime.log",
    "runtime-identity.log",
    "driver-state.json",
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
    for _ in 0..900 {
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
    for _ in 0..900 {
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

def first-non-empty [values: list] {
    for value in $values {
        let text = ($value | default "")
        if not ($text | is-empty) {
            return $text
        }
    }
    ""
}

def normalize-url [value: string] {
    if ($value | is-empty) {
        ""
    } else if (($value | str starts-with "http://") or ($value | str starts-with "https://")) {
        $value
    } else {
        $"https://($value)"
    }
}

cd $root_dir

let local_atlassian_dir = ($env.HISLE_ATLASSIAN_DIR? | default ([$root_dir "local" "atlassian"] | path join))
let config_file = [$local_atlassian_dir "config.json"] | path join
let config = if ($config_file | path exists) {
    open $config_file
} else {
    {}
}
let info_file = [$root_dir "local" "atlassianinfo"] | path join
let info_text = if ($info_file | path exists) {
    open --raw $info_file | str trim
} else {
    ""
}
let info_parts = if ($info_text | is-empty) {
    []
} else {
    $info_text | split row --regex '\s+'
}
let info_site_raw = if (($info_parts | length) > 0) { $info_parts | get 0 } else { "" }
let info_email = if (($info_parts | length) > 1) { $info_parts | get 1 } else { "" }
let info_site = normalize-url $info_site_raw
let config_base_url = normalize-url ($config.base_url? | default "")
let page_url = first-non-empty [
    ($env.ATLASSIAN_CONFLUENCE_URL? | default ""),
    ($env.HISLE_ATLASSIAN_URL? | default ""),
    ($config.page_url? | default ""),
    $config_base_url,
    $info_site,
]
let email = first-non-empty [
    ($env.ATLASSIAN_EMAIL? | default ""),
    ($config.email? | default ""),
    $info_email,
]

if ($page_url | is-empty) {
    error make {
        msg: "Set ATLASSIAN_CONFLUENCE_URL or local/atlassian/config.json page_url before running the Atlassian Confluence repro."
    }
}

let seed = ($env.SEED? | default "1")
let login_only = (($env.HISLE_ATLASSIAN_LOGIN_ONLY? | default "") == "1")
let run_id_env = ($env.RUN_ID? | default "")
let run_id = if ($run_id_env | is-empty) {
    let suffix = if $login_only { "login" } else { random chars --length 6 }
    $"(date now | format date "%Y%m%d-%H%M%S")-($suffix)"
} else {
    $run_id_env
}
let run_dir = [$local_atlassian_dir "runs" $run_id] | path join
let profile_dir = ($env.HISLE_ATLASSIAN_PROFILE_DIR? | default ([$local_atlassian_dir "chrome-profile"] | path join))
let ready_file = [$run_dir "observer-ready.json"] | path join
let observer_process_file = [$run_dir "observer-process.json"] | path join
let observer_stdout_file = [$run_dir "observer.stdout.log"] | path join
let observer_stderr_file = [$run_dir "observer.stderr.log"] | path join
let driver_stdout_file = [$run_dir "driver.stdout.log"] | path join
let driver_stderr_file = [$run_dir "driver.stderr.log"] | path join
let observer_port = ($env.OBSERVER_PORT? | default (random int 30000..55000 | into string))
let remote_debugging_port = ($env.CHROME_REMOTE_DEBUGGING_PORT? | default (random int 55001..60999 | into string))
let chrome_path = ($env.CHROME_PATH? | default "")
let chrome_app = ($env.HISLE_ATLASSIAN_CHROME_APP? | default "Google Chrome")
let keep_open = ($env.HISLE_ATLASSIAN_KEEP_OPEN? | default "")
let expected_text = ($env.HISLE_ATLASSIAN_EXPECTED_TEXT? | default "안녕하세요")
let scenario = ($env.HISLE_ATLASSIAN_SCENARIO? | default "annyeonghaseyo")
let word_count = ($env.HISLE_ATLASSIAN_WORD_COUNT? | default "")
let roman_text = ($env.HISLE_ATLASSIAN_ROMAN_TEXT? | default "")
let target_selector = ($env.HISLE_ATLASSIAN_TARGET_SELECTOR? | default "")
let edit_page = ($env.HISLE_ATLASSIAN_EDIT? | default "")
let window_title_contains = ($env.HISLE_ATLASSIAN_WINDOW_TITLE_CONTAINS? | default "")
let allow_mismatch = ($env.HISLE_ATLASSIAN_ALLOW_MISMATCH? | default "")
let trace = ($env.HISLE_ATLASSIAN_TRACE? | default "")
let editor_timeout = ($env.HISLE_ATLASSIAN_EDITOR_TIMEOUT_MS? | default "")
let initial_caret_offset = ($env.HISLE_ATLASSIAN_INITIAL_CARET_OFFSET? | default "")

mkdir $local_atlassian_dir
mkdir ([$local_atlassian_dir "runs"] | path join)
mkdir $run_dir
mkdir $profile_dir
mkdir ([$root_dir "build" "tools"] | path join)

if $login_only {
    print $"Opening Atlassian Confluence with normal Chrome and persistent profile: ($profile_dir)"
    print $"Requested URL: ($page_url)"
    print "Complete sign-in in Chrome, verify that the page is usable, then quit that Chrome window with Command-Q."
    let login_result = if not ($chrome_path | is-empty) {
        do {
            ^$chrome_path $"--user-data-dir=($profile_dir)" "--no-first-run" "--no-default-browser-check" $page_url
        } | complete
    } else {
        do {
            ^/usr/bin/open -W -na $chrome_app --args $"--user-data-dir=($profile_dir)" "--no-first-run" "--no-default-browser-check" $page_url
        } | complete
    }

    if not ($login_result.stdout | str trim | is-empty) {
        print ($login_result.stdout | str trim)
    }
    if not ($login_result.stderr | str trim | is-empty) {
        print -e ($login_result.stderr | str trim)
    }
    if $login_result.exit_code != 0 {
        error make {
            msg: $"Atlassian login Chrome exited with status ($login_result.exit_code)."
        }
    }

    print $"Atlassian login profile browser closed. Profile: ($profile_dir)"
    exit 0
}

if not (([$root_dir $observer_dir "node_modules" "playwright-core" "package.json"] | path join) | path exists) {
    print "Installing Atlassian Confluence observer Node dependencies..."
    if (([$root_dir $observer_dir "package-lock.json"] | path join) | path exists) {
        ^npm --prefix $observer_dir ci --ignore-scripts --no-audit --no-fund
    } else {
        ^npm --prefix $observer_dir install --ignore-scripts --no-audit --no-fund
    }
}

let observer_env = {
    RUN_DIR: $run_dir
    RUN_ID: $run_id
    OBSERVER_PORT: $observer_port
    CHROME_REMOTE_DEBUGGING_PORT: $remote_debugging_port
    CHROME_PATH: $chrome_path
    HISLE_ATLASSIAN_CHROME_APP: $chrome_app
    HISLE_ATLASSIAN_NORMAL_CHROME: ($env.HISLE_ATLASSIAN_NORMAL_CHROME? | default "")
    HISLE_ATLASSIAN_REUSE_CHROME: ($env.HISLE_ATLASSIAN_REUSE_CHROME? | default "")
    ATLASSIAN_PROFILE_DIR: $profile_dir
    ATLASSIAN_CONFLUENCE_URL: $page_url
    ATLASSIAN_EMAIL: $email
    HISLE_ATLASSIAN_LOGIN_ONLY: (if $login_only { "1" } else { "" })
    HISLE_ATLASSIAN_KEEP_OPEN: $keep_open
        HISLE_ATLASSIAN_EXPECTED_TEXT: $expected_text
        HISLE_ATLASSIAN_SCENARIO: $scenario
        HISLE_ATLASSIAN_WORD_COUNT: $word_count
        HISLE_ATLASSIAN_TARGET_SELECTOR: $target_selector
    HISLE_ATLASSIAN_EDIT: $edit_page
    HISLE_ATLASSIAN_WINDOW_TITLE_CONTAINS: $window_title_contains
    HISLE_ATLASSIAN_ALLOW_MISMATCH: $allow_mismatch
    HISLE_ATLASSIAN_TRACE: $trace
    HISLE_ATLASSIAN_EDITOR_TIMEOUT_MS: $editor_timeout
    HISLE_ATLASSIAN_INITIAL_CARET_OFFSET: $initial_caret_offset
}

print "Compiling Atlassian Confluence Swift driver..."
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

print $"Writing Atlassian Confluence artifacts to ($run_dir)"
let observer_job = job spawn --description "hisle atlassian confluence observer" {
    let result = do {
        with-env $observer_env {
            ^node $observer_source
        }
    } | complete

    $result.stdout | save --force $observer_stdout_file
    $result.stderr | save --force $observer_stderr_file
    { exit_code: $result.exit_code } | to json | save --force $observer_process_file
}

wait-for-file $ready_file $observer_process_file "Atlassian Confluence observer readiness"
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

print "Running Atlassian Confluence Swift HID driver..."
let driver_result = do {
    with-env {
        HISLE_ATLASSIAN_EXPECTED_TEXT: $expected_text
        HISLE_ATLASSIAN_SCENARIO: $scenario
        HISLE_ATLASSIAN_WORD_COUNT: $word_count
        HISLE_ATLASSIAN_ROMAN_TEXT: $roman_text
        HISLE_ATLASSIAN_DELAY_MIN_MS: ($env.HISLE_ATLASSIAN_DELAY_MIN_MS? | default "")
        HISLE_ATLASSIAN_DELAY_MAX_MS: ($env.HISLE_ATLASSIAN_DELAY_MAX_MS? | default "")
        HISLE_ATLASSIAN_IDLE_MS: ($env.HISLE_ATLASSIAN_IDLE_MS? | default "")
        HISLE_ATLASSIAN_CLICK_SCREEN_DX: ($env.HISLE_ATLASSIAN_CLICK_SCREEN_DX? | default "")
        HISLE_ATLASSIAN_CLICK_SCREEN_DY: ($env.HISLE_ATLASSIAN_CLICK_SCREEN_DY? | default "")
        HISLE_ATLASSIAN_SKIP_EDITOR_CLICK: ($env.HISLE_ATLASSIAN_SKIP_EDITOR_CLICK? | default "")
        HISLE_ATLASSIAN_HANGUL_BEFORE_EDITOR_CLICK: ($env.HISLE_ATLASSIAN_HANGUL_BEFORE_EDITOR_CLICK? | default "")
        HISLE_ATLASSIAN_INITIAL_CARET_OFFSET: $initial_caret_offset
    } {
        ^$driver_output --run-dir $run_dir --ready-file $ready_file --seed $seed
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
    requested_page_url: $page_url
    current_page_url: ($ready.current_page_url? | default null)
    local_atlassian_dir: $local_atlassian_dir
    profile_dir: $profile_dir
    expected_text: $expected_text
    scenario: $scenario
    word_count: (maybe-null $word_count)
    roman_text: (maybe-null $roman_text)
    target_selector: (maybe-null $target_selector)
    initial_caret_offset: (maybe-null $initial_caret_offset)
    edit_page: (if ($edit_page | is-empty) { true } else { $edit_page != "0" })
    allow_mismatch: ($allow_mismatch == "1")
    keep_open: ($keep_open == "1")
    trace_enabled: ($trace != "0")
    window_title_contains: ($ready.window_title_contains? | default null)
    macos_version: $macos_version
    chrome_path: (maybe-null $chrome_path)
    chrome_version: (if not ($ready.chrome_version? | default "" | is-empty) { $ready.chrome_version } else { maybe-null $chrome_version })
    hisle_cli_version: (maybe-null $hisle_cli_version)
    atlassian_email_configured: (not ($email | is-empty))
    active_input_source_before_selection: ($driver_state.active_input_source_before_selection? | default null)
    selected_input_source_id: "hooreique.inputmethod.hisle.main"
    observer_readiness_time: ($ready.ready_wall_clock_timestamp? | default null)
    driver_start_time: ($driver_state.driver_start_time? | default null)
    observer_port: $ready.observer_port
    chrome_remote_debugging_port: $remote_debugging_port
    expected_artifacts: $expected_artifacts
} | to json | save --force ([$run_dir "environment.json"] | path join)

if $driver_result.exit_code != 0 {
    error make { msg: $"Atlassian Confluence Swift driver failed with status ($driver_result.exit_code). Artifacts: ($run_dir)" }
}

if not $finish_response.ok {
    error make {
        msg: $"Atlassian Confluence final state did not match expected text. Artifacts: ($run_dir)"
    }
}

if $observer_result.exit_code != 0 {
    error make { msg: $"Atlassian Confluence observer failed with status ($observer_result.exit_code). Artifacts: ($run_dir)" }
}

print $"Atlassian Confluence repro passed. Artifacts: ($run_dir)"
