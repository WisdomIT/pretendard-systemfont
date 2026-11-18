# pretendard-systemfont

현대·기아 Gen5W(S5W_M, Android 4.4) 인포테인먼트의 시스템 폰트를 [Pretendard](https://github.com/orioncactus/pretendard)로 바꾸는 NEMESIS 패키지입니다.
`/system`을 건드리지 않으므로, 패키지나 NEMESIS를 지우면 순정 폰트로 돌아옵니다.

## 현재 상태 (2026-11-18)

**버전 0.5. 폰트 적용, 상태 화면, 진단 버튼은 실차 1대에서 확인**

| 항목 | 상태 |
|---|---|
| 확인한 차량 | `DEPEHEV.KOR.S5W_M.V039.001.260902`, NEMESIS 1.16.7 |
| 실차 설치·적용 | 확인 |
| 실차 패키지 삭제(Uninstall) 후 순정 복귀 | 확인 |
| NEMESIS 삭제(wipe), 비정상 삭제 후 순정 복귀 | 실차 미확인 (컨테이너 테스트로만 검증) |
| 컨테이너 수명주기 테스트 | 62/62 통과 (`tests/run.sh`) |
| 상태 화면 표시 | 확인 (0.2) |
| 진단 버튼 진행 표시 (0.3) | 확인 (빠른 진단 58초, 결과 6.6MB) |
| 진단 결과의 개인 정보 정리 (0.4) | 확인 (재부팅 전후 2회, 식별 정보 없음, 결과 1.1MB) |
| 부팅 때 마운트 시간 단축 (0.5) | 컨테이너 테스트만, **실차 미확인** |
| 다른 차종·펌웨어 | 미확인 |

### 적용 범위 (실차 확인)

**런처의 메인 화면과 앱 목록을 빼면 사실상 전부 Pretendard로 바뀝니다.**

- **내비게이션**과 기본 앱 전부:
  - 전화, 음성 메모, 공조, 발레모드, 카투홈
  - 라디오, DMB, 미디어, 지니뮤직, 멜론
  - 기아 커넥트, 매뉴얼, 시스템 설정
- 앱 목록 화면 **상단의 메뉴 버튼**
- 미디어 재생 중 오른쪽에 뜨는 팝업, 모달 메시지
- 시동을 처음 걸 때 나오는 경고 메시지
- 음성인식 화면과 음성인식을 통한 내비 검색
- NEMESIS Manager 같은 추가 앱

패키지가 덮는 시스템 폰트는 세 가지입니다. 이 앱들이 모두 이 폰트를 거쳐 글자를 그리기 때문에 범위가 넓습니다.
- Android 기본 글꼴 Roboto
- OEM 기본 글꼴 Mobis(원래 Kia CubeR, `devicedefault`)
- 한글 대체 폰트 NanumGothic

**바뀌지 않는 곳: 런처의 메인 화면과 앱 목록**뿐입니다. 런처(`Launcher_WP3.apk`)는 APK 안에 넣어 둔 Cube 폰트(`assets/fonts/CubeN.ttf`)를 직접 불러오기 때문에 시스템 폰트를 거치지 않습니다. HMG-API 모드로 이 호출을 가로채는 방법을 조사했지만 **보류 중**입니다. HMG-API에 hook point를 새로 추가해야 해서 원저장소 PR이나 직접 빌드가 필요합니다.

### 알려진 표시 차이

폰트 모양과 폭이 Cube와 달라서 생기는 작은 차이가 있습니다. 보기에 불편한 정도는 아닙니다.

- 여러 줄로 표시되는 내용 일부에서 **줄 사이 위아래 여백이 조금 좁아 보입니다.** Pretendard의 줄 높이(1.19em)가 원래 Cube(1.49em)보다 낮기 때문입니다.
- 특수문자가 들어간 일부 버튼은 **글자 폭이 넘쳐 다음 줄로 줄바꿈**됩니다.

## 설치

필요한 것: NEMESIS가 설치된 Gen5W 차량, exFAT/FAT32 USB.

1. 패키지를 빌드합니다(아래 "빌드"). 이미 빌드했다면 건너뜁니다.
2. `dist/usb/` **안의 내용**을 USB 루트에 복사합니다.
   ```
   NEMESIS.data                              (type=install)
   packages/pretendard.systemfont-0.5.zip
   ```
3. Android가 켜진 상태에서 USB를 꽂고 확인 창에서 **예**를 누릅니다.
4. **NEMESIS Manager → Settings → Reboot**으로 재부팅합니다.
   - 설치 직후에는 바로 바뀌지 않습니다. 실행 중인 화면과 섞이지 않도록 다음 부팅부터 적용합니다.
   - 시동을 잠깐(3분 정도) 껐다 켜면 Android가 재부팅되지 않고 화면만 꺼졌다 켜집니다(실측). 그래서 적용되지 않습니다. 15분 정도 꺼 두면 재부팅됩니다.
5. **My Packages → Pretendard System Font → Launch**를 누르면 상태 화면이 열립니다. "적용됨 11/11"이면 성공입니다.

## 상태 화면

NEMESIS Manager에서 Launch하면 열리는 화면입니다.

- **왼쪽**:
  - 적용 상태 배지
  - 적용이 안 됐을 때 **원인과 해결 방법**
  - 펌웨어, NEMESIS, 패키지, Pretendard 버전과 부팅 안전장치 상태
  - 폰트 묶음(Roboto, Mobis, NanumGothic)별 적용 여부
  - **진단 실행** 버튼: 빠른 진단(보통 1분 안팎)을 돌려 꽂혀 있는 USB에 결과(`pfdiag-날짜-시간-번호` 폴더)를 저장하고, 요약을 화면에 보여 줍니다. 진행 중에는 9단계 중 어디까지 끝났는지, 지금 무엇을 하는지, 경과 시간이 보이고, 같은 버튼으로 중지할 수 있습니다.
  - 오른쪽 위 **닫기**로 NEMESIS Manager로 돌아갑니다.
- **오른쪽**: 휴대폰으로 스캔하면 GitHub 이슈 작성 화면이 열리는 QR입니다. 이 차의 펌웨어, 버전, 적용 상태가 미리 채워집니다.

화면이 보여 주는 적용 안 된 이유:

| 원인 | 뜻 |
|---|---|
| 재부팅하면 적용됩니다 | 설치 후 아직 재부팅하지 않음 |
| Android보다 늦게 시작해 적용하지 못했습니다 | 이번 부팅에서 NEMESIS가 폰트 로딩보다 늦게 뜸. 계속되면 지원되지 않는 차일 수 있음 |
| 부팅 서비스가 실행되지 않았습니다 | 이번 부팅에 패키지 서비스 기록이 없음 |
| 안전을 위해 스스로 꺼졌습니다 | 적용한 부팅이 연속 2번 정상 완료되지 않음. 재설치하면 다시 켜짐 |
| 바꿀 시스템 폰트를 찾지 못했습니다 | 이 펌웨어에 대상 폰트 파일이 없음 |
| 폰트 파일이 손상되었습니다 / 일부 폰트를 덮어쓰지 못했습니다 | 재설치하거나 진단 결과를 이슈로 보내 주세요 |

## 문제 알리기 (GitHub 이슈)

### 1. 진단 실행
1. exFAT 또는 FAT32 USB를 차에 꽂습니다. 빈 USB면 충분합니다.
2. **NEMESIS Manager → My Packages → Pretendard System Font → Launch**로 상태 화면을 엽니다.
3. **진단 실행**을 누릅니다.
   - 진행 단계, 지금 하는 일, 경과 시간이 표시됩니다. 보통 1분 안팎이면 끝납니다.
   - **"진단 완료"가 뜰 때까지 USB를 뽑지 마세요.** 뽑으면 진단이 멈추고 "USB가 분리되어 진단을 멈췄습니다"가 뜹니다.
4. 끝나면 화면 아래에 결과 요약이 나오고, USB 최상위에 `pfdiag-날짜-시간-번호` 폴더(예: `pfdiag-20261118-222142-3551`)가 생깁니다. 화면의 "진단 완료" 문구에도 폴더 이름이 나옵니다.

### 2. 이슈 작성
- 상태 화면 오른쪽의 **QR**을 휴대폰으로 스캔하면 버그 신고 양식이 열립니다. 펌웨어, 버전, 적용 상태가 미리 채워집니다.
- 컴퓨터에서는 [이슈 작성](https://github.com/WisdomIT/pretendard-systemfont/issues/new/choose)에서 양식을 고르세요.
  - **버그 신고**: 폰트가 적용되지 않음, 화면이 이상함, 설치·삭제 문제
  - **기능 제안**
  - **차량 호환성 보고**: 내 차에서 잘 되는지 알리기. 잘 되는 경우도 환영합니다.
- 문제가 보이는 화면은 **사진**을 함께 올려 주세요.

### 3. 어떤 파일을 올리나요
| 파일 (USB 최상위 `pfdiag-날짜-시간-번호` 폴더 안) | 올리기 | 내용 |
|---|---|---|
| `SUMMARY.txt` | **항상** | 펌웨어, 폰트 구성, 부팅 순서, 적용 상태 요약 |
| `run.log`, `nemesis/pretendard_package.log` | 요청받으면 | 진단 과정과 이 패키지의 부팅 기록 |
| `boot/`, `fonts/config/`, `storage/` | 요청받으면 | 부팅 설정, 폰트 설정 파일, 마운트 정보 |
| `fonts/files/`, `apks/` | **올리지 마세요** | 기아·현대의 폰트와 앱 원본입니다. 상태 화면의 빠른 진단은 만들지 않고, USB 직접 진단(아래)만 만듭니다 |

진단은 개인 정보를 남기지 않도록 만들었습니다. 시리얼 번호, BT·Wi-Fi·MAC 주소를 빼고 저장합니다. logcat은 폰트·부팅 관련 줄만, 파일 목록은 `/system`과 `/vendor`만 남깁니다. 연락처 동기화나 사용자 파일 이름이 섞이지 않게 하려는 것입니다. 그래도 올리기 전에 한 번 훑어보세요.

### Android가 켜지지 않거나 상태 화면을 열 수 없을 때
- **화면이 계속 재부팅되면**: 시동을 끄고 15분 정도 기다렸다 켜 보세요. 폰트를 적용한 부팅이 연속 2번 정상적으로 끝나지 않으면 패키지가 스스로 꺼지고 순정 폰트로 부팅합니다.
- **USB 직접 진단**: [diag/usb/](diag/usb/)의 `NEMESIS.data`와 `pfdiag.sh`를 USB 루트에 복사하고 꽂은 뒤, NEMESIS가 묻는 창에서 **예**를 누릅니다. Android가 켜지지 않는 상태라면 USB 루트에 빈 파일 `NEMESIS.emergency`도 넣으세요.
  - 이 방식은 **전체 진단**입니다. 앱 안의 폰트 검사, OEM 폰트·APK 복사가 포함돼 3~5분 걸리고 결과가 수백 MB입니다.
  - `fonts/files/`와 `apks/`는 올리지 마세요.

## 되돌리기

| 방법 | 결과 |
|---|---|
| My Packages → **Uninstall** 후 Reboot | 순정 폰트. 사용 중인 폰트는 재부팅 때 해제됩니다 |
| `nemesis wipe --confirm` (NEMESIS 전체 삭제) | 자동 재부팅 후 순정 |
| NEMESIS가 다른 이유로 사라짐 (비상 삭제, `/data` 초기화, 펌웨어 업데이트) | 다음 부팅부터 순정 |

`/system/fonts`의 원본은 한 번도 바뀌지 않으므로, 복원할 백업이 필요 없습니다.

## 빌드

macOS 또는 Linux에서 `curl`, `unzip`, `python3`, JDK(17 이상)가 필요합니다. Android SDK는 필요 없습니다. 상태 화면 앱은 `tools/build_apk.sh`가 공개 Maven 저장소에서 버전과 sha256을 고정한 빌드 도구를 받아 만듭니다(aapt2, r8, Android 4.4 라이브러리). `build.py`가 필요할 때 자동으로 부릅니다.

앱 서명 키는 처음 빌드할 때 `~/.pretendard-systemfont/app-release.p12`에 만들어집니다. 업데이트는 같은 키로 서명해야 설치되므로 **꼭 백업해 두세요.**

```bash
tools/fetch_fonts.sh
```

```bash
python3 tools/build.py
```

- `fetch_fonts.sh`는 Pretendard 1.3.9 공식 릴리스를 받아 sha256을 검증합니다.
- `build.py`는 `dist/pretendard.systemfont-<버전>.zip`과 설치용 USB 구성 `dist/usb/`를 만듭니다.

테스트에는 Docker가 필요합니다.

```bash
tests/run.sh
```

## 시스템을 건드리지 않고 폰트를 바꾸는 방법

### 파일을 바꾸지 않고 "위에 겹쳐 보이게" 합니다

- Pretendard 파일은 패키지 폴더(`/data/nemesis/apps/pretendard.systemfont/fonts/`)에만 둡니다.
- 부팅할 때마다 원래 폰트 경로 위에 Pretendard를 **bind mount**합니다. 예를 들어 `/system/fonts/Roboto-Regular.ttf` 위에 겹칩니다.
- bind mount는 리눅스 커널이 메모리에서만 들고 있는 "이 경로를 열면 저 파일을 보여 줘"라는 연결입니다. 앱이 원래 경로를 열면 Pretendard가 보이지만, `/system/fonts`의 원본 파일은 디스크에서 **한 바이트도 바뀌지 않습니다**.
- 이 연결은 디스크에 저장되지 않아서 **전원이 완전히 꺼지면 사라집니다**. 다음 부팅에서 패키지가 다시 걸어 주지 않으면 원래 폰트가 그대로 보입니다.

그래서 순정 복귀에 따로 복원 작업이 필요 없습니다.
- **패키지를 지우면**: 마운트를 거는 주체가 사라집니다.
- **NEMESIS를 지우면**: 마운트를 거는 주체가 사라집니다.
- **`/data`가 초기화되거나 펌웨어가 업데이트되면**: Pretendard 파일 자체가 사라집니다.

어느 경우든 **재부팅하면 순정**입니다. `/system` 파티션에 쓰지 않고, 시스템 설정 파일(`system_fonts.xml` 등)도 고치지 않으며, 백업도 만들지 않습니다.

### 타이밍: Android가 폰트를 읽기 전에 겹칩니다

Android는 부팅 중에 zygote라는 프로세스가 시스템 폰트를 한 번 읽어 두고, 모든 앱이 그것을 물려받습니다. 실차에서 측정한 순서는 이렇습니다.

```
약 2.9초  NEMESIS 시작 → 이 패키지의 부팅 서비스(svc/overlay.sh)가 바로 마운트
약 5.2~5.6초  zygote가 시스템 폰트를 읽음 → 이미 Pretendard가 보임
```

마운트는 모든 앱 프로세스에 똑같이 보입니다(실차 확인). 그래서 앱마다 따로 손댈 필요가 없습니다.

### 안전장치

- **늦으면 걸지 않습니다.** zygote가 이미 폰트를 읽은 뒤라면(설치 직후 등) 마운트하지 않고 다음 부팅으로 미룹니다. 옛 폰트와 새 폰트가 섞이지 않게 하려는 것입니다.
- **부팅 루프를 막습니다.** 마운트한 부팅이 연속 2번 정상적으로 끝나지 않으면 스스로 꺼지고 순정 폰트로 부팅합니다. 정상 판정은 `sys.boot_completed` 이후 zygote가 60초 유지되는 것입니다. 재설치하면 다시 켜집니다.
- **손상된 폰트는 쓰지 않습니다.** 설치할 때 md5로 검증하고, 부팅할 때는 파일 크기로 다시 확인해 다른 파일은 건너뜁니다. 부팅 때 md5를 계산하지 않는 이유는 폰트 로딩 전에 마운트를 빨리 끝내기 위해서입니다.
- **지울 때 앱이 깨지지 않습니다.** 앱이 열어 둔 폰트는 재부팅 전까지 그대로 유지되고, 열려 있지 않은 것만 즉시 해제합니다.

바꿀 폰트와 굵기는 [map.conf](package/pretendard.systemfont/files/map.conf)에서 정합니다. 자세한 내용은 [package/README.md](package/README.md)에, 실차 측정 기록은 [docs/diag-findings-DEPEHEV-260902.md](docs/diag-findings-DEPEHEV-260902.md)에 있습니다.

## 구성

```
package/pretendard.systemfont/   NEMESIS 패키지
  NEMESIS.data                   패키지 정의
  files/map.conf                 어떤 시스템 폰트를 어떤 굵기로 덮을지
  svc/overlay.sh                 부팅 서비스: 마운트 + 부팅 루프 방지
  scripts/pre.sh post.sh preun.sh  설치 전 검사, 설치 후 안내, 삭제 시 해제
  app/PretendardStatus.apk       상태 화면 앱 (빌드 산출물, Launch 대상)
  bin/info.sh, bin/diag.sh       상태 화면이 NEMESIS root 채널로 부르는 상태 조회·진단 실행
  diag/pfdiag.sh                 진단 스크립트 (diag/usb/pfdiag.sh 를 빌드 때 동봉)
  lib/common.sh                  공용 함수
tools/fetch_fonts.sh             Pretendard 1.3.9 내려받기 (sha256 검증)
tools/build_apk.sh               상태 화면 앱 빌드 (Android SDK 없이)
tools/build.py                   패키지 zip과 설치용 USB 구성 생성 → dist/
app/                             상태 화면 앱 소스 (Java, API 19, QR: Nayuki qrcodegen MIT)
.github/ISSUE_TEMPLATE/          버그 신고, 기능 제안, 차량 호환성 보고
tests/run.sh                     컨테이너 수명주기 테스트
diag/                            실차 진단 USB (pfdiag: 폰트·부팅 조사, pfqb: 시동 OFF/ON 동작)
docs/                            실차 진단 결과
```

## 라이선스

Pretendard는 SIL Open Font License 1.1이고, "Pretendard"는 예약 이름(RFN)입니다. 이 패키지는 폰트를 수정하지 않고 원본 그대로 넣으며, `fonts/LICENSE.txt`를 함께 배포합니다.

상태 화면 앱의 QR 코드는 [Nayuki QR Code generator](https://github.com/nayuki/QR-Code-generator)(MIT)로 그립니다. 원본 그대로 `app/third_party/`에 들어 있습니다.
