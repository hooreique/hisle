<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="hisle/AppIcon.icon/Assets/HisleLogo-white.svg">
    <img src="hisle/AppIcon.icon/Assets/HisleLogo.svg" width="128" alt="hisle 로고">
  </picture>
</p>

<h1 align="center">hisle</h1>

`hisle`은 macOS용 개인 한글 입력기입니다.

한국어 이름은 `이슬`, 영문 표기는 `hisle`입니다.

로마자와 한글을 하나의 Input Source 안에서 처리하며, 한글은 세벌식 최종 기반의 개인 글쇠 배열인 **Cole Sebeol**을 사용합니다. 범용 한국어 입력기를 목표로 하지 않습니다.

## Motivation

### Caps Lock without delay

macOS에서 입력 소스를 바꾸려면 Caps Lock을 100ms 이상 눌러야 합니다. 그래서 Karabiner Elements 와 같은 도구를 이용하여 Caps Lock이 눌렸다 떼진 것을 에뮬레이션하는 식으로 입력기가 전환되게 구성하는 것이 지저분합니다.

> [!NOTE]
> Caps Lock에만 적용되는 것은 아니고 시스템 설정에서 입력 소스 전환에 할당한 키에 적용되는 제약입니다. 그리고 이것은 언젠가 고쳐질지도 모릅니다. See https://github.com/pqrs-org/Karabiner-Elements/issues/3949

`hisle`은 입력기 전환 없이 로마자와 한글을 하나의 입력기 안에서 함께 처리합니다. 이것이 프로젝트를 시작한 가장 큰 이유입니다.

### Left/Right Shift mode selection

입력기 전환은 토글보다 명시적인 선택이 편합니다.

왼쪽 Shift 단독 탭은 로마자 모드, 오른쪽 Shift 단독 탭은 한글 모드를 선택합니다.

현재 상태를 확인하거나 기억할 필요 없이 원하는 모드의 Shift만 누르면 됩니다.

### Underlying Roman Layout

저는 Qwerty 대신 Colemak을 사용합니다.

한글을 입력하는 동안에도 Command·Control 단축키는 Colemak 기준으로 동작하기를 원했습니다.

`hisle`은 이를 위해 한글 글쇠 배열과 단축키에 사용하는 로마자 배열을 분리하는 `underlying roman layout` 개념을 제공합니다.

### Sane punctuation

세벌식 최종의 자모 배치는 유지하면서, 특수문자는 현대적인 개발 환경과 일상 입력에 맞는 일반적인 배열을 사용합니다.

## Project direction

`hisle`은 제 취향에 맞게 유지보수하는 개인 프로젝트입니다.

MIT 라이선스이므로 자유롭게 포크하거나 수정해서 사용할 수 있습니다. 글쇠 배열, 모드 전환 방식, 문장부호 정책처럼 취향의 영역에 해당하는 변경은 PR로 받지 않습니다.

범용성, 확장성, 고도화에 해당하는 변경도 원치 않습니다. 작게 유지하고자 합니다.

성능 개선, 버그 수정, 테스트 보강, 빌드·패키징 개선처럼 코드 품질을 높이는 기여는 환영합니다.

## Development

유지보수 가이드는 [AGENTS.md](AGENTS.md)를 참고하세요.
