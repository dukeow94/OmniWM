# Upstream v0.8.0 병합 계획

## 1. 목표와 현재 범위

- `OmniNull/OmniWM`의 릴리스 `v0.8.0`을 fork의 `develop`에 통합하면서 fork 전용 동작을 보존한다.
- **Nix/Lix는 설치하지 않는다.** 로컬 개발·검증 경로는 Nix 없이 구성한다.
- 이 계획 커밋에는 조사 결과와 작업 순서만 포함한다. 실제 merge, 의존성 설치·업데이트, Xcode 설정·라이선스 변경, 앱 실행은 수행하지 않는다.
- 작업 브랜치는 `sync/upstream-v0.8.0`, PR 대상은 `develop`이다. 검증이 완료될 때까지 Draft로 유지한다.

## 2. 기준 리비전과 사전 조사

| 대상 | 조사 시점 상태 |
| --- | --- |
| fork `develop` | `dd4da030089a8f83b98b23ee662262049ba0c179` |
| upstream 릴리스 `v0.8.0` | `bf118cca1449468397dee3662acbba5544657545` |
| 로컬 `main` | 위 릴리스 커밋까지 fast-forward 완료 |
| `origin/main` | `3c0783954604eaa9110d0bdb61fa29f953e738ee` (`v0.7.6`), 아직 변경하지 않음 |
| remote | `origin`: `dukeow94/OmniWM`, `upstream`: `OmniNull/OmniWM` |

- `origin/main`에서 `v0.8.0`까지 upstream 커밋은 835개이며, fork `main`에만 있는 커밋은 없다.
- 릴리스 커밋을 고정하여 통합한다. 릴리스 이후의 `upstream/main`은 이번 범위에 포함하지 않는다.
- `develop`에서 `main`을 시험 병합했을 때 10개 파일에 텍스트 충돌이 발생했다. 시험 병합은 취소했고 `develop`은 변경하지 않았다.
- 자동 병합에 성공한 파일에도 의미적 충돌이 있다. 충돌 표시가 없는 파일 역시 fork 차이를 검토해야 한다.

## 3. 병합 전략

### 3.1 Git 작업 순서

1. 작업 시작 시 `origin/develop`을 fetch하고 계획 이후 추가된 변경을 확인한다. 다른 작업을 덮어쓰거나 `develop`을 rebase하지 않는다.
2. 필요하면 최신 `develop`을 작업 브랜치에 merge한다. 기존 계획 커밋은 보존한다.
3. `main`이 정확히 고정된 `v0.8.0` 커밋인지 확인한다. `origin/main` 갱신은 별도 단계에서 일반 fast-forward push로 수행하고 원격 반영을 확인한다. fork 전용 커밋은 넣지 않는다.
4. `sync/upstream-v0.8.0`에서 `main`을 merge한다. 충돌 해결 및 통합에 필수적인 수정은 merge commit에 포함한다.
5. 비-Nix 도구 설정, 추가 회귀 테스트·문서 등 독립적으로 리뷰할 수 있는 변경은 논리적인 후속 커밋으로 분리한다.
6. 모든 검증과 수동 확인 결과를 PR에 기록한 뒤 Draft를 해제한다. 최종적으로 merge commit을 사용하여 `develop`에 통합한다.
7. `main`과 `develop`의 히스토리는 재작성하지 않는다. 원격 브랜치 보호를 우회하지 않는다.

### 3.2 텍스트 충돌 10개

| 파일 | 해결 방향 |
| --- | --- |
| `Sources/OmniWM/Core/Config/SettingsExport.swift` | upstream의 Focus 디코더·기본값 구조와 fork의 `monitorCrossingFocus`를 통합 |
| `Sources/OmniWM/Core/Config/SettingsTOMLMigration.swift` | 서로 다른 스키마 5 마이그레이션을 아래 호환성 설계로 통합 |
| `Sources/OmniWM/Core/Surface/TabRailWindow.swift` | upstream의 WindowServer 배치 구조를 기준으로 fork가 보장하던 프레임 비제약 동작을 검증 |
| `Sources/OmniWM/Resources/Localizable.xcstrings` | 양쪽 문자열을 보존하고 최종 Swift 소스로 재동기화 |
| `Sources/OmniWM/UI/MonitorSettingsTab.swift` | upstream의 Arrangement/Behavior 탭 구조에 fork의 포커스 선택 UI와 설명을 이식 |
| `Tests/OmniWMTests/FocusRoutingSettingsExportTests.swift` | 양쪽 Focus 필드 및 마이그레이션 회귀 테스트 유지 |
| `Tests/OmniWMTests/SettingsMigrationTests.swift` | upstream 단축키 변환 및 fork 필드 보존을 함께 검증 |
| `Tests/OmniWMTests/SettingsTOMLCodecTests.swift` | upstream의 통합된 boolean 테스트와 fork enum round-trip 테스트 유지 |
| `Tests/OmniWMTests/WindowGesturePersistenceTests.swift` | 현재 스키마를 기준으로 검사하도록 유지 |
| `Tests/OmniWMTests/WorkspaceBarAppearanceSettingsTests.swift` | 현재 스키마를 기준으로 검사하도록 유지 |

