use browser_repro_support.nu [cleanup-observer-job create-fresh-run-directory]

def require [condition: bool, message: string] {
    if not $condition {
        error make { msg: $message }
    }
}

def check-observer-cleanup [run_dir: path, record_pid: bool] {
    let observer_job = job spawn --description "browser repro support cleanup check" {
        do { ^/bin/sleep 30 } | complete | ignore
    }

    try {
        mut child_pid = -1
        for _ in 1..100 {
            let jobs = job list | where id == $observer_job
            if not ($jobs | is-empty) {
                let pids = $jobs | get pids | flatten
                if not ($pids | is-empty) {
                    $child_pid = $pids | first
                    break
                }
            }
            sleep 10ms
        }
        require ($child_pid > 0) "background observer child PID was not registered"

        let pid_name = if $record_pid { "observer.pid" } else { "missing-observer.pid" }
        let pid_file = [$run_dir $pid_name] | path join
        if $record_pid {
            $child_pid | save --force $pid_file
        }
        cleanup-observer-job $observer_job $pid_file
        cleanup-observer-job $observer_job $pid_file
        require ((job list | where id == $observer_job) | is-empty) "observer job survived cleanup"
    } finally {
        if not ((job list | where id == $observer_job) | is-empty) {
            try { job kill $observer_job } catch { }
        }
    }
}

let temporary_template = [($env.TMPDIR? | default "/tmp") "hisle-browser-repro-support.XXXXXX"] | path join
let temporary_root = ^/usr/bin/mktemp -d $temporary_template | str trim
let run_dir = [$temporary_root "run"] | path join
let sentinel = [$run_dir "sentinel"] | path join

try {
    create-fresh-run-directory $run_dir
    require ($run_dir | path exists) "fresh run directory was not created"
    require ((^/usr/bin/stat -f '%Lp' $run_dir | str trim) == "700") "fresh run directory is not mode 0700"

    "preserve" | save $sentinel
    let collision_error = try {
        create-fresh-run-directory $run_dir
        null
    } catch { |error|
        $error
    }
    require ($collision_error != null) "existing run directory was reused"
    require ((open --raw $sentinel) == "preserve") "collision handling changed existing artifacts"
    check-observer-cleanup $run_dir false
    check-observer-cleanup $run_dir true
} finally {
    rm --recursive --force $temporary_root
}

print "Browser repro support check passed."
