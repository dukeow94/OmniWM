# v0.8.0 통합: 새 worktree 로컬 검증

## 1. 기준 및 현재 결론

2026-11-16에 [PR #8](https://github.com/dukeow94/OmniWM/pull/8)의 인수인계를 읽고 검증을 재개했다. 이전 기기 결과는 PR 본문에 있으며, 이 문서는 새 기기의 추가 관찰만 기록한다.

**2026-11-20 최종 재검증에서 최신 drawer 수정이 포함된 소스의 전체 serial 및 parallel이 각각 8,818개, 실패 0개로 통과했다.** build/verify, 집중 회귀, live compile, 웹 및 validation 패키징도 통과했다. 초기 실패·정체와 잠금에 의한 중단은 아래에 이력으로 보존하며, 최종 자동 검증 성공은 9절을 기준으로 한다. 이후 사용자 승인하에 Dev 전환·설정 마이그레이션·실제 창/규칙 smoke 검증도 수행했다(10절). 다중 모니터 등 수동 미검증 항목은 보존한다. 이후 사용자가 이 범위의 검증을 충분하다고 승인하고 PR #8 병합을 명시적으로 요청했다. 승인 이후의 절차는 11절을 기준으로 한다.

- worktree: `/Users/duke/personal/OmniWM-upstream-v0.8.0`
- 브랜치: `sync/upstream-v0.8.0`, PR base `develop`
- 원격 및 시작 소스: `ea1278b712c335bc2fb27ce9a4a31702fa3bce1a`
- 검증 당시 추가 변경: 아래 drawer 입력 격리 및 검증 문서. 동일 소스의 drawer 수정은 이후 `d1da6cb816912a4b73c8ebaf0e2b5b22da99652d`로 커밋했다.

## 2. 환경 준비

- macOS 27.2.1 (`26B131`), arm64, Xcode 27.2 (`27B52`), SDK 27.2.
- 기존 developer 선택 경로 `/Applications/Xcode.app/Contents/Developer` 유지. `xcodebuild -checkFirstLaunchStatus`는 exit 69지만 실제 build/localization 도구는 정상 동작했다. first-launch 설정이나 라이선스를 변경하지 않았다.
- 기존 Swiftly로 `.swift-version`의 `main-snapshot-2026-11-01` 설치. worktree에서 Swift 6.5-dev (`2b0c27dbdd76ed8`) 확인. 기존 Swift 6.4와 전역 기본 선택 유지.
- Python 3.15.2 사용.
- `make setup`으로 checksum-pinned GhosttyKit 0.8.0, SwiftFormat 0.64.4, SwiftLint 0.65.1, Fish 4.9.3, Nushell 0.116.1을 worktree 로컬에 준비했다. 두 번째 실행에서 재사용 확인. Nix/Lix 설치·실행 없음.
- 웹은 공식 Node 24.15.0 darwin-arm64 archive를 공식 `SHASUMS256.txt`와 비교한 뒤 `.cache/node-downloads`에 풀어 사용했다. npm 11.12.1. 기존 시스템 Node 26.12.1이나 shell 설정을 바꾸지 않았다.
- Git 자동 tracking 설정이 `rebase=true`를 적용하여 이 브랜치만 `branch.sync/upstream-v0.8.0.rebase=false`로 설정했다. 히스토리 재작성 없음.

작업용 환경:

```bash
cd /Users/duke/personal/OmniWM-upstream-v0.8.0
export PATH="$HOME/.swiftly/bin:$PWD/.cache/flake-tools/bin:$PATH"
export TOOLCHAIN_DIR="$HOME/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-11-01-a.xctoolchain"
export LIBRARY_PATH="$(./Scripts/ghostty-preflight.sh print-library-dir)${LIBRARY_PATH:+:$LIBRARY_PATH}"
```

테스트는 `env -i`가 아닌 harness shell의 상속 환경에서 실행했다. SwiftPM은 `--build-system swiftbuild --arch arm64 --scratch-path .build/localization`, parallel은 `--num-workers 4`를 사용했다. 최초 verify와 test를 병행했을 때 localization이 scratch lock을 기다렸으며 이후 scratch 공유 작업은 순차 실행했다.

## 3. 자동 검증

| 항목 | 결과와 소스 범위 |
| --- | --- |
| setup 두 번 / doctor / package manifest | 성공, 시작 소스 |
| `make verify` | 시작 소스 및 drawer 수정 후 모두 성공. 최종 format/lint/localization/build 통과, lint 1,698개 파일 위반 0개 |
| 앱·기본 테스트 번들 build | 시작 소스 및 수정 후 성공 |
| `make test-dev-tools` | setup 완료 후 재실행: DevTooling 169개 + KittyControl 24개, 실패·skip 0개 |
| IPC 생성물 / `make check-pins` | 시작 소스에서 concrete encoder 202개 일치 / pin 검사 성공 |
| `make arc-audit` | 시작 소스에서 50-node workload 10,000회 retain/release/Swift allocation/malloc 모두 0, Embedded Swift compile 성공 |
| fork 집중 회귀 | 시작 소스에서 아래 7개 suite 115개 통과 |
| drawer lifecycle | 수정 후 `ShellWidgetBarLifecycleTests` 20개 통과 |
| drawer 상태·VM reload | 수정 후 `ShellDrawerTests` 11개 + `ShellComponentReloadVMTests` 9개 통과 |
| 전체 serial | 2026-11-20, 최신 수정 소스 8,818개, 실패 0개, exit 0 (9절) |
| 전체 parallel | 2026-11-20, 동일 소스 8,818개, 실패 0개, exit 0 (9절) |
| opt-in live compile | 수정 후 `OMNIWM_LIVE_CHECKS=1 swift build --build-tests ... --jobs 4` 성공. 실행은 하지 않음 |
| 기본 테스트 번들 복구 | live flag 없이 `swift build --build-tests ... --jobs 4` 재실행 성공. 현재 scratch는 기본 suite용 |
| 웹 | Node 24.15.0에서 `npm ci`, `reference:check`, `check`(오류·경고 0), 테스트 11개, build 53페이지 성공 |
| validation bundle | 시작 소스 및 수정 후 debug 패키징, ad-hoc 서명, `codesign --verify --deep --strict`, bundled CLI `--help` 성공. 시작 검증에서 Now Playing dylib arm64도 확인 |

도구 테스트 최초 실행은 setup과 병행되어 pre-commit 도구 검사 2개가 skip됐다. setup 완료 후 전체 도구 테스트를 다시 실행하여 skip 없이 193개 통과를 확인했다.

fork 집중 회귀 suite는 `MonitorCrossingFocusTests`, `ForkSchemaSixMigrationTests`, `TerminalCellWidthTests`, `FocusRoutingSettingsExportTests`, `SettingsMigrationTests`, `WorkspaceAssignmentModeTests`, `WindowRuleEngineTests`이다.

명시적인 파일 경로로 Tests까지 넘긴 별도 SwiftLint 시도는 저장소의 기본 검사 범위를 벗어나 기존 대형 테스트 파일 위반을 보고했다. 설정을 완화하지 않았으며 최종 판정은 저장소 계약인 `make verify`의 전체 format/lint 결과를 사용했다.

validation bundle은 `dist/OmniWM Validation v0.8.0.app`, identity는 `com.barut.OmniWM.dev`이다. 최종 bundle에는 미커밋 drawer 변경이 포함되어 있으므로 plist의 기반 git hash `ea1278b71`만으로 clean 원격 소스와 같다고 보지 않는다. 설치·기동하지 않았다.

### 웹 dependency 경고

`npm ci`/`npm audit`는 기존 직접 의존성 Astro의 moderate 취약점 1개를 보고했다(동일 패키지의 advisory 2개). lockfile은 변경하지 않았다.

- [GHSA-mh32-jxcr-mh9f](https://github.com/advisories/GHSA-mh32-jxcr-mh9f): dynamic tag name attribute injection XSS
- [GHSA-r3h5-4585-7x3w](https://github.com/advisories/GHSA-r3h5-4585-7x3w): `@astrojs/node` image endpoint의 case-variant sibling file read

audit는 Astro 7.4.12를 fix로 제시했다. 이 사이트는 static build이며 별도 취약점 영향 검토·업데이트가 필요하다. 이번 통합에 무관한 dependency update나 `npm audit fix`는 수행하지 않았다. build의 빈 `i18n` collection 경고도 기록하며 build 실패로 처리되지는 않았다.

## 4. 전체 suite 및 이전 실패 subset: 실행 순서별 실제 결과

| 순서 | 소스 | 실행 | 결과 |
| --- | --- | --- | --- |
| 1 | 시작 소스 | 이전 실패 5개 suite subset, serial / parallel 각각 | 각 45개 중 40개 통과, 권한 전제조건 5개 실패 |
| 2 | 시작 소스 | 전체 serial | 8,818개 중 권한 전제조건 5개 실패 |
| 3 | 시작 소스 | 전체 parallel | **8,818개, 실패 0개, exit 0** |
| 4 | 시작 소스 | 동일 subset serial 재확인 | 45개 모두 통과 |
| 5 | 시작 소스 | 전체 serial 재확인 | 8,818개 중 drawer 닫힘 assertion 1개 실패. 권한 관련 5개와 이전 focus/icon 실패는 통과 |
| 6 | 시작 소스 | drawer 실패 단독 5회 | 매회 통과 |
| 7 | drawer 수정 후 | 전체 serial | GUI 테스트 3개 실패 후 Luau containment에서 정체, 1,200초 command timeout. 전체 실행 미완료 |
| 8 | drawer 수정 후 | 전체 parallel | 8,818개 실행, GUI 관련 테스트 6개 실패, exit 1 |

### 권한 전제조건

최초 실패 5개는 `KeyboardModeTests` 4개(`Needs a keyboard event tap (Input Monitoring)`)와 `WindowAdmissionIdentityLookupTests.testDefaultLookupCreatesNoAXContextForPolicyExcludedApp` 1개(`Observing AX context creation requires Accessibility trust`)이다. 이후 동일 소스로 통과했지만 원인은 확정하지 않았다. 이 작업에서 권한을 부여하거나 TCC를 변경하지 않았다.

초기 subset에서 `HostedWindowExternalPresentationTests`, `ShellFocusTransferTests`, `ShellIslandInputTests`는 통과했다. 수정 후 화면 잠금 상태의 parallel에서는 이전 인수인계의 Shell focus 실패 3개도 다시 관찰됐다. 단순한 병렬 race나 fork 회귀로 확정하지 않는다.

### 화면 잠금과 최신 실행의 실패

후반부에 `IOConsoleUsers`의 `CGSSessionScreenIsLocked=Yes`와 lock time **18:29:51 KST**를 읽기 전용으로 확인했다. 수정 후 전체 serial은 18:34에 시작했고 parallel도 잠금 상태에서 실행됐다. 잠금을 해제하거나 자동 잠금 정책을 변경하지 않았다.

최신 parallel 실패 테스트 6개:

- `CommandPaletteFocusTests.testPalettePanelIsNonactivatingAndSearchRemainsFocused`: `A locked console cannot grant key-window status`
- `CommandPaletteFocusTests.testAnimatedPaletteRevealsCompactAndExpandsWhileSearchStaysFocused`: reveal/expand/collapse animation timeout 및 height assertion
- `OverridableControlsAccessibilityTests.testResettingAnOverrideLeavesAReadableGlobalLabel`: slider accessibility element nil
- `ShellFocusTransferTests.testIslandPopoutBarAndDrawerTransferKeepsOneLeaseAndOriginalReturnTarget`
- `ShellFocusTransferTests.testStaleSourceCannotReleaseTransferredFocusAndActualHideReleasesIt`
- `ShellIslandInputTests.testFocusTransfersAcrossDisplaysAndStaleCallbacksCannotReleaseNewLease`

최신 serial에서도 첫 3개가 실패한 후 정체됐다. 잠금에 의한 key-window 전제조건 실패는 명확하지만, 다른 모든 오류나 정체가 잠금만으로 발생했다고 확정하지 않는다. 잠금 해제된 안정적인 GUI 환경에서 재검증해야 한다.

### Serial 정체 샘플

command timeout 이후 남은 이 작업의 `swift-test`/`xctest` PID를 확인하고 3초간 sample을 확보한 뒤 해당 두 프로세스만 SIGTERM으로 종료했다. Release 앱은 종료하지 않았다.

관찰:

- main thread는 `ShellComponentReloadVMTests.testDeinitFailureStillCancelsServicesAndCommitsReplacement`의 `while true do end` deinit을 Luau에서 실행 중, CPU 약 99%.
- sample은 `Dispatch Thread Soft Limit: 70 reached`를 보고했다.
- user-interactive global queue의 worker들이 AppKit `-[NSAnimation _runBlocking]`에서 대기 중이었다.
- ScriptVM watchdog queue도 user-interactive global queue를 target으로 사용한다. watchdog starvation은 조사할 후보이지만 root cause로 확정하지 않았고 watchdog runtime 코드를 변경하지 않았다.
- 새 프로세스에서 `ShellComponentReloadVMTests` 9개와 `ShellDrawerTests` 11개는 90초 supervision 하에 모두 즉시 통과했다. 따라서 containment 해결이나 전체 serial 성공으로 간주하지 않는다.

## 5. Drawer 입력 격리 수정

실패한 `testFlushDashboardDrawersStayOpenUntilThePointerLeavesThem`는 가상 pointer 좌표를 보내면서 버튼 상태는 실제 `NSEvent.pressedMouseButtons`에서 읽었다. `ShellEdgeHover`는 버튼을 누른 동안 drawer를 닫지 않도록 설계되어 있어 테스트 중 실제 클릭에 영향을 받을 수 있다. 실패 순간 버튼 값은 기록하지 않아 실제 클릭이 해당 실패의 원인이었다고 확정하지 않는다.

수정:

- `WorkspaceBarManager.mouseButtonsDown` provider의 기본값은 기존과 동일한 `NSEvent.pressedMouseButtons != 0`이다.
- `handleShellEdgeHover`가 이 provider를 읽는다. 제품의 기본 입력/닫힘 정책은 유지한다.
- lifecycle fixture는 버튼 상태를 명시적으로 false로 제공한다.
- 기존 drawer 테스트에서 포인터가 drawer 안에 들어갔다 나온 뒤 버튼이 true이면 유지되고, false이면 닫히는 assertion을 추가했다. 기존 close assertion을 삭제·약화하지 않았다.

변경 파일:

- `Sources/OmniWM/UI/WorkspaceBar/WorkspaceBarManager.swift`
- `Sources/OmniWM/UI/WorkspaceBar/WorkspaceBarManager+Shell.swift`
- `Tests/OmniWMTests/ShellWidgetHostTests.swift`

## 6. 재현 명령 및 로그

위 환경에서:

```bash
swift build --build-tests --build-system swiftbuild --arch arm64 --scratch-path .build/localization --jobs 4
swift test --skip-build --build-system swiftbuild --arch arm64 --scratch-path .build/localization
swift test --skip-build --build-system swiftbuild --arch arm64 --scratch-path .build/localization --parallel --num-workers 4

pattern='OmniWMTests\.(HostedWindowExternalPresentationTests|KeyboardModeTests|WindowAdmissionIdentityLookupTests|ShellFocusTransferTests|ShellIslandInputTests)'
swift test --skip-build --build-system swiftbuild --arch arm64 --scratch-path .build/localization --filter "$pattern"
swift test --skip-build --build-system swiftbuild --arch arm64 --scratch-path .build/localization --filter 'OmniWMTests\.(ShellWidgetBarLifecycleTests|ShellDrawerTests|ShellComponentReloadVMTests)'
```

전체 serial은 hang 가능성이 있으므로 timeout 시 해당 실행의 자식 프로세스도 정리하는 supervision을 사용한다. assertion이나 suite skip으로 회피하지 않는다.

로컬 raw log/sample은 `/tmp/omniwm-v080-duke-*`에 있다. 특히 `full-serial.log`, `full-parallel.log`, `full-serial-recheck.log`는 수정 전, `final-serial.log`, `final-parallel.log`는 수정 후이므로 혼동하지 않는다. `serial-hang.sample.txt`는 종료 전 스택이고, `final-vm-drawer.log`는 새 프로세스의 집중 회귀 결과다. 로그는 Git에 포함하지 않으며 공개 전에 개인 경로·환경 정보를 확인한다. 주요 결과는 이 문서에 보존하며 tmp의 영구 보존을 가정하지 않는다.

## 7. 자동 검증 단계의 안전 경계 및 당시 다음 절차

이 절은 Dev 전환 전 기록이다. 이후 사용자가 승인한 설치·전환과 현재 실행 상태는 10절 및 별도 수동 검증 문서를 우선한다.

- `/Applications/OmniWM.app`은 계속 실행 중이다. `make run`, 기존 앱 종료·교체, Dev 설치·기동은 하지 않았다.
- 기존 Release/Dev 설정·상태, TCC, 인증서/keychain, 로그인 항목, 화면 잠금 정책을 변경하지 않았다. 서명은 worktree 내 validation bundle의 ad-hoc만 수행했다.
- opt-in live는 compile만 했다. 실제 다중 모니터, 규칙, Quake, Overview, Now Playing 및 live runtime은 미검증이다.
- commit/push, PR 본문 갱신·Draft 해제, 원격 main 갱신, develop 병합은 하지 않았다.
- 최신 전체 serial / parallel은 9절에서 완료했다. 다음 주요 단계는 사용자 승인 후 Dev 전환과 실제 WM 수동 검증이다. 보안 설정·자동 잠금을 무단 변경하지 않는다.
- 잠금 해제 상태의 최종 serial에서는 이전 NSAnimation / dispatch-pool starvation이 재현되지 않았다. 이것만으로 잠금을 유일한 root cause로 확정하지 않는다. 재현되면 sample을 추가하고 upstream 동작·테스트 cleanup을 조사하며 watchdog budget이나 assertion을 완화하지 않는다.
- Dev 전환은 실행 중인 Release에 영향을 주므로 사용자 명시적 확인 후 설정 백업·서명·권한을 확인하고 진행한다.

## 8. 2026-11-20 최초 잠금 해제 후 재시도 이력

사용자의 잠금 해제 안내 후 동일한 최신 미커밋 소스에서 전체 serial을 재시작했다. 시작 시 화면 잠금 key는 없었고, 실행 중 5초 간격으로 잠금 상태를 관찰했다.

- 시작: 17:09:32 KST. 약 261초 뒤 `CGSSessionScreenIsLocked=Yes`를 관찰하여 supervision이 실행을 중단했다.
- SwiftPM 자식이 별도 process group을 만들어 group 종료만으로 정리되지 않아, 이 실행의 `swift-test`/`xctest` PID와 경로를 확인하고 두 프로세스를 추가로 종료했다. 정리 후 실행 중인 테스트 프로세스는 없고 기존 Release 앱은 계속 실행 중이다.
- 종료 시점까지 로그에 완료된 XCTest case 6,936개, 실패 0개가 기록됐다. **전체 serial은 미완료이며 전체 통과로 간주하지 않는다.** 잠금이 다시 확인되어 parallel은 시작하지 않았다.
- 로그: `/tmp/omniwm-v080-duke-unlocked-serial.log`, supervision 상태: 같은 이름의 `.json`. 이 자료는 로컬 임시 파일이며 영구 보존을 가정하지 않는다.
- 새 소스 변경이나 권한·앱·자동 잠금 정책 변경 없음. 이 문서에 재시도 결과만 추가했다.
- 이 실행 후에는 전체 serial 및 parallel 동안 화면이 잠기지 않는 안정적인 GUI session이 필요하다고 안내했다. 이후 최종 재시도는 9절에 기록한다.

## 9. 2026-11-20 최종 잠금 해제 상태 검증 — 전체 통과

사용자가 다시 잠금을 해제한 뒤 동일한 최신 미커밋 drawer 수정 소스로 재실행했다. 라이브 compile 이후 기본 flag로 복구해 둔 동일 테스트 번들을 사용했으며 추가 소스 변경, 테스트 skip, assertion 완화는 없었다.

| 실행 | 결과 | 전체 경과 시간 | 잠금 관찰 |
| --- | --- | --- | --- |
| serial | **8,818개, 실패 0개, exit 0** | 402.1초, XCTest 자체 약 397.7초 | 시작·실행 중·종료 시 잠금 없음 |
| parallel (4 workers) | **8,818개, 실패 0개, exit 0** | 522.9초 | 시작·실행 중·종료 시 잠금 없음 |

- serial은 17:30:58 KST에 시작하여 XCTest가 17:37:35에 완료됐다. parallel은 그 뒤 순차 실행했다. scratch 공유 명령을 동시에 실행하지 않았다.
- parallel 로그의 test index는 1~8,818이며 고유 index 8,818개를 확인했다. 테스트 일부만 실행한 결과가 아니다.
- 각 실행 동안에만 별도 `/usr/bin/caffeinate -d -i -w <supervisor PID>`를 사용해 디스플레이·시스템 유휴 잠자기를 억제했다. 각 실행 종료 후 해당 assertion 프로세스를 종료했다. 기존 다른 작업의 caffeinate 프로세스는 건드리지 않았다.
- 잠금 상태를 5초 간격으로 감시했으며 잠금·정체·시간 초과에 의한 supervision 중단은 두 실행 모두 없었다. 자동 잠금·암호·화면 보호기 설정이나 영구 전원 설정은 변경하지 않았다.
- 로그: `/tmp/omniwm-v080-duke-awake-serial.log`, `/tmp/omniwm-v080-duke-awake-parallel.log`. 각 실행의 exit code, 경과 시간, supervision 중단 여부와 마지막 잠금 상태는 같은 이름의 `.json`에 기록했다.
- 초기 권한 전제조건 실패 5개, 이전 focus/icon 실패, drawer 닫힘 assertion, 잠금 상태 GUI 실패 및 Luau containment 정체는 이번 두 전체 실행에서 재현되지 않았다. 모든 이전 원인이 영구 해결됐거나 잠금 하나만이 원인이라고 단정하지 않는다.
- 검증 후 실행 중인 테스트 프로세스가 없고 기존 Release 앱은 계속 실행 중이다. commit/push, PR 갱신·Draft 해제, main/develop 반영, Dev 앱 전환·기동은 하지 않았다.

**이 자동 검증 직후의 다음 단계**는 백업과 사용자 승인 후 Dev 전환이었다. 이어서 수행한 결과는 아래와 같다. 자동 테스트 전체 통과만으로 수동 완료 기준을 대체하지 않는다.

## 10. 사용자 승인 후 Dev 전환 및 런타임 smoke 검증

[상세 수동 검증 기록](upstream-v0.8.0-manual-validation.md)에 백업, 실제 확인 범위와 미검증 항목을 기록했다.

- Release/Dev 설정·state와 이전 Dev 앱을 별도 로컬 디렉터리에 백업했다.
- 기존 `OmniWM Dev` identity로 `make run` 성공. 현재 Dev 0.8.0/protocol 22가 실행 중이며 Release 앱은 보존했다.
- Release 설정 SHA-256 동일, Dev schema 5→6과 `last` 포커스·IPC 보존, `.pre-v6` 원본 백업 일치, Start at Login 꺼짐을 확인했다.
- 별도 AppKit probe 창 5개로 규칙 합성, all-new-windows, first-window, 명시적 rule apply, 숨김/재표시와 focus 제외를 확인했다. 임시 창·규칙 정리 후 기존 규칙 목록이 사전 snapshot과 완전히 같음을 확인했다.
- 화면은 내장 디스플레이 1개라 실제 다중 모니터 crossing을 검증하지 않았다. Tab rail 화면 경계, Quake 입력/환경, Overview capture, Now Playing 재생 및 opt-in live runtime도 아직 미완료다.
- Dev `workspaceBar.enabled`의 true→false 차이는 사용자가 직접 Workspace Bar를 끈 결과라고 확인했다. 사용자 의도대로 꺼진 상태를 유지하며 마이그레이션 회귀로 분류하지 않는다. 전체 Dev 설정을 임의 복원하지 않았고 Release 설정에는 차이가 없다.
- 위 수동 검증 종료 시 Dev를 계속 실행하는 상태였으며 commit/push, PR Draft 해제·병합, main/develop 반영은 하지 않았다. 이후 사용자 병합 요청에 따른 절차는 아래와 같다.

## 11. 사용자 승인에 따른 PR #8 병합 준비

사용자는 Workspace Bar 차이가 직접 조작한 결과임을 확인하고 현재까지의 검증이 충분하다고 판단하여 PR 병합을 명시적으로 요청했다. 남은 미검증 범위를 통과 처리하지 않고 제약을 기록한 채 수용한 결정이다.

- 자동 전체 serial/parallel과 Dev smoke 검증에서 사용한 동일 drawer 수정을 `d1da6cb816912a4b73c8ebaf0e2b5b22da99652d`에 커밋했다. 검증 이후 제품 코드나 테스트 assertion의 추가 변경은 없다.
- 검증 문서를 별도 커밋으로 보존하고 원격 작업 브랜치 및 PR에 반영한다.
- 최신 head의 CI 확인 후 Draft를 해제하고 fork 규칙에 따라 merge commit으로 `develop`에 통합한다. 실제 완료 상태와 merge SHA는 GitHub PR을 기준으로 확인한다.
- shared history 재작성·강제 push·보호 설정 우회·기본 브랜치 변경은 하지 않는다. 원격 main 갱신과 실행 앱/설정 변경도 이번 병합 요청에 포함하지 않는다.