### 3.3 설정 스키마 충돌: 신규 스키마 6을 제안

현재 양쪽은 같은 버전 번호를 서로 다른 변경에 사용한다.

- 기존 fork 스키마 5: `focus.monitorCrossingFocus`를 추가한다. 이전 단축키 ID가 남아 있을 수 있다.
- upstream 스키마 5: resize 단축키의 이전 ID를 새 ID로 변환한다. `monitorCrossingFocus`는 없다.

버전 숫자만으로 둘을 구분할 수 없으므로 한쪽의 마이그레이션을 그대로 선택하면 안 된다. 다음 설계를 구현 전에 테스트로 고정한다.

1. 통합된 fork의 현재 스키마를 **6**으로 올린다.
2. upstream의 4→5 단축키 변환은 유지한다.
3. 5→6에서는 `monitorCrossingFocus`가 없을 때만 `spatial`을 추가하고, 기존 `last`/`spatial` 값은 보존한다.
4. 5→6에서도 이전 resize 단축키 ID를 멱등적으로 정규화하여 기존 fork 스키마 5를 지원한다. 명시적인 새 ID의 바인딩이 있으면 upstream의 우선순위·검증 규칙을 따른다.
5. upstream 5, fork 5, 양쪽 4 이하에서 6으로 가는 경로를 모두 검증한다. 스키마 5에서 전환된 결과를 재로드하면 추가 마이그레이션이 없어야 한다.
6. 손상된 enum/단축키 값은 임의로 복구하지 않고 기존 오류 처리 정책을 유지한다.
7. 원본 백업, 기존 백업 슬롯 보존, 알 수 없는 키 보존, 미래 버전 쓰기 차단을 검증한다. upstream으로 되돌릴 때는 원본 설정 백업을 사용하도록 안내한다.

### 3.4 자동 병합 이후 반드시 검토할 의미적 충돌

- **앱 규칙 합성**: upstream은 하나의 `userRule` 대신 `ComposedUserRules`에서 속성별로 규칙을 선택한다. 시험 병합 결과의 `MatchedWindowRules.swift`에는 삭제된 `userRule` 참조가 남았다. `workspaceAssignmentMode`는 workspace를 실제로 제공한 규칙(`userRules.workspace`)에서 읽도록 통합하고, layout 제공 규칙과 workspace 제공 규칙이 다른 경우를 검증한다.
- **모든 신규 창의 workspace 배정**: 생성·재평가·수동 적용 경로, placement resolver, IPC projection, CLI parser, UI draft/editor, 설정 round-trip을 함께 검증한다. workspace가 없는 규칙이 배정 모드를 바꾸지 않아야 한다.
- **모니터 이동 포커스**: spatial/last-focused 선택, hidden/suppressed 앱 제외, stale selection 방어, inactive Dwindle group 제외와 upstream 변경의 상호작용을 검증한다.
- **Tab rail 배치**: `constrainFrameRect` override를 무조건 복사하지 않는다. upstream의 `appliedFrame`/WindowServer 배치가 기존 문제를 해결하는지 회귀 테스트로 판단한다.
- **Quake 실행 환경**: fork의 `NO_COLOR` 제거와 테스트를 보존한다. upstream의 새 launcher 경로에서도 환경 변수가 의도치 않게 재유입되지 않는지 확인한다.
- **CLI locale linkage**: fork의 `TerminalCellWidth.swift` 수정과 upstream의 현재 구현을 비교하고 Xcode 27 + 새 snapshot에서 링크·문자 폭 테스트를 실행한다.
- **fork 문서**: `AGENTS.md` 및 추적 설정, 설정 스키마 설명, 앱 규칙·CLI·모니터 포커스 문서를 보존·갱신한다.

