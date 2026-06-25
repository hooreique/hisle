<p align="center">
  <img src="hisle/AppIcon.icon/Assets/HisleLogo.svg" width="128" alt="hisle 로고">
</p>

<h1 align="center">hisle</h1>

`hisle`은 macOS용 개인 한글 입력기입니다. 한국어 이름은 `이슬`이고,
국제 표기는 `hisle`입니다.

로마자 입력과 한글 입력을 하나의 input source 안에서 다루고, 한글 모드는
Cole Sebeol 기반의 개인 글쇠 배열을 씁니다. 범용 한국어 입력기를 목표로
하지 않습니다.

## Motivation

### Apple Caps Lock Delay Issue

macOS는 Caps Lock으로 입력 소스를 전환할 때 키를 100ms 넘게 눌러야
동작하도록 제한합니다. 이 때문에 Karabiner-Elements 같은 도구로 Caps
Lock을 입력기 전환 키처럼 다루기가 까다롭고, 영문과 한국어를 오가는
흐름도 나빠집니다.

`hisle`은 로마자와 한글을 한 입력기 안에서 처리해 이 문제를 피하려고
만들었습니다. 이것이 가장 큰 계기이고, 기왕 만드는 김에 제 취향에 맞는
입력 정책도 함께 넣었습니다.

### left/right Shift mode selection

입력기 전환은 토글보다 단방향 선택이 편합니다. `hisle`은 왼쪽 Shift
단독 탭으로 로마자 모드를, 오른쪽 Shift 단독 탭으로 한글 모드를
선택합니다.

현재 상태를 기억하고 맞는지 확인할 필요 없이 원하는 모드의 Shift를 치면
되기 때문에, 영문과 한국어를 자주 오가는 흐름에서 꽤 큰 차이를 만듭니다.

### underlying roman layout

저는 Qwerty 대신 Colemak을 씁니다. 그래서 한글 입력 중에도
Command/Control 단축키는 Colemak과 일관되게 동작해야 합니다.

`hisle`은 한글 글쇠 배열과 단축키 전달에 쓰는 로마자 배열을 분리하기
위해 `underlying roman layout` 개념을 둡니다.

### sane-punctuation

전통적인 세벌식의 자모 배치는 여전히 유효하지만, 특수문자 레이어는 현대적
개발과 일상 입력에는 잘 맞지 않습니다.

`hisle`은 세벌식 최종 글쇠배열을 바탕으로 자모 배치는 살리고, 문장부호는
`sane-punctuation` 정책으로 다시 잡은 개인 글쇠 배열을 사용합니다.

## Direction

`hisle`은 작게 유지보수할 개인용 입력기입니다. 모든 사람에게 맞는 한국어
입력기를 만들 생각은 없습니다.

이 설정과 취향이 맞지 않는다면 MIT 라이선스이므로 자유롭게 포크하거나
가져가서 원하는 대로 바꿔 쓰면 됩니다. 다만 글쇠 배열, 모드 전환,
문장부호 정책처럼 취향의 영역에 있는 변경은 미안하지만 PR로 받지
않습니다.

성능 개선, 버그 수정, 테스트 보강, 빌드와 패키징 개선처럼 코드 품질을
높이는 변경은 여전히 환영합니다.

## Development

유지보수와 개발 규칙은 [AGENTS.md](AGENTS.md)와 [docs/](docs/)에
있습니다.
