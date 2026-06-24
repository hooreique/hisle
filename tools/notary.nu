const root_dir = path self ..

cd $root_dir

let dmg_path = ($env.DMG_PATH? | default ([$root_dir "build" "dist" "hisle-0.1.0.dmg"] | path join))
let timeout = ($env.NOTARY_TIMEOUT? | default "30m")

def local-value [name: string] {
    let path = [$root_dir "local" $name] | path join

    if not ($path | path exists) {
        return ""
    }

    open --raw $path | str trim
}

if not ($dmg_path | path exists) {
    error make { msg: $"Missing DMG: ($dmg_path)" }
}

let notary_key_path = ($env.NOTARY_API_KEY_PATH? | default (local-value "notary-api-key-path"))
let notary_key_id = ($env.NOTARY_API_KEY_ID? | default (local-value "notary-api-key-id"))
let notary_issuer_id = ($env.NOTARY_API_ISSUER_ID? | default (local-value "notary-api-issuer-id"))

if ($notary_key_path | is-empty) {
    error make { msg: "Missing NOTARY_API_KEY_PATH or local/notary-api-key-path." }
}

if ($notary_key_id | is-empty) {
    error make { msg: "Missing NOTARY_API_KEY_ID or local/notary-api-key-id." }
}

if ($notary_issuer_id | is-empty) {
    error make { msg: "Missing NOTARY_API_ISSUER_ID or local/notary-api-issuer-id." }
}

if not ($notary_key_path | path exists) {
    error make { msg: $"Missing notary API key file: ($notary_key_path)" }
}

let submission_id_from_env = ($env.NOTARY_SUBMISSION_ID? | default "")
let current_submission_id = (local-value "current-notary-submission-id")
let submission_id = if ($submission_id_from_env | is-empty) {
    if ($current_submission_id | is-empty) {
        print $"Submitting ($dmg_path) to Apple notary service..."

        let submit = (^/usr/bin/xcrun notarytool submit $dmg_path --key $notary_key_path --key-id $notary_key_id --issuer $notary_issuer_id --no-s3-acceleration --output-format json | from json)

        mkdir "local"
        $submit.id | save --force ([$root_dir "local" "current-notary-submission-id"] | path join)
        print $"Submission ID: ($submit.id)"
        $submit.id
    } else {
        print $"Using saved submission ID: ($current_submission_id)"
        $current_submission_id
    }
} else {
    print $"Using existing submission ID: ($submission_id_from_env)"
    $submission_id_from_env
}

print $"Waiting for notarization result, timeout: ($timeout)"

try {
    ^/usr/bin/xcrun notarytool wait $submission_id --key $notary_key_path --key-id $notary_key_id --issuer $notary_issuer_id --timeout $timeout
} catch {
    print "notarytool wait exited before an Accepted result; checking final status..."
}

let status_info = (^/usr/bin/xcrun notarytool info $submission_id --key $notary_key_path --key-id $notary_key_id --issuer $notary_issuer_id --output-format json | from json)

print $"Notary status: ($status_info.status)"

if $status_info.status == "In Progress" {
    print $"Notarization is still in progress. Check again later with NOTARY_SUBMISSION_ID=($submission_id)."
    exit 0
}

if $status_info.status != "Accepted" {
    let notary_dir = [$root_dir "build" "notary"] | path join
    let log_output_path = [$notary_dir $"($submission_id)-log.json"] | path join

    try {
        mkdir $notary_dir
        ^/usr/bin/xcrun notarytool log $submission_id --key $notary_key_path --key-id $notary_key_id --issuer $notary_issuer_id $log_output_path
        print $"Saved notary log: ($log_output_path)"
    } catch {
        print "Notary log is not available yet."
    }

    error make { msg: $"Notarization did not finish as Accepted. Submission ID: ($submission_id)" }
}

print $"Stapling ticket to ($dmg_path)..."
^/usr/bin/xcrun stapler staple $dmg_path

print "Validating stapled ticket..."
^/usr/bin/xcrun stapler validate $dmg_path

print "Verifying Gatekeeper acceptance..."
^/usr/sbin/spctl -a -vv -t open --context context:primary-signature $dmg_path

print "Verifying DMG code signature..."
^/usr/bin/codesign --verify --verbose=4 $dmg_path

print $"Notarized and stapled: ($dmg_path)"