## 4. 의존성 조사: 앱 빌드와 검증

아래 상태는 이 작업 머신에서 읽기 전용으로 확인했다. 설치 작업은 수행하지 않았다.

| 의존성 | v0.8.0 요구 사항 / 용도 | 현재 상태 | 계획 |
| --- | --- | --- | --- |
| 하드웨어·OS | Apple Silicon, 빌드 호스트 macOS 27 이상 | arm64, macOS 27.2.1 | 유지. 배포 앱의 최소 OS 26과 빌드 호스트 요건을 구분 |
| Xcode·SDK | Xcode 27+, macOS SDK 27+ | Xcode 27.2 및 SDK 27.2 설치됨 | 재설치 불필요. 라이선스 동의와 개발 경로 선택 필요 |
| Xcode 선택 | 전체 Xcode의 SDK·도구 사용 | 기본 경로가 `/Library/Developer/CommandLineTools` | 작업용 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` 사용을 우선. 시스템 전역 선택 변경은 별도 확인 |
| Xcode 라이선스 | SDK·빌드 도구 사용 전 동의 | 전체 Xcode로 package 검사를 시도했을 때 라이선스 오류 | 사용자가 라이선스를 검토·동의한 뒤 first-launch 구성과 SDK 도구 실행 여부 재확인. 자동 동의하지 않음 |
| Swift snapshot | `.swift-version`: `main-snapshot-2026-11-01`, manifest: Swift 6.5 | 기본 Swift 6.4.2 | **설치 필요**. 임의의 다른 snapshot/안정 버전으로 대체하지 않음 |
| swiftly | upstream Makefile·localization·ARC audit의 툴체인 경로 | 명령 및 `~/.swiftly/bin` 없음 | **설치 필요**. Swift.org 서명 확인 후 user-local 설치. bootstrap은 버전이 고정되어 있지 않으므로 실제 설치 버전을 기록 |
| GhosttyKit | `GhosttyKit.xcframework-v0.8.0.zip`, source `8265e74cd3945c56d59aba3917ff01af33ba3e78` | 저장소의 `Frameworks/` 없음 | **설치 필요**. 릴리스 prebuilt를 받아 체크섬 검증 후 기대 경로에 배치. 소스 빌드하지 않음 |
| SwiftFormat | `0.64.4` (develop의 pin `0.63.0`에서 변경) | 명령·저장소 캐시 없음 | **설치 필요**. upstream의 정확한 버전과 ZIP 체크섬 사용 |
| SwiftLint | `0.65.1` (기존 pin과 동일) | 명령·저장소 캐시 없음 | **설치 필요**. 버전 변경은 없지만 이 머신에는 없음 |
| Python | 3.11+ (`localization.py`가 표준 라이브러리 `tomllib` 사용) | Homebrew Python 3.13.2, `tomllib` 확인 | 유지. 일반 도구·Python 테스트에는 별도 pip 패키지 없음 |
| Fish | completion 및 선택적 실제 shell 테스트 | 3.7.1 | **4.9.3으로 업데이트 제안**. upstream 고정 nixpkgs가 선택한 버전과 일치시켜 검증 차이를 줄임. 앱 컴파일 자체에는 불필요 |
| Nushell | completion 테스트의 `nu` 실행 | 미설치 | **0.116.1 설치 필요**. upstream 고정 nixpkgs 기준 버전. 일반 completion 테스트에도 필요 |
| Bash·Zsh | CLI completion 및 shell 실행 테스트 | `/bin/bash` 3.2.57, `/opt/homebrew/bin/bash` 5.2.26, `/bin/zsh` 5.9 | 유지. 선택적 live test의 두 Bash 경로 모두 존재 |
| Make | Makefile 실행 | `/usr/bin/make`: GNU Make 3.81 | 기존 버전 우선 사용. upstream 도구 묶음에 gnumake가 있으나 현재 테스트도 `/usr/bin/make`를 사용하므로 최신 Make 별도 설치를 필수로 보지 않음 |
| Git·curl·아카이브 도구 | fetch, 다운로드, SHA-256 및 ZIP 검증 | Git 2.54.0, curl, shasum, ditto, tar, unzip, zip 있음 | 유지 |
| Apple 개발·패키징 도구 | clang/clang++, lipo, codesign, security, plutil, pkgutil, installer, xcrun, osascript, open 등 | 경로 존재 | 추가 패키지 설치 대신 Xcode 구성 후 실행 검증 |
| Xcode 문자열·그래픽 도구 | `xcstringstool`, 필요 시 Metal 도구 | Xcode bundle에 `xcstringstool`, `metal`, `actool` 확인 | `xcrun`으로 올바른 Xcode에서 찾고 실행되는지 검증. Metal 추가 컴포넌트 필요 여부는 이 단계에서 판단 |
| Nix/Lix | upstream `make setup`, doctor 및 CI에서 사용 | 미설치 | **설치하지 않음**. 아래 비-Nix 경로로 대체 |

### 4.1 다운로드 pin과 검증 기준

`v0.8.0`의 `Scripts/dev-tools.env` 및 `Scripts/build-metadata.env`를 단일 기준으로 사용한다.

| 아티팩트 | 다운로드 URL | SHA-256 |
| --- | --- | --- |
| GhosttyKit ZIP | `https://github.com/OmniNull/OmniWM/releases/download/v0.8.0/GhosttyKit.xcframework-v0.8.0.zip` | `ae53418a0314fe8a25eeebd5c25856ab1e6bc1d04bb895ffcd5f58097c010dfd` |
| SwiftFormat ZIP | `https://github.com/nicklockwood/SwiftFormat/releases/download/0.64.4/swiftformat.zip` | `bb42fbfb0b9d5f1b8b83db3147087220ea414916fce8c5cf71abaea5ad5a3175` |
| SwiftLint ZIP | `https://github.com/realm/SwiftLint/releases/download/0.65.1/portable_swiftlint.zip` | `c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0` |

