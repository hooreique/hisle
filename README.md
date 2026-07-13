<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="hisle/AppIcon.icon/Assets/HisleLogo-white.svg">
    <img src="hisle/AppIcon.icon/Assets/HisleLogo.svg" width="128" alt="hisle 로고">
  </picture>
</p>

<h1 align="center">hisle</h1>

`hisle`은 macOS용 한글 입력기입니다.

한국어 이름은 `이슬`, 영문 표기는 `hisle`입니다.

로마자와 한글을 하나의 입력 소스 안에서 처리하며, 한글 모드에서는 세벌식 최종 기반의 **Cole Sebeol** 글쇠 배열을 사용합니다. 불필요하게 복잡해지는 것은 지양합니다.

## Motivation

`hisle`은 왼쪽 Shift 단독 탭으로 로마자 모드를, 오른쪽 Shift 단독 탭으로 한글 모드를 직접 선택하기 위해 만들었습니다.

- 왼쪽 Shift 단독 탭: 로마자 모드
- 오른쪽 Shift 단독 탭: 한글 모드

토글 방식과 달리 현재 모드를 확인하거나 기억할 필요 없이 원하는 모드를 바로 선택할 수 있습니다.

## Caps Lock 전환 지연 없이

macOS에서 Caps Lock으로 입력 소스를 전환할 때는 키를 일정 시간 이상 눌러야 하는 지연이 있습니다. Apple이 이 동작을 개선하기 전까지 이 지연을 피하려면 입력기 내부에서 모드를 전환하거나 별도 유틸리티로 우회해야 합니다.

`hisle`은 로마자와 한글을 하나의 입력 소스 안에서 처리하므로, 시스템의 입력 소스 전환을 거치지 않고 지연 없이 모드를 바꿀 수 있습니다.

참고: [Karabiner-Elements 관련 이슈 #3949](https://github.com/pqrs-org/Karabiner-Elements/issues/3949)

## Development

유지보수 가이드는 [AGENTS.md](AGENTS.md)를 참고하세요.
