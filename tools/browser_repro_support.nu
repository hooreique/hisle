export def create-fresh-run-directory [run_dir: path] {
    let parent_dir = $run_dir | path dirname
    mkdir $parent_dir

    let result = do { ^/bin/mkdir -m 700 $run_dir } | complete
    if $result.exit_code != 0 {
        let detail = $result.stderr | str trim
        let message = if ($run_dir | path exists) {
            $"RUN_ID collision: refusing to reuse existing run directory: ($run_dir)"
        } else {
            $"Failed to atomically create fresh run directory: ($run_dir). ($detail)"
        }
        error make { msg: $message }
    }
}

def job-is-running [job_id: int] {
    not ((job list | where id == $job_id) | is-empty)
}

def read-observer-pid [pid_file: path] {
    if not ($pid_file | path exists) {
        return null
    }

    let text = try {
        open --raw $pid_file | str trim
    } catch {
        ""
    }

    if ($text =~ '^[1-9][0-9]*$') {
        $text | into int
    } else {
        null
    }
}

export def cleanup-observer-job [job_id: int, pid_file: path] {
    if not (job-is-running $job_id) {
        return
    }

    mut signalled = false
    for _ in 1..100 {
        if not (job-is-running $job_id) {
            return
        }

        if not $signalled {
            let recorded_pid = read-observer-pid $pid_file
            let job_pids = job list | where id == $job_id | get pids | flatten
            let target_pid = if $recorded_pid != null and ($recorded_pid in $job_pids) {
                $recorded_pid
            } else if not ($job_pids | is-empty) {
                $job_pids | first
            } else {
                null
            }
            if $target_pid != null {
                kill --quiet --signal 15 $target_pid
                $signalled = true
            }
        }

        sleep 100ms
    }

    if (job-is-running $job_id) {
        try { job kill $job_id } catch { }
    }
}