- GhosttyKit은 ZIP 검증 외에도 arm64 static archive 검증을 수행한다. 내부 `Frameworks/GhosttyKit.xcframework/macos-arm64/libghostty-internal.a`의 SHA-256은 `8f98f3ad7c31826baf400a96473aab311490837259b608808291d29903e8d06e`이다.
- GitHub 릴리스 API로 Ghostty ZIP 존재·크기 35,579,192 bytes·공개 digest 일치를 확인했고, upstream 다운로드 검사 스크립트의 HEAD 검사도 통과했다. 실제 ZIP 다운로드·내부 파일 검증은 아직 하지 않았다.
- SwiftFormat·SwiftLint는 이 단계에서 URL과 pin을 소스로 확인했다. 실제 설치 전 다운로드 가능 여부 및 SHA-256을 확인한다.
- swiftly는 upstream `Scripts/swift-toolchain.sh`처럼 Swift.org Team ID `V9AUD2URP3` 서명을 확인한다. `.swift-version`에 지정된 snapshot을 설치하고 `swift`, `swiftc`, `swift-demangle`, SwiftPM/swiftbuild를 같은 툴체인으로 맞춘다.
- Fish 4.9.3과 Nushell 0.116.1은 `flake.lock`의 nixpkgs 커밋 `f20cd90e28fe0403873f473b29e42662cd86e8c4`에 있는 패키지 정의를 조회해 확인했다. Nix는 실행하지 않았다. 비-Nix 배포 경로의 해당 버전 제공 여부·아키텍처·체크섬은 설치 전 확인하고 기록한다.

### 4.2 Swift 패키지·vendored 코드·시스템 라이브러리

- 외부 SwiftPM 패키지는 **swift-toml 2.0.0** 하나다. `Package.resolved`의 revision은 `827506c90475e82d5a7f191f950fb3025cbdc0d6`이며 기존 develop과 동일하다. `swift package resolve`로 고정 리비전을 가져오되 무관한 dependency update는 하지 않는다.
- Luau **0.741**, revision `2d88f9b5facaa9e4ec91247b39ae8251bd49a244`는 `Sources/OmniWMLuau`에 vendored되어 있다. 별도 Luau CLI, Lua 패키지, Rust/CMake 설치는 앱 빌드에 필요하지 않다.
- Material Color 및 새 audio tap/Now Playing/script host/shell core 타깃도 저장소 소스에서 빌드한다. 별도 전역 패키지로 설치하지 않는다. 새 C++ 코드에는 Xcode의 C++17 컴파일러·libc++를 사용한다.
- AppKit, ApplicationServices, Carbon, Metal, MetalKit, QuartzCore, Foundation 및 `libz`, `libc++`는 macOS/Xcode가 제공한다. SkyLight와 약하게 링크되는 FoundationModels도 별도 패키지로 설치하지 않는다.
- 개발 패키징에는 새 `libOmniWMNowPlaying.dylib`가 앱 안에 포함·서명되는지 확인한다. 외부 dylib 수동 설치 대상으로 취급하지 않는다.

