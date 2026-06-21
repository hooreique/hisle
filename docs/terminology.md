# Terminology

이 문서는 `hisle` 개발과 대화에서 쓰는 글쇠 배열 관련 용어를 정리한다.

## 글쇠 용어

- 대표 글쇠: 키보드의 물리적인 각 키를 문서와 스펙에서 부르기 위한 기준
  이름이다. 대표 글쇠 이름은 표준 미국식 Qwerty 키보드에 인쇄된 글쇠를
  따른다. 예를 들어 `underlying roman layout`이 Colemak이어도 물리적 `K`
  자리의 대표 글쇠는 `k`이고, 물리적 `F` 자리의 대표 글쇠는 `f`이다.
- 대표 글쇠 표기: `k f x`, `j k f`, `v f`, `b t`처럼 입력 순서를
  대표 글쇠 이름으로 쓴 표기이다. Cole Sebeol 문서의 정책 예시는
  가독성을 위해 이 표기를 쓴다.
- 아랫글쇠: Shift 없이 눌렀을 때 입력되어야 하는 글자.
- 윗글쇠: Shift와 함께 눌렀을 때 입력되어야 하는 글자.
- 글쇠 배열: 영어의 layout에 해당하는 말이다. 어떤 배열로 글쇠가
  위치하느냐를 뜻한다.

## underlying roman layout

- underlying roman layout: 한글 입력 상태이더라도 프로그램에게 mod 키와
  함께 눌렀을 때 전달되어야 하는 로마자의 배열.
- 이 용어는 `기반 로마자 배열`처럼 번역하지 않고 항상 영어
  `underlying roman layout`으로 쓴다.
- underlying 글쇠: 어떤 글쇠의 underlying 글쇠라고 하면, 그 글쇠의
  underlying roman layout 상의 글쇠를 말한다.
- 대표 글쇠와 underlying 글쇠는 서로 다를 수 있다. Cole Sebeol에서는
  `underlying roman layout`이 Colemak이므로 대표 글쇠 `j k f`는
  underlying 글쇠로 쓰면 `n e t`가 된다. 정책 예시와 source-key label은
  사용자가 누르는 물리 글쇠를 보여주려고 underlying 글쇠가 아니라 대표
  글쇠로 쓴다.

## sane-punctuation 정책

- sane-punctuation 정책: Cole Sebeol 한글 모드에서 자모 글쇠는 Cole
  Sebeol 조합 입력으로 처리하되, 한글 자모가 아닌 printable scalar는
  세벌식 최종 특수문자 레이어가 아니라 아래 정책 표에 정의된 값을
  내보내는 정책이다. 이 표는 `~`, `"`, `{`, `<`, `>`처럼 기본 미국식
  문장부호를 보존해야 하는 글쇠와, `N -> :`, `M -> ;`, `? -> !`처럼
  Cole Sebeol이 별도로 정한 printable 글쇠를 함께 정의한다.
- sane-punctuation은 `underlying roman layout`과 별개다.
  `underlying roman layout`은 command/control shortcut 전달과 로마자
  모드의 Colemak 출력에 쓰인다. sane-punctuation은 한글 모드의
  printable scalar 출력에만 적용된다.
- sane-punctuation에서 한글 자모가 아닌 printable scalar는
  `FlushThenEmit`으로 처리한다. 먼저 활성 조합을 flush한 뒤, 정책 표에
  정의된 printable scalar를 이어서 내보낸다.
- 대표 글쇠 기준 sane-punctuation 표는 다음과 같다.

```text
대표 글쇠
`1234567890-=
[]\
;'
b n m , . /

아랫글쇠
`ㅎㅆㅂㅛㅠㅑㅖㅢㅜㅋ-=
[]\
ㅂㅌ
ㅜ ㅅ ㅎ , . ㅗ

윗글쇠
~ㄲㄺㅈㄿㄾ^&*()_+
{}|
4"
? : ; < > !
```

## 오토마타 정책 용어

- 초성 선행 모아치기 정책: 콜세벌에서 초성이 먼저 해결된 뒤에만 중성과
  종성을 순서 없이 받아들이는 제한적 모아치기 정책이다. 초성까지 포함한
  full 모아치기를 뜻하지 않는다.
