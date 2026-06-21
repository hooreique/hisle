# Two Icons

`hisle` has two different icons. Do not mix them up when cleaning up or
rerendering icon files.

## App Icon

The app icon is the icon shown in Finder, the Dock, and the installed `.app`
bundle.

- Source: `hisle/AppIcon.icon/`
- Foreground logo: `hisle/AppIcon.icon/Assets/HisleLogo.svg`
- Fallback PNG asset catalog: `hisle/Assets.xcassets/AppIcon.appiconset/`
- Xcode setting: `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`
- Build output: `hisle.app/Contents/Resources/AppIcon.icns`

`HisleLogo.svg` must contain only the logo foreground. The app icon's white
background is handled as fill/background data in the `AppIcon.icon` document.
Do not make the app icon from `tools/icons/HisleInputSource.svg`.

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

## Work Rules

- Before doing icon work, first decide which icon is changing.
- `make icons` renders both the input method icon resources and the app icon
  fallback PNGs.
- When changing the app icon, check both `hisle/AppIcon.icon/` and
  `hisle/Assets.xcassets/AppIcon.appiconset/`.
- When changing the input method icon, check `tools/icons/HisleInputSource.svg`,
  `hisle/Resources/`, and `hisle/Info.plist` together.
- When deleting icon-related files, keep the source, fallback, and metadata
  references needed to build both icons.

## Quick Check

```sh
make icons
nix develop .#xcode-work --command -- make build
```

After the build, the `.app` bundle should contain these files.

- `Contents/Resources/AppIcon.icns`
- `Contents/Resources/Assets.car`
- `Contents/Resources/HisleInputSource.tiff`
- `Contents/Resources/HisleInputSourceLarge.tiff`
- `Contents/Resources/HisleInputSource@2x.pdf`
