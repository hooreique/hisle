const root_dir = path self ..
const source_svg = $root_dir | path join "tools" "icons" "HisleInputSource.svg"
const output_dir = $root_dir | path join "hisle" "Resources"
const app_icon_dir = $root_dir | path join "hisle" "Assets.xcassets" "AppIcon.appiconset"
const app_icon_svg = $root_dir | path join "hisle" "AppIcon.icon" "Assets" "HisleLogo.svg"
const pdf_fixed_timestamp = "19700101000000"

def normalize_pdf_timestamp [prefix: string] {
  let data = $in
  let prefix_bytes = ($prefix | into binary)
  let timestamp_bytes = ($pdf_fixed_timestamp | into binary)
  let prefix_index = ($data | bytes index-of $prefix_bytes)
  if $prefix_index < 0 {
    error make {msg: $"PDF metadata marker not found: ($prefix)"}
  }

  let timestamp_start = $prefix_index + ($prefix_bytes | bytes length)
  let timestamp_end = $timestamp_start + ($timestamp_bytes | bytes length)
  let old_timestamp = ($data | bytes at $timestamp_start..<$timestamp_end | decode utf-8)
  if not ($old_timestamp =~ "^\\d{14}$") {
    error make {msg: $"Unexpected PDF timestamp after ($prefix): ($old_timestamp)"}
  }

  let before = ($data | bytes at ..<$timestamp_start)
  let after = ($data | bytes at $timestamp_end..)
  $before | bytes add $timestamp_bytes --end | bytes add $after --end
}

def normalize_pdf_metadata [pdf_path: path] {
  # ImageMagick writes wall-clock PDF metadata. Replace only fixed-width
  # timestamp bytes so PDF xref offsets remain valid.
  open --raw $pdf_path
  | normalize_pdf_timestamp "/CreationDate (D:"
  | normalize_pdf_timestamp "/ModDate (D:"
  | save --raw --force $pdf_path
}

let sizes = [
  [filename size];
  ["HisleInputSource.tiff" 16]
  ["HisleInputSource@2x.tiff" 32]
  ["HisleInputSourceLarge.tiff" 64]
  ["HisleInputSourceLarge@2x.tiff" 128]
]

let app_icon_sizes = [
  [filename size];
  ["HisleAppIcon-16x16@1x.png" 16]
  ["HisleAppIcon-16x16@2x.png" 32]
  ["HisleAppIcon-32x32@1x.png" 32]
  ["HisleAppIcon-32x32@2x.png" 64]
  ["HisleAppIcon-128x128@1x.png" 128]
  ["HisleAppIcon-128x128@2x.png" 256]
  ["HisleAppIcon-256x256@1x.png" 256]
  ["HisleAppIcon-256x256@2x.png" 512]
  ["HisleAppIcon-512x512@1x.png" 512]
  ["HisleAppIcon-512x512@2x.png" 1024]
]

let stale_files = [
  "HisleInputSource.png"
  "HisleInputSource@2x.png"
  "HisleInputSource@2x.pdf.png"
  "HisleInputSourceLarge.png"
  "HisleInputSourceLarge@2x.png"
]

mkdir $output_dir
mkdir $app_icon_dir

for filename in $stale_files {
  let stale_path = $output_dir | path join $filename
  if ($stale_path | path exists) {
    rm $stale_path
  }
}

for icon in $sizes {
  let output = $output_dir | path join $icon.filename
  let intermediate = $"($output).png"
  let dimensions = $"($icon.size)x($icon.size)"
  ^resvg --width $icon.size --height $icon.size $source_svg $intermediate
  ^magick $intermediate -background none -gravity center -extent $dimensions $output
  rm $intermediate
}

let custom_icon_pdf = $output_dir | path join "HisleInputSource@2x.pdf"
let custom_icon_intermediate = $"($custom_icon_pdf).png"
^resvg --width 32 --height 32 $source_svg $custom_icon_intermediate
^magick $custom_icon_intermediate -background none -gravity center -extent 32x32 $custom_icon_pdf
normalize_pdf_metadata $custom_icon_pdf
rm $custom_icon_intermediate

for icon in $app_icon_sizes {
  let output = $app_icon_dir | path join $icon.filename
  let intermediate = $"($output).tmp.png"
  let dimensions = $"($icon.size)x($icon.size)"
  ^resvg --width $icon.size --height $icon.size $app_icon_svg $intermediate
  ^magick -size $dimensions "xc:#ffffff" $intermediate -gravity center -composite -alpha off -type TrueColor $output
  rm $intermediate
}

print $"rendered input source icons into ($output_dir)"
print $"rendered app icons into ($app_icon_dir)"
