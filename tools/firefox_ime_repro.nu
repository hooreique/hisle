const root_dir = path self ..

cd $root_dir

with-env { HISLE_BROWSER_KIND: "firefox" } {
    nu tools/chrome_ime_repro.nu
}
