# 개발 흐름

## 브랜치

| 브랜치 | 용도 | 어디서 만들고 어디로 합치나 |
|---|---|---|
| `main` | **릴리스된 코드만.** main의 모든 커밋은 릴리스 태그(`v<버전>`)와 짝을 이룹니다. | 직접 커밋하지 않습니다. `dev`(또는 `hotfix/*`)에서 PR로만 합칩니다. |
| `dev` | 다음 릴리스를 모으는 통합 브랜치 | 기능·버그 브랜치를 PR로 합칩니다. |
| `feature/<주제>` | 기능 추가 (예: `feature/launcher-font`) | `dev`에서 만들고 `dev`로 PR |
| `fix/<주제>` | 버그 수정 (예: `fix/diag-usb-removed`) | `dev`에서 만들고 `dev`로 PR |
| `release/<버전>` | 릴리스 준비: 버전 올리기, 변경 내역 쓰기 ([RELEASING.md](docs/RELEASING.md)) | `dev`에서 만들고 `dev`로 PR |
| `hotfix/<주제>` | 릴리스된 버전의 급한 수정 | `main`에서 만들고 `main`으로 PR, 릴리스 후 `main`을 `dev`에 합침 |

GitHub 저장소의 기본 브랜치는 `main`으로 둡니다. 처음 오는 사람이 릴리스된 README를 보게 하려는 것입니다. 그래서 **PR을 열 때 대상(base)을 `dev`로 바꾸는 것**을 잊지 마세요.

## 작업 순서

1. `dev`를 최신으로 받습니다.
   ```bash
   git switch dev
   ```
   ```bash
   git pull
   ```
2. 작업 브랜치를 만듭니다.
   ```bash
   git switch -c feature/<주제>
   ```
3. 작업하고 커밋합니다. 커밋 메시지는 무엇을 왜 바꿨는지 적습니다.
4. 테스트를 돌립니다. 전부 통과해야 합니다(Docker 필요).
   ```bash
   tests/run.sh
   ```
5. 푸시하고 **`dev` 대상**으로 PR을 엽니다.
   ```bash
   gh pr create --base dev
   ```
6. 실차에서 확인한 내용이 있으면 PR 설명에 적습니다. 차종, 펌웨어, 결과, 진단 수치를 남겨 주세요.

## 지켜야 할 것

- **기본 패키지는 NEMESIS만 필요합니다.** HMG-API 같은 다른 모드가 필요한 기능(예: 런처 글꼴)은 기본 패키지에 넣지 않습니다. 따로 설치하는 선택 기능으로 분리합니다. 그 기능이 없어도 기본 패키지는 지금처럼 동작해야 합니다.
- **`/system`에 쓰지 않습니다.** 이 패키지의 핵심 약속은 "지우면 순정"입니다. bind mount 방식 밖으로 나가는 변경은 먼저 이슈로 논의합니다.
- **부팅 경로(`svc/overlay.sh`)에서는 프로세스를 띄우지 않습니다.** 셸 내장 기능만 씁니다. zygote가 폰트를 읽기 전에 끝나야 하기 때문입니다. `tests/lifecycle.sh`의 fork 개수 검사가 이를 지킵니다.
- **기기 스크립트는 KitKat toolbox와 mksh에서 돌아야 합니다.** `sed`, `awk`, `printf`, `sort`, `head`, `tail`, `find`는 기기에 없습니다.
- **진단 결과에 개인 정보를 남기지 않습니다.** 시리얼, BT·Wi-Fi·MAC 주소, 사용자 파일 이름, logcat 원본이 해당합니다.
- **OEM 파일을 커밋하지 않습니다.** 진단 결과(`pfdiag-*/`), 순정 폰트, APK가 해당합니다. `.gitignore`가 막고 있습니다.
- 상태 화면 앱은 Android 4.4(API 19)에서 돌아야 합니다. 빌드 때 r8로 API 참조를 확인합니다([README](README.md#직접-빌드해서-설치-개발자용)).

## 버전

- 버전은 `package/pretendard.systemfont/NEMESIS.data`의 `package-version` 한 곳에서 정합니다. 앱 버전과 릴리스 파일 이름, 태그가 모두 여기서 나옵니다.
- NEMESIS는 점으로 구분된 숫자만 받습니다(`0.6`, `0.7`, `1.0`, `1.0.1`).
- 태그는 `v<package-version>`입니다(예: `v0.6`).
- 버전을 올리는 시점은 릴리스 준비 때입니다([docs/RELEASING.md](docs/RELEASING.md)). 기능 브랜치에서는 올리지 않습니다.

## 릴리스

[docs/RELEASING.md](docs/RELEASING.md)를 따릅니다.
