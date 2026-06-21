let product_name = ($env.PRODUCT_NAME? | default "hisle")
let app_name = $"($product_name).app"
let install_dir = ($env.INSTALL_DIR? | default ([$env.HOME "Library" "Input Methods"] | path join))

if ($install_dir | is-empty) {
    error make { msg: "INSTALL_DIR must not be empty" }
}

let installed_app = [$install_dir $app_name] | path join

try {
    ^/usr/bin/killall $product_name out+err> /dev/null
} catch {
}

rm --recursive --force $installed_app

print $"Removed ($installed_app)"
