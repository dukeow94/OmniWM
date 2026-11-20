# v0.8.0 Dev 전환 및 런타임 검증

## 1. 기준과 범위

2026-11-20, 사용자가 Release → Dev 전환과 수동 검증을 승인한 뒤 수행했다. [자동 검증 기록](upstream-v0.8.0-local-validation.md)의 최신 전체 serial/parallel 각 8,818개 통과 이후 단계다.

- 브랜치: `sync/upstream-v0.8.0`
- 기반 head: `ea1278b712c335bc2fb27ce9a4a31702fa3bce1a`
- 검증 당시 소스에는 미커밋 drawer 입력 격리 수정이 포함됐다. 이후 동일한 수정을 `d1da6cb816912a4b73c8ebaf0e2b5b22da99652d`로 커밋했다. 설치 앱의 기반 git hash만으로 당시 원격 clean head와 동일하다고 보지 않는다.
- 설치 앱: `~/Applications/OmniWM Dev.app`, bundle ID `com.barut.OmniWM.dev`
- CLI: `0.8.0 (protocol 22, build ea1278b71, debug, sha256 a238d86089aa)`
- 실제 모니터: 내장 Retina Display 1개, 1728×1117 logical points. 다중 모니터 검증 환경은 아니다.

**검증 결과:** 설치·기동·마이그레이션·IPC·실제 규칙 합성/배정/숨김 smoke 검증은 통과했다. 모든 WM 기능의 수동 검증이 끝난 것은 아니며 아래 미검증 항목을 보존한다. 사용자는 이 범위의 검증이 충분하다고 판단하고 PR #8 병합을 명시적으로 요청했다. 승인과 병합 범위는 8절에 기록한다.

## 2. 백업 및 전환

백업 위치:

```text
~/Library/Application Support/OmniWM Validation Backups/v080-20261120-180552/
```

`umask 077`로 별도 디렉터리를 만들고 아래 자료를 복사했다. 개인 설정·state·진단 자료를 포함하므로 Git이나 원격에 공유하지 않는다.

- `config/omniwm/`, `config/omniwm-dev/`
- `state/omniwm/`, `state/omniwm-dev/`
- `apps/OmniWM Dev.app`: 이전 Dev 앱, 기반 hash `dfbcdeab`, 서명 검증 성공
- `baseline.json`: 생성 시각과 Release/Dev 설정 SHA-256

Release 앱은 `/Applications/OmniWM.app`에 그대로 보존했다(bundle ID `com.barut.OmniWM`, hash `bdf2de66`, Developer ID 서명). state는 Release 실행 중의 스냅샷이므로 graceful quit 시 최종 state flush까지 동일하다고 가정하지 않는다.

실행 환경과 launchctl에 XDG config/state override가 없음을 확인했다. 기존 `OmniWM Dev` codesigning identity를 재사용했으며 인증서/keychain이나 TCC를 변경하지 않았다.

Pinned Swift 환경에서 `make run`을 실행했다. build/localization/packaging/signing 성공 후 helper가 Release를 정상 종료하고 Dev를 교체·설치·LaunchServices 기동했다. 강제 종료는 사용하지 않았다. 설치 후 앱의 deep/strict 서명 검증도 통과했다.

## 3. 설정 분리와 마이그레이션

| 항목 | 결과 |
| --- | --- |
| Release 설정 | schema 3, IPC false. 전환 전/검증 후 설정 SHA-256 동일 |
| 기존 Dev 설정 | schema 5 → 6, 기존 파일을 Release 설정으로 덮어쓰지 않음 |
| Dev 포커스 설정 | `focus.monitorCrossingFocus = last` 보존, Displays → Behavior UI에서도 `Last Focused` 표시 확인 |
| Dev IPC | 기존 true 유지, 별도 enable 변경 없이 접속 성공 |
| 마이그레이션 백업 | `settings.toml.pre-v6`가 전환 전 Dev 설정 백업과 byte-for-byte 일치 |
| 기존 백업 | 기존 `settings.toml.pre-v4` 유지 |
| Start at Login | General UI switch 0(꺼짐) 확인, 조작하지 않음 |
| CLI 경로 | 설치 앱 내부의 CLI만 직접 사용. 시스템 CLI symlink 변경 없음 |

실제 WM bootstrap과 IPC가 시작되어 필수 권한 gate를 통과했음을 확인했다. 별도의 권한 부여는 하지 않았으며, Screen Recording의 허용 상태까지 독립적으로 확인한 것은 아니다.

### Dev 설정 추가 관찰

