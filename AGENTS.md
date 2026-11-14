# Fork 브랜치 관리 규칙

이 규칙은 이 fork(`dukeow94/OmniWM`)에 적용한다. 이 fork 내부의 브랜치 관리에서는 `CONTRIBUTING.md`의 upstream 작업 흐름보다 이 규칙을 우선한다. 구현·검증·upstream 기여에 대해서는 계속 `CONTRIBUTING.md`를 따른다.

## 브랜치 역할

- `main`은 `OmniNull/OmniWM:main`을 추적한다. fork 전용 문서와 설정을 포함하여 fork 전용 커밋을 넣지 않는다. upstream으로부터 fast-forward로 갱신하며, 히스토리가 갈라졌다면 reset이나 강제 푸시를 하지 말고 중단한 뒤 사용자에게 확인한다.
- `develop`은 fork의 장기 개발·통합 브랜치다. fork 전용 작업의 기본 기준 브랜치로 사용한다.
- 최신 `develop`에서 작업 단위별 브랜치를 만들고, `feat/<topic>`, `fix/<topic>`, `docs/<topic>`처럼 목적이 드러나는 이름을 사용한다. fork 내부 PR은 `main`이 아닌 `develop`을 대상으로 한다.
- 완료한 작업 브랜치는 merge commit으로 `develop`에 통합하여 논리적인 커밋 구성과 작성자 정보를 보존한다.
- 명시적인 요청 없이 저장소의 기본 브랜치나 브랜치 보호 설정을 변경하지 않는다.

## Upstream 동기화

- `origin`은 `dukeow94/OmniWM`, `upstream`은 `https://github.com/OmniNull/OmniWM.git`을 가리킨다. fetch나 push 전에 remote URL을 확인한다. `upstream`이 없다면 동기화 전에 등록한다.
- upstream을 fetch하고, fork의 `main`을 동기화 대상 upstream 커밋까지 fast-forward한 뒤 갱신된 `main`을 `develop`에 merge한다. fork 전용 변경을 보존하고 충돌은 명시적으로 해결한다.
- `develop`에 반영할 때는 동기화 전용 브랜치와 PR을 사용한다. `develop`을 upstream 위로 rebase하거나 upstream 히스토리로 대체하지 않는다.
- upstream에 기여할 때는 `upstream/main`에서 별도 브랜치를 만들고 `OmniNull/OmniWM:main`을 PR 대상으로 한다. 관련 변경만 포함하고, fork의 `develop`을 upstream PR에 merge하지 않는다.

## 커밋과 히스토리 안전 규칙

- 커밋은 리뷰하기 쉬운 논리적인 작업 단위로 나눈다. 무관한 변경을 섞지 않는다.
- `main`과 `master`에서는 기존 커밋을 재작성하지 않는다. 공유 통합 브랜치인 `develop`의 히스토리도 재작성하지 않는다.
- 작업 브랜치에서는 폐기한 접근이나 수정만을 위한 중간 단계를 남기기보다 최종 구현을 중심으로 커밋을 정리한다.
- 기존 커밋을 제거하거나 재작성하기 전에는 현재 히스토리를 원격 브랜치에 푸시하고, 원격에 반영되었는지 확인한다. 푸시나 확인에 실패하면 재작성하지 않는다.
- 재작성은 현재 작업에 속한 커밋만 대상으로 한다. 다른 기여자의 커밋과 작업에 무관한 변경은 보존한다.
- 재작성한 히스토리를 푸시할 때는 `--force` 대신 `--force-with-lease`를 사용한다. 원격 변경으로 거부되면 중단하고 원격 변경을 확인한다.
- 저장소의 브랜치 보호와 강제 푸시 제한을 준수한다. 의도한 작업과 충돌하면 우회하지 말고 사용자에게 확인한다.
