# Icon

`hisle` has two different icons. Do not mix them up when cleaning up or
rerendering icon files.

## App Icon

The app icon is the icon shown in Finder, the Dock, and the installed `.app`
bundle.

- Source: `hisle/AppIcon.icon/`
- Foreground logo: `hisle/AppIcon.icon/Assets/HisleLogo.svg`
- README dark-mode logo: `hisle/AppIcon.icon/Assets/HisleLogo-white.svg`
- Fallback PNG asset catalog: `hisle/Assets.xcassets/AppIcon.appiconset/`
- Xcode setting: `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`
- Build output: `hisle.app/Contents/Resources/AppIcon.icns`

`HisleLogo.svg` must contain only the logo foreground. The app icon's white
background is handled as fill/background data in the `AppIcon.icon` document.
`HisleLogo-white.svg` is only for the README dark-mode image fallback. Do not
make the app icon from `HisleLogo-white.svg` or
`tools/icons/HisleInputSource.svg`.

## Input Method Icon

The input method icon is the icon used by the macOS input menu and
TIS/InputMethodKit metadata.

- Source: `tools/icons/HisleInputSource.svg`
- Rendered output: `hisle/Resources/HisleInputSource*.tiff`
- Modern input menu path: `hisle/Resources/HisleInputSource@2x.pdf`
- Metadata: `TISIconLabels.CustomIcon`, `tsInputMode*IconFileKey`, and
  `tsInputMethodIconFileKey` in `hisle/Info.plist`

`HisleInputSource.svg` is the input method icon source. Do not use it as the app
icon source.

The visible input mode points `TISIconLabels.CustomIcon` at the PDF so modern
macOS input menus can use the custom icon path, while the TIFF keys remain for
legacy TIS callers.

## Work Rules

- Before doing icon work, first decide which icon is changing.
- Keep app-icon and input-method-icon sources, outputs, and metadata separate
  in both documentation and implementation.
- Icon rendering uses the `icon` Nix shell with `resvg` and ImageMagick.
- `make icons` renders both the input method icon resources and the app icon
  fallback PNGs.
- Build release app bundles with Xcode 26 or newer so `AppIcon.icon`
  fill/background metadata is compiled into `AppIcon.icns`. Older Xcode
  versions can fall back to legacy app icon behavior and produce a visually
  different macOS app icon even when the PNG assets are unchanged.
- When changing the app icon, check both `hisle/AppIcon.icon/` and
  `hisle/Assets.xcassets/AppIcon.appiconset/`.
- When changing the input method icon, check `tools/icons/HisleInputSource.svg`,
  `hisle/Resources/`, and `hisle/Info.plist` together.
- When deleting icon-related files, keep the source, fallback, and metadata
  references needed to build both icons.

## Quick Check

```sh
nix develop .#icon --command -- make icons
nix develop .#icon --command -- nu tools/render_icons.nu
nix develop --command -- make build
```

After the build, the `.app` bundle should contain these files.

- `Contents/Resources/AppIcon.icns`
- `Contents/Resources/Assets.car`
- `Contents/Resources/HisleInputSource.tiff`
- `Contents/Resources/HisleInputSourceLarge.tiff`
- `Contents/Resources/HisleInputSource@2x.pdf`