새 버전은 schema/default 필드, 새 기능 테이블, resize hotkey 정규화 등을 저장한다. 따라서 Dev 설정 전체 파일이 전환 전과 동일하지 않은 것은 예상된다. 마지막 비교에서 `workspaceBar.enabled`가 백업의 true에서 현재 false로 달라진 것도 관찰했다. 이후 사용자가 Workspace Bar를 직접 껐다고 확인했다. 이 차이는 사용자가 의도한 변경으로 확인됐으며, 마이그레이션 회귀로 분류하지 않는다.

사용자 변경을 보존하여 Workspace Bar는 꺼진 상태로 유지하고 기존 Dev 설정 전체를 백업으로 복원하지 않았다. 이 항목의 확인은 완료됐다. Release 설정에는 차이가 없다.

## 4. 실제 창과 규칙 검증

개인 앱·문서 대신 독립적인 AppKit probe를 worktree의 `.cache/manual-validation/`에 만들었다. bundle ID는 `local.omniwm.v080-validation-probe`이며, 내용은 고정된 검증 문구뿐이다. 사용자 앱에 적용되지 않는 임시 규칙 2개를 사용했다.

- 높은 specificity의 title + bundle 규칙: `layout = float`, assignment mode `first-window`, workspace 지정 없음
- bundle 규칙: workspace `9`, assignment mode `all-new-windows`

이는 layout 제공 규칙의 mode를 workspace 제공 규칙의 mode로 잘못 사용하는 의미적 충돌을 실제 runtime에서 확인하기 위한 구성이다.

| 검증 | 실제 결과 |
| --- | --- |
| 초기 창 2개 | 두 창 모두 floating / workspace 9 |
| `all-new-windows` | 다른 workspace로 전환한 뒤 추가한 신규 창 2개도 workspace 9. 총 4개 모두 floating / workspace 9 |
| CLI/IPC mode 조회 | layout 규칙의 `firstWindow`, workspace 규칙의 `allNewWindows`가 각각 정확히 반환됨 |
| mode replace | workspace 규칙을 `first-window`로 교체한 뒤 조회 값 `firstWindow` 확인 |
| 기존 앱 창이 있는 `first-window` | 5번째 신규 창은 지정 workspace 9로 강제되지 않음. 관찰 workspace는 4이며 특정 fallback workspace를 강제하는 검증은 아님 |
| 명시적 `rule apply` | 해당 검증 창을 workspace 8로 이동한 뒤 `rule apply --window` 실행. workspace 9로 다시 이동 |
| 숨김 | probe 전체 5개 창의 `isAppHidden` true, focused-window projection에 probe PID가 남지 않음 |
| 재표시 | probe 전체 5개 창의 `isAppHidden` false로 복구 |
| 정리 | probe 종료, probe 창 0개, 임시 규칙 모두 제거. 기존 rule query 결과가 사전 snapshot과 완전히 동일함을 확인 |

이 과정에서 활성 workspace와 포커스는 잠시 변경됐다. 기존 사용자 창을 이동·닫거나 개인 문서를 편집하지 않았다. 정리 단계에서 workspace 1 복귀 명령을 보냈고, 이후 사용자 작업에 따른 workspace 변화를 강제로 되돌리지 않았다.

검증 driver의 최초 시도는 이미 활성 상태인 workspace로 이동할 때 CLI가 `ignored: no_change`와 exit 1을 반환하는 것을 harness 오류로 처리했다. 창/규칙을 정리한 뒤 이 명시적인 no-op 결과만 허용하도록 driver를 고치고 위 검증 전체를 다시 수행하여 통과했다. 제품 코드나 assertion을 변경한 것은 아니다.

probe 소스·control·결과는 `.cache/manual-validation/`의 로컬 생성물이며 Git에는 포함하지 않는다. 최종 결과는 `probe-results.json`과 위 표에 기록했다. 기존 규칙 원본 snapshot은 `/tmp/omniwm-v080-duke-manual-rules-before.json`이며 개인 규칙을 포함하므로 공유하지 않는다.

## 5. UI·CLI 및 제한적인 Quake 확인

