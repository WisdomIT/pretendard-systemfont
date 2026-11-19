# 실차 진단 USB (pfdiag)

Pretendard 패키지를 만들기 전에 실차에서 필요한 정보를 모으는 일회성 스크립트입니다.
NEMESIS `type=execute`로 실행되고 결과는 USB에만 남깁니다.

## 하는 일 / 하지 않는 일

| 수집 | 내용 |
|---|---|
| 펌웨어 | `getprop`, `build.prop`, 커널, CPU (패키지 `os=` 값과 펌웨어별 분기의 근거) |
| 저장공간 | `df`, `/proc/mounts`, `mountinfo`, SELinux 상태 |
| 시스템 폰트 | `/system/fonts` 목록, SELinux 라벨, md5, 폰트 설정 XML, 폰트 파일 사본 |
| 그 밖의 폰트 | `/system`, `/vendor`, `/data/app`, 내비 지도 파티션 등에서 `.ttf/.otf/.ttc` 검색 |
| APK 안의 폰트 | 파일명으로 폰트를 품은 APK를 찾고, 64MB 이하면 복사 |
| 실행 중 폰트 | 프로세스마다 실제로 매핑하거나 열어 둔 폰트 (어떤 앱이 시스템 폰트를 쓰는지) |
| 부팅 순서 | init rc, `install-recovery.sh`, `qb_runtime.sh`, zygote와 NEMESIS의 시작 시각, logcat, dmesg |
| NEMESIS | 버전, 패키지와 서비스 목록, 로그 |
| bind mount 시험 | `/system`을 바꾸지 않는 방식이 이 장치에서 되는지 확인 |

하지 않는 일: `/system` 쓰기, remount rw, `setprop`, `am`, `pm install`, 차량 신호 접근.

bind mount 시험은 `/system/fonts`의 폰트 하나에 **바이트 단위로 같은 사본**을 잠깐 덮었다가
바로 해제합니다. 화면에는 변화가 없고, 해제가 실패해도 재부팅하면 사라집니다. 이 시험을 빼려면
`pfdiag.sh` 위쪽에서 `MOUNT_TEST=0`으로 바꾸면 됩니다.

## 사용법

1. exFAT 또는 FAT32 USB의 **루트**에 `usb/` 폴더 안의 파일 두 개를 복사합니다.
   ```
   NEMESIS.data
   pfdiag.sh
   ```
   `NEMESIS.emergency`는 넣지 않습니다.
2. 차량 시동(ACC ON)을 켜고 Android 화면이 뜬 뒤 USB를 꽂습니다.
3. "실행하시겠습니까" 다이얼로그에서 **예**를 누릅니다.
4. 1~5분 뒤 성공/실패 다이얼로그가 뜰 때까지 **USB를 뽑지 않습니다**.
5. USB의 `pfdiag-<날짜>-<pid>/` 폴더를 통째로 컴퓨터에 옮깁니다. 먼저 `SUMMARY.txt`를 보면 됩니다.

부팅 순서를 정확히 보려면 두 번 돌려 주세요.

- **완전히 끈 뒤 켠 직후** (시동을 끄고 문을 잠근 뒤 수 분 기다렸다가 켜기)
- **잠깐 껐다 켠 직후** (QuickBoot로 켜지는 경우)

## QuickBoot 확인 (usb-qb)

시동을 잠깐 껐다 켰을 때 실제로 다시 부팅하는지 확인합니다. [usb-qb/](usb-qb/)의 `NEMESIS.data`와 `pfqb.sh`를 USB 루트에 복사합니다. 기존 `NEMESIS.data`는 덮어씁니다.

**순서**
1. Android가 켜진 상태에서 USB를 꽂고 **예**를 누릅니다. 이 1회차가 기준이 됩니다.
2. USB를 꽂은 채로 시동을 끄고, 아래 시나리오 중 하나대로 기다린 뒤 다시 켭니다.
3. NEMESIS 다이얼로그가 다시 뜨면 **예**를 누릅니다. 뜨지 않으면 USB를 뽑았다 다시 꽂습니다.
   그래도 뜨지 않으면 이전 스크립트가 멈춰 있는 것입니다. NEMESIS Manager → Settings → Reboot으로 재부팅한 뒤 다시 꽂으세요.
   스크립트는 90초가 지나면 스스로 끝나므로, 고친 버전에서는 이런 일이 생기지 않아야 합니다.