- slash-nine(/9) 정책: 대표 글쇠 `/` 자리의 `ㅗ`와 대표 글쇠 `9` 자리의
  `ㅜ`를 source-key 특수 글쇠로 취급하는 정책이다. `/`와 `9`는 복합 중성
  조합에서 대응하는 기본 중성의 앞이나 뒤 어느 쪽에 와도 조합할 수 있다:
  `/ f`, `f /` -> `ㅘ`; `/ r`, `r /` -> `ㅙ`; `/ d`, `d /` -> `ㅚ`;
  `9 t`, `t 9` -> `ㅝ`; `9 c`, `c 9` -> `ㅞ`; `9 d`, `d 9` -> `ㅟ`.
- slash-nine(/9) 정책은 우는(Crying) 표현을 보존하기 위해 필요하다.
  예를 들어 `망했어ㅜㅜ`는 그대로 입력되어야 하며, 대표 글쇠 `b` 자리
  `ㅜ`가 앞의 `ㅓ`와 합쳐져 `망했워ㅜ`가 되면 안 된다.
- 대표 글쇠 `v` 자리의 `ㅗ`와 대표 글쇠 `b` 자리의 `ㅜ`는 `/`, `9`와
  같은 Unicode 자모를 내지만 같은 source-key 정책을 갖지 않는다. `v`와
  `b`는 앞에 오는 source-key order에서만 조합한다:
  `v f` -> `ㅘ`; `v r` -> `ㅙ`; `v d` -> `ㅚ`; `b t` -> `ㅝ`;
  `b c` -> `ㅞ`; `b d` -> `ㅟ`. 반대로 `f v`, `r v`, `d v`,
  `t b`, `c b`, `d b`는 조합하지 않고 각각 `ㅏㅗ`, `ㅐㅗ`, `ㅣㅗ`,
  `ㅓㅜ`, `ㅔㅜ`, `ㅣㅜ`로 남긴다.
- 약한 아래 정책: 공병우 세벌식 계열 배열은 유지하면서 순아래의
  shift 사용 감소 이점을 일부 취하는 정책이다. 정해진 서로 다른 자모
  쌍만 겹자모나 복합 중성/종성으로 조합한다. 초성의 같은 자모 반복은
  약한 아래 조합으로 보지 않지만, 종성 ㄱ+ㄱ -> ㄲ, 종성 ㅅ+ㅅ -> ㅆ은
  허용한다.
- 초성 선행 모아치기 정책은 약한 아래 정책의 논리적 필수 조건은
  아니지만, 순차 오토마타에서 약한 아래를 안정적으로 적용하기 위한
  boundary를 제공한다. 중성이나 종성이 오는 순간 초성 조합 상태는
  결정적으로 끝나며, 뒤에 온 초성은 앞의 초성과 약한 아래 조합을 만들지
  않는다.
- standalone jamo: 완성 음절로 조합되지 못하고 단독으로 flush되는 자모이다.
  오토마타 내부에서는 Unicode Hangul Jamo를 쓰더라도, 사용자에게 flush할
  때는 Hangul Compatibility Jamo로 내보낸다.
- Flush: 현재 조합 중인 내용을 visible text로 내보내고 조합 상태를 비우는
  엔진 동작이다.
- FlushThenEmit: 먼저 Flush하고 Space나 문장부호 같은 printable scalar를
  이어서 내보내는 동작이다.
- FlushThenForward: 먼저 Flush하고 Delete나 command/control shortcut 같은
  host action을 host app으로 넘기는 동작이다.
- Backspace: 조합 중이면 입력 스택에서 하나 제거하고, 조합 중이 아니면
  host app으로 넘기는 동작이다.
- Clear: flush 없이 조합 상태를 지우는 내부 동작이다. 일반 사용자 입력
  경로에서는 거의 쓰지 않는다.
- partial composition boundary: 미완성 조합을 더 기다리지 않고 처리해야
  하는 입력 경계이다. 새 초성, 문장부호, 공백, 명시적 Flush, Delete,
  command/control shortcut이 여기에 들어간다. Clear는 flush하지 않고
  조합을 지우는 clearing boundary이다.
- source key: 같은 유니코드 자모라도 어느 대표 글쇠에서 왔는지를
  나타내는 입력 출처이다. slash-nine(/9) 정책을 구현하려면 `ㅗ`와
  `ㅜ`를 유니코드 자모만으로 처리하지 말고 source key를 보존해야 한다.
- source-key label: 정책 예시에 쓰는 `k f x`, `j k f`, `v f`, `b t` 같은
  대표 글쇠 이름이다. 오토마타 정책의 입력 순서를 설명하기 위한 표기이며,
  전역 유니코드 자모 치환 규칙을 뜻하지 않는다.
