# hisle

hisle은 작은 macOS 입력기입니다. 이름은 한국어로 `이슬`, 국제 표기는
`hisle`이고 발음은 `/i.sɯl/`입니다.

영어 문서는 [README.md](README.md)를 참고하십시오.

## 현재 상태

hisle은 하나의 macOS input source인 `hisle`을 제공합니다. 로마자 모드로
시작해 Colemak 출력을 내보내고, 한글 모드에서는 콜세벌을 사용합니다.
왼쪽/오른쪽 Shift 단독 탭으로 로마자/한글 모드를 선택합니다.
다른 입력기를 쓰다가 `hisle`로 돌아오면 로마자 모드로 들어옵니다.

## 소스에서 설치

이 checkout에서 설치하려면 macOS, Xcode, Nix가 필요합니다.

```sh
make install-debug
```

이 명령은 앱을 빌드한 뒤 `~/Library/Input Methods`에 설치합니다.

## 입력 소스 선택

System Settings > Keyboard에서 `hisle`을 input source로 추가합니다. 입력
메뉴에서 `hisle`을 선택하면 사용할 수 있습니다.

## 사용

- 왼쪽 Shift 단독 탭은 로마자 모드를 선택합니다.
- 오른쪽 Shift 단독 탭은 한글 모드를 선택합니다.
- Escape는 활성 한글 조합을 commit하고 로마자 모드를 선택한 뒤, 현재 앱에
  그대로 전달됩니다.

## Companion CLI

설치된 번들에는 작은 `hisle` helper가 포함됩니다.

```sh
"$HOME/Library/Input Methods/hisle.app/Contents/Helpers/hisle"
"$HOME/Library/Input Methods/hisle.app/Contents/Helpers/hisle" --version
"$HOME/Library/Input Methods/hisle.app/Contents/Helpers/hisle" --help
```

옵션 없이 실행하면 현재 모드인 `roman` 또는 `hangul`을 출력합니다.
`--version`은 앱과 `hisle-core` 버전을 출력하고, `--help`는 사용법을
출력합니다.

## 제거

```sh
make uninstall
```

유지보수와 개발 규칙은 [AGENTS.md](AGENTS.md)에 있습니다.