4. 다른 시나리오도 2~3을 반복합니다. 실행할 때마다 USB의 `pfqb-log.txt`에 한 블록씩 덧붙습니다.

| 시나리오 | 방법 |
|---|---|
| A | 시동 OFF 후 10초 안에 다시 ON |
| B | 시동 OFF, 문을 열고 닫고 잠근 뒤 5분 기다렸다 ON |
| C | 시동 OFF, 30분 이상(또는 하룻밤) 기다렸다 ON |

**결과 읽는 법**

| 직전 블록과 비교한 결과 | 의미 | A안 영향 |
|---|---|---|
| `boot_id`가 바뀜, uptime이 작음, 표식 마운트 "없음", 새 `boot_progress_start` | 실제로 다시 부팅함 | 문제 없음 |
| `boot_id`가 그대로, uptime이 이어짐, 표식 마운트 "살아 있음", dmesg에 `PM: suspend` | 절전 후 복귀(suspend/resume), 앱이 그대로 살아 있음 | 문제 없음. 폰트는 마지막 부팅 때 상태로 유지 |
| `boot_id`가 예전 값, 표식 "없음", 새 `boot_progress_start` 없음, dmesg에 `restore`나 `hibernat` | 저장해 둔 이미지로 복원(QuickBoot) | **대책 필요**. 부팅 경로를 건너뜀 |

표식 마운트는 `/data/pfqb/` 안의 작은 파일 두 개 사이의 bind mount입니다. `/system`과 `/data/nemesis`는 건드리지 않고, 재부팅하면 사라집니다. 시험이 끝나면 `pfqb.sh`의 `CLEANUP=0`을 `1`로 바꿔 한 번 더 실행하면 흔적이 지워집니다.

## 결과물 다루기

- 결과에는 OEM 폰트와 APK가 들어갑니다. **저장소에 커밋하지 마세요.** `.gitignore`에서 `pfdiag-*/`를 제외해 두었습니다.
- 공유할 때는 `SUMMARY.txt`, `fonts/config/`, `fonts/ls_fonts.txt`, `fonts/md5.txt`, `boot/`, `mounttest/`면 충분합니다.

## 결과로 정할 것

| 확인할 것 | 결정 |
|---|---|
| bind mount 시험 b)의 OK 여부, zygote/앱 네임스페이스에서 보이는지 | `/system`을 바꾸지 않는 방식(A안)이 가능한지 |
| zygote와 nemesis의 시작 tick, `qb_runtime.sh` 실행 시점 | 마운트를 zygote보다 먼저 걸 수 있는지 |
| 폰트 설정 XML, 한글 대체 폰트 이름 | 어떤 파일을 Pretendard로 덮을지 |
| `/system` 남은 용량 | B안을 쓸 수 있는지, 어떤 굵기를 넣을지 |
| `/system/fonts` 밖의 폰트, APK 안의 폰트, 매핑 결과 | 바뀌지 않는 화면의 범위 |
| md5 | 펌웨어별 원본 지문 (원복 검증 기준) |

## 런처 글꼴 확인 (usb-launcher)

런처가 자체 글꼴(Cube)을 어떻게 불러오는지 확인하기 위한 수집 스크립트입니다. HMG-API에 훅 포인트를 요청하기 전에 근거를 얻으려고 씁니다.

1. [usb-launcher/](usb-launcher/)의 `NEMESIS.data`와 `pflauncher.sh`를 USB 맨 위에 복사합니다. 기존 `NEMESIS.data`는 덮어씁니다.
2. 차에 꽂고 **예**를 누릅니다. 1분 안팎이면 끝납니다.
3. USB 맨 위에 `pflauncher-날짜-시간-번호` 폴더가 생깁니다. 안에는 다음이 들어 있습니다.
   - `app/`: 런처와 Cube 폰트를 넣어 둔 앱들의 `.odex`, 런처 APK
   - `framework/`: 부트 클래스패스 파일 (baksmali용)
   - `bootclasspath.txt`, `firmware.txt`

분석은 컴퓨터에서 합니다.

```bash
python3 tools/dexrefs.py pflauncher-*/app/*.odex
```

- 글꼴 파일 이름 문자열과 `Typeface` 생성 메서드 호출을 함께 쓰는 메서드를 "글꼴 로딩 지점"으로 보여 줍니다.
- **수집한 파일은 기아·현대의 원본입니다. 개인 분석에만 쓰고 GitHub 등에 올리지 마세요.** `.gitignore`가 `pflauncher-*/`를 막고 있습니다.