## 5. 비-Nix 도구 설정 계획

1. `Scripts/dev-tools.env`의 고정 버전·체크섬을 재사용하는 명시적인 비-Nix setup 경로를 추가한다. 기존 develop의 `Scripts/dev-tools.sh`에서 다운로드·검증·기존 파일 보존 동작을 활용하되 upstream의 새 버전과 요구 사항에 맞춘다.
2. 변경 범위를 줄이기 위해 기존 소비 경로 `.cache/flake-tools/bin`은 호환 경로로 유지할 수 있다. 디렉터리 이름이 Nix 설치를 뜻하지 않도록 문서화하고, 실제 경로 변경 여부는 구현 시 결정한다. 도구는 저장소 로컬로 배치하고 전역 버전을 임의로 교체하지 않는다.
3. `Frameworks/GhosttyKit.xcframework`는 검증된 릴리스 ZIP으로 준비한다. 다른 버전의 기존 프레임워크가 있다면 자동 삭제·덮어쓰지 않는다.
4. 다음 소비자들이 같은 도구 경로와 툴체인을 사용하도록 정합성을 맞춘다: Makefile, `Scripts/doctor.sh`, `Scripts/generate_ipc_wire.py`, `.githooks/pre-commit`, `Scripts/localization.py`, `Scripts/package-app.sh`, `Scripts/arc-audit.sh`, shell 테스트.
5. `doctor`가 비-Nix 모드에서도 실제 빌드 의존성만 검사하도록 변경한다. 이름뿐인 `nix` 대체 실행 파일을 만들어 검사를 속이지 않는다.
6. `make build`는 swiftly의 절대 경로를 쓰지만 패키징과 일부 테스트는 PATH의 `swift`를 사용한다. `~/.swiftly/bin`과 도구 디렉터리를 작업용 PATH에 두어 Swift 6.4로 되돌아가는 일이 없게 한다.
7. upstream의 `flake.nix`, `flake.lock`은 동기화 이력 보존을 위해 남길 수 있지만 로컬 필수 경로로 사용하지 않는다. `.envrc`의 Nix 자동 진입도 사용하지 않는다.
8. upstream CI는 setup-lix action과 `nix flake check`, 특수 `xcode-27` runner를 가정한다. fork CI에서는 실제 사용 가능한 runner/Xcode와 비-Nix setup을 명시적으로 선택하고 pin·tooling·build·test 검증을 유지한다. 릴리스·canary workflow는 자동으로 실행하거나 signing secret을 설정하지 않는다.
9. `LauncherExecutionTests.testRealNushellFishZshAndBothBashVersions`의 opt-in live test에는 catalog에 `nix`가 반드시 있어야 한다는 가정이 있다. 이 환경 의존 assertion을 통제된 테스트 fixture로 바꾸거나 비-Nix 지원에 맞게 수정한다. 일반 테스트 전체를 건너뛰는 방식으로 우회하지 않는다.

## 6. 웹 검증용 의존성

fork 문서가 upstream 웹 문서와 함께 변경되므로 웹 검증도 병합 완료 기준에 포함한다. 앱 컴파일만 할 때는 이 섹션이 필수가 아니다.

| 항목 | 요구 사항 | 현재 상태 / 조치 |
| --- | --- | --- |
| Node.js | `website/package.json`: 24.x, CI: **24.15.0** | 활성 버전 26.13.0, 설치 목록에는 18/22/26만 있음. **nvm으로 24.15.0 추가 및 작업용 전환 필요**. 다른 프로젝트의 Node는 제거하지 않음 |
| npm | Node 24 배포에 포함되는 호환 버전 | 활성 npm 11.20.0. Node 24 선택 후 npm 버전 기록, 별도 전역 업데이트는 하지 않음 |
| npm 패키지 전체 | `website/package-lock.json` | `website/node_modules` 없음. **`npm ci`로 lockfile의 직접·전이 의존성 전체 설치 필요** |
| 직접 runtime 패키지 | `@astrojs/starlight` 0.41.9, `astro` 7.4.2, `sharp` 0.35.5 | lockfile 그대로 설치. Sharp의 플랫폼별 바이너리도 npm 경로로 준비 |
| 직접 dev 패키지 | `@astrojs/check` 0.9.10, `typescript` 6.0.3 | lockfile 그대로 설치 |
| override | `postcss-nested`의 `postcss-selector-parser` 7.1.6 | override 유지, `npm update`로 무관한 업그레이드 금지 |