- Dev 설정 창이 실제로 열리며 General / Layouts / Displays의 navigation과 Behavior UI 표시를 확인했다.
- Displays → Behavior에 fork의 `Focus on Monitor Crossing` 선택 UI와 설명이 존재하고, 기존 값 `Last Focused`를 표시한다.
- mode popup의 AX set-value는 도구에서 지원되지 않았고 foreground AX press도 선택 변경을 입증하지 못했다. 설정을 변경했다고 보고하지 않으며 실제 값은 `last`로 남아 있다.
- 검증 종료 시 열었던 Dev 설정 창이 window list에서 사라졌음을 확인했다.
- `ping`, `version`, displays/workspaces/windows/rules query가 실제 Dev IPC에서 성공했다.
- `LC_ALL=C`의 ping과 `LANG=ko_KR.UTF-8`의 version도 성공했다. 이것만으로 모든 Unicode 폭 렌더링을 수동 검증한 것은 아니며, 폭 관련 unit regression은 별도 자동 검증에 포함된다.
- Quake 설정의 provider는 기본 Ghostty이며 enable 상태다. toggle 명령 수락, Dev 소유 창의 표시/숨김 변화, `/usr/bin/login` 및 zsh child 생성은 관찰했다.
- Quake window가 focus 변화에 따라 사라져 GUI에서 입력·렌더링까지 안정적으로 확인하지 못했다. `ps eww`는 해당 shell 환경 자체를 보여주지 않아 **NO_COLOR 미존재 여부를 판정할 근거가 없었다**. 단순히 검색 결과가 없다는 이유로 통과 처리하지 않는다.
- 시작 직후 Now Playing helper와 번들 dylib 경로의 프로세스 실행을 관찰했다. 실제 재생·제어 기능 통과를 뜻하지 않는다.
- 검증 중 새 OmniWM crash report를 발견하지 못했고 마지막 CLI ping도 성공했다. 모든 crash 가능성을 배제한 것은 아니다.

## 6. 남은 수동 완료 기준

- 다중 모니터 실제 spatial/last-focused crossing, stale selection, suppressed 앱 및 Dwindle group 포커스: **화면 1개라 미실행**.
- 앱 규칙 editor의 UI↔CLI mode 변경 round-trip: CLI/IPC/실제 배정은 확인했으나 editor 조작까지는 미실행.
- 화면 경계 Tab rail 배치·hover/accessibility/재표시: 미실행, 자동 회귀 테스트와 구분.
- Quake 실제 입력·렌더링, 실행 환경의 NO_COLOR 및 외부 Kitty/Foot provider: 미완료.
- 선택적 Screen Recording / Overview capture 및 Now Playing 실제 재생: 미완료.
- opt-in live: compile만 완료. 실제 실행은 별도 검증 필요.

## 7. 종료 상태 및 복귀

Dev는 사용자 승인을 받아 전환한 상태로 계속 실행 중이다. 검증용 probe와 임시 규칙은 남기지 않았다. 로그인 항목, 권한, 영구 전원 설정, 기본 브랜치/보호 설정은 변경하지 않았다. Release 앱과 설정은 보존했다.

Release로 복귀할 때:

```bash
cd /Users/duke/personal/OmniWM-upstream-v0.8.0
make use-release
```

이는 Dev를 정상 종료하고 보존된 Release 앱을 연다. 설정·state 전체를 자동 복구하지는 않는다. 백업 복원이 필요하면 동시 변경을 먼저 확인하고 앱 종료 상태에서 필요한 자료만 선택적으로 복원한다.

위 수동 검증 단계에서는 소스 수정·commit/push·PR 갱신·Draft 해제·main/develop 통합을 하지 않았다. 이후 사용자 병합 요청에 따른 별도 절차는 아래와 같다.

## 8. 사용자 검증 승인 및 병합 결정

사용자는 Workspace Bar를 직접 껐다고 확인한 뒤, 현재까지의 검증이 충분하다고 판단하고 PR #8 병합을 명시적으로 요청했다. 6절의 미실행 항목은 미실행으로 유지하며, 사용자가 이 제약을 수용한 병합 결정과 모든 수동 기능을 통과했다는 주장을 혼동하지 않는다.

- drawer 입력 격리 수정은 검증한 동일 소스로 별도 논리적 커밋 `d1da6cb816912a4b73c8ebaf0e2b5b22da99652d`에 보존했다.
- 검증 문서와 PR 본문을 갱신하고 최신 head의 CI를 확인한 뒤 Draft를 해제하고 **merge commit으로 `develop`에 통합**한다. 실제 병합 완료 여부와 merge SHA는 GitHub PR 상태를 기준으로 확인한다.
- squash/rebase/강제 push, 보호 설정 우회, 기본 브랜치 변경은 하지 않는다. 원격 `main` 갱신은 이 PR 병합 요청에 포함하지 않는다.
- 실행 중인 Dev 앱, 사용자 Workspace Bar 설정, 로컬 백업은 병합 작업에서 변경하지 않는다.
