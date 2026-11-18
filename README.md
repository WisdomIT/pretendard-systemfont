# pretendard-systemfont

현대·기아 Gen5W(S5W_M, Android 4.4) 인포테인먼트의 시스템 폰트를 [Pretendard](https://github.com/orioncactus/pretendard)로 바꾸는 NEMESIS 패키지입니다.
`/system`을 건드리지 않으므로, 패키지나 NEMESIS를 지우면 순정 폰트로 돌아옵니다.

## 현재 상태 (2026-11-18)

**버전 0.1, 실차 1대에서 동작 확인**

| 항목 | 상태 |
|---|---|
| 확인한 차량 | `DEPEHEV.KOR.S5W_M.V039.001.260902`, NEMESIS 1.16.7 |
| 실차 설치·적용 | 확인 |
| 실차 패키지 삭제(Uninstall) 후 순정 복귀 | 확인 |
| NEMESIS 삭제(wipe), 비정상 삭제 후 순정 복귀 | 실차 미확인 (컨테이너 테스트로만 검증) |
| 컨테이너 수명주기 테스트 | 37/37 통과 (`tests/run.sh`) |
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
   packages/pretendard.systemfont-0.1.zip
   ```
3. Android가 켜진 상태에서 USB를 꽂고 확인 창에서 **예**를 누릅니다.
4. **NEMESIS Manager → Settings → Reboot**으로 재부팅합니다.
   - 설치 직후에는 바로 바뀌지 않습니다. 실행 중인 화면과 섞이지 않도록 다음 부팅부터 적용합니다.
   - 시동을 잠깐(3분 정도) 껐다 켜면 Android가 재부팅되지 않고 화면만 꺼졌다 켜집니다(실측). 그래서 적용되지 않습니다. 15분 정도 꺼 두면 재부팅됩니다.
5. **My Packages → Pretendard System Font → Launch**를 누르면 상태가 토스트로 뜹니다. "적용됨 (11/11)"이면 성공입니다.

## 되돌리기

| 방법 | 결과 |
|---|---|
| My Packages → **Uninstall** 후 Reboot | 순정 폰트. 사용 중인 폰트는 재부팅 때 해제됩니다 |
| `nemesis wipe --confirm` (NEMESIS 전체 삭제) | 자동 재부팅 후 순정 |
| NEMESIS가 다른 이유로 사라짐 (비상 삭제, `/data` 초기화, 펌웨어 업데이트) | 다음 부팅부터 순정 |

`/system/fonts`의 원본은 한 번도 바뀌지 않으므로, 복원할 백업이 필요 없습니다.

## 빌드

macOS 또는 Linux에서 `curl`, `unzip`, `python3`가 필요합니다.

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
약 5.2초  zygote가 시스템 폰트를 읽음 → 이미 Pretendard가 보임
```

마운트는 모든 앱 프로세스에 똑같이 보입니다(실차 확인). 그래서 앱마다 따로 손댈 필요가 없습니다.

### 안전장치

- **늦으면 걸지 않습니다.** zygote가 이미 폰트를 읽은 뒤라면(설치 직후 등) 마운트하지 않고 다음 부팅으로 미룹니다. 옛 폰트와 새 폰트가 섞이지 않게 하려는 것입니다.
- **부팅 루프를 막습니다.** 마운트한 부팅이 연속 2번 정상적으로 끝나지 않으면 스스로 꺼지고 순정 폰트로 부팅합니다. 정상 판정은 `sys.boot_completed` 이후 zygote가 60초 유지되는 것입니다. 재설치하면 다시 켜집니다.
- **손상된 폰트는 쓰지 않습니다.** 빌드 때 기록한 md5와 다른 폰트 파일은 건너뜁니다.
- **지울 때 앱이 깨지지 않습니다.** 앱이 열어 둔 폰트는 재부팅 전까지 그대로 유지되고, 열려 있지 않은 것만 즉시 해제합니다.

바꿀 폰트와 굵기는 [map.conf](package/pretendard.systemfont/files/map.conf)에서 정합니다. 자세한 내용은 [package/README.md](package/README.md)에, 실차 측정 기록은 [docs/diag-findings-DEPEHEV-260902.md](docs/diag-findings-DEPEHEV-260902.md)에 있습니다.

## 구성

```
package/pretendard.systemfont/   NEMESIS 패키지
  NEMESIS.data                   패키지 정의
  files/map.conf                 어떤 시스템 폰트를 어떤 굵기로 덮을지
  svc/overlay.sh                 부팅 서비스: 마운트 + 부팅 루프 방지
  scripts/pre.sh post.sh preun.sh  설치 전 검사, 설치 후 안내, 삭제 시 해제
  bin/status.sh                  Manager에서 Launch하면 적용 상태 표시
  lib/common.sh                  공용 함수
tools/fetch_fonts.sh             Pretendard 1.3.9 내려받기 (sha256 검증)
tools/build.py                   패키지 zip과 설치용 USB 구성 생성 → dist/
tests/run.sh                     컨테이너 수명주기 테스트
diag/                            실차 진단 USB (pfdiag: 폰트·부팅 조사, pfqb: 시동 OFF/ON 동작)
docs/                            실차 진단 결과
```

## 라이선스

Pretendard는 SIL Open Font License 1.1이고, "Pretendard"는 예약 이름(RFN)입니다. 이 패키지는 폰트를 수정하지 않고 원본 그대로 넣으며, `fonts/LICENSE.txt`를 함께 배포합니다.