## 7. 선택적 의존성: 이번 병합에 불필요하거나 조건부

| 항목 | 필요한 경우 | 현재 상태 / 방침 |
| --- | --- | --- |
| `OmniWM Dev` 서명 인증서 | 재빌드 시 macOS 권한 유지 | 같은 이름의 유효한 codesigning identity가 조회되지 않음. 선택 사항이며 ad-hoc 서명 가능. 인증서·keychain 자동 변경 금지 |
| Accessibility·Input Monitoring | Dev 앱 수동 실행·입력 검증 | 컴파일 의존성 아님. 실행 시 사용자가 Dev 앱에 직접 허용 |
| Screen Recording | Overview preview 등 캡처 기능 수동 검증 | 선택적 런타임 권한. 자동 변경하지 않음 |
| Kitty·Foot 외부 터미널 | 해당 Quake provider를 선택해 실제 통합 검증 | 기본 GhosttyKit 빌드에는 불필요. Python KittyControl 테스트는 모듈 fixture/mock을 사용하므로 Kitty 설치가 선행 조건이 아님 |
| Zig·gettext·Metal source-build 도구 | GhosttyKit을 소스에서 재빌드하는 별도 작업 | 이번에는 prebuilt 사용. Zig 미설치, msgfmt 있음. **Zig를 설치하거나 최신 Ghostty main을 빌드하지 않음** |
| Pillow·librsvg·HarfBuzz·Icon Composer | 브랜드 아티팩트를 재생성할 때 | PIL·rsvg-convert 없음, hb-view·iconutil·Xcode ictool 있음. 기존 브랜드 아티팩트 사용 시 **설치 불필요** |
| Developer ID·notarytool profile·배포 권한 | 공개 릴리스 서명·공증·배포 | 이번 병합/Dev 실행 범위 밖. 설정하지 않음 |
| doctl | DigitalOcean 웹 배포 | 미설치. 웹 check/build에 불필요, 설치하지 않음 |
| direnv | 개발 환경 자동 로딩 | 설치되어 있으나 필수 아님. `direnv allow`는 실행하지 않음 |

## 8. 검증 순서와 완료 기준

### 8.1 설치 전/후 환경 검증

- [ ] Xcode 라이선스·first-launch·선택 경로를 사용자와 확인한다.
- [ ] 선택한 Xcode에서 SDK 27+, clang, 문자열 도구, 필요한 그래픽 도구를 실행 확인한다.
- [ ] pinned snapshot의 `swift --version` 및 `swift package dump-package`를 검증한다.
- [ ] 다운로드 SHA-256, Ghostty 내부 archive, arm64 아키텍처, SwiftFormat/SwiftLint 버전을 검증한다.
- [ ] Python, Fish, Nushell, Node/npm의 실제 버전·경로를 기록한다.
- [ ] 비-Nix setup을 두 번 실행해 재사용·멱등성과 기존 dependency 보존을 검증한다.

### 8.2 통합·자동 테스트

- [ ] fork의 기존 모니터 포커스/앱 규칙/CLI/Tab rail/NO_COLOR 회귀 테스트를 먼저 실행한다.
- [ ] 규칙 합성 시 workspace 제공 규칙과 assignment mode의 일치 테스트를 추가한다.
- [ ] upstream 5·fork 5·구버전→6, 재로드 멱등성, 설정 백업·unknown key·invalid value·future version 테스트를 추가한다.
- [ ] `make verify`로 formatting, lint, localization, build를 검증한다. **이 명령만으로 테스트를 실행했다고 간주하지 않는다.**
- [ ] `python3 Scripts/generate_ipc_wire.py --check`, `make test-dev-tools`, `make arc-audit`, `make check-pins`를 실행한다.
- [ ] 고정된 Swift로 전체 serial `swift test`를 실행한다. 동시성 변경이 포함된 이번 대규모 upstream 통합에서는 `swift test --parallel`도 실행한다.
- [ ] Swift 명령에 검증된 Ghostty library 경로를 전달하고 필요 시 upstream과 같은 `--build-system swiftbuild --arch arm64 --scratch-path .build/localization`을 사용한다. 서로 다른 빌드 시스템·컴파일러 캐시를 혼용하지 않는다.
- [ ] opt-in live test는 먼저 컴파일하고, GUI/권한이 준비된 환경에서만 실행한다. 실행하지 못한 항목은 PR에 명시한다.
- [ ] Node 24에서 `npm ci`, `npm run reference:check`, `npm run check`, `npm test`, `npm run build`를 실행한다.

### 8.3 수동 확인 및 PR 완료

- [ ] Dev 설정·상태를 release와 분리하고 기존 설정을 보존한다. `make run`이 실행 중인 OmniWM을 종료·전환하므로 사용자 확인 후 수행한다.
- [ ] 모니터 edge crossing의 spatial/last-focused, 숨겨진 앱, stale selection, Dwindle group을 확인한다.
- [ ] 앱 규칙의 first-window/all-new-windows와 여러 규칙의 합성, CLI/IPC/UI round-trip을 확인한다.
- [ ] 화면 경계의 Tab rail 배치, Quake 색상 환경, CLI locale/문자 폭, Now Playing dylib 패키징을 확인한다.
- [ ] 모든 결과·실패·미실행 사유를 PR에 기록한다. 검증 전에는 `develop`에 merge하지 않는다.

## 9. 이번 계획 단계에서 수행한 검증

- Git branch/remote/리비전 및 취소된 시험 병합 결과 조사.
- `v0.8.0`의 Package.swift/Package.resolved, Makefile, 도구 pin, flake/lock, setup/doctor/packaging/localization/ARC/IPC scripts, CI, 관련 테스트 및 웹 package/lockfile 조사.
- 머신의 OS·아키텍처·설치 명령·버전·로컬 dependency 디렉터리·Xcode bundle·SDK 파일·선택적 서명 identity 상태 확인.
- GitHub API 및 HEAD 요청으로 Ghostty release asset의 존재와 공개 digest 확인.
- 고정 nixpkgs 소스에서 Fish·Nushell 버전 조회. Nix/Lix 설치·실행 없음.
- 실제 빌드·테스트는 수행하지 않았다. 기존 package 검사 시도는 Xcode 라이선스 오류로 중단됐으며, pinned Swift와 GhosttyKit 등도 아직 준비되지 않았다.

## 10. 조사 근거

별도 표기가 없는 소스 경로는 `v0.8.0` 커밋을 기준으로 한다.

- `CONTRIBUTING.md`, `.swift-version`, `Package.swift`, `Package.resolved`
- `Makefile`, `Scripts/dev-tools.env`, `Scripts/build-metadata.env`, `Scripts/ghostty-preflight.sh`
- `Scripts/swift-toolchain.sh`, `Scripts/doctor.sh`, `Scripts/package-app.sh`, `Scripts/localization.py`, `Scripts/arc-audit.sh`
- `Scripts/generate_ipc_wire.py`, `.githooks/pre-commit`, `flake.nix`, `flake.lock`, `.envrc`
- `.github/actions/setup-swift/action.yml`, `.github/actions/setup-lix/action.yml`, `.github/workflows/ci.yml`, `.github/workflows/website.yml`
- `Tests/OmniWMTests/NuCompletionTestSupport.swift`, `LauncherExecutionTests.swift`, `LauncherTerminalLiveTests.swift`, `Tests/DevToolingTests/test_make_tools.py`, `Tests/KittyControlTests/`
- `website/package.json`, `website/package-lock.json`, `website/README.md`, `Sources/OmniWMLuau/VERSION`, `Scripts/generate-brand-assets.py`
- [GhosttyKit v0.8.0 릴리스](https://github.com/OmniNull/OmniWM/releases/tag/v0.8.0)
- [고정 nixpkgs Fish 정의](https://github.com/NixOS/nixpkgs/blob/f20cd90e28fe0403873f473b29e42662cd86e8c4/pkgs/by-name/fi/fish/package.nix)
- [고정 nixpkgs Nushell 정의](https://github.com/NixOS/nixpkgs/blob/f20cd90e28fe0403873f473b29e42662cd86e8c4/pkgs/by-name/nu/nushell/package.nix)
