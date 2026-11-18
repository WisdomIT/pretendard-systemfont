# 실차 진단 결과: DEPEHEV.KOR.S5W_M.V039.001.260902

진단 일시 2026-11-18. 콜드부팅 후 약 4분 뒤에 실행했습니다(uptime 236초). 원본 결과물은 OEM 폰트와 APK가 들어 있어 저장소에 넣지 않았습니다.

## 차량과 시스템

| 항목 | 값 |
|---|---|
| 펌웨어 | `DEPEHEV.KOR.S5W_M.V039.001.260902` |
| Android | 4.4.2 (SDK 19), `tcc897x`, `wp_daudioplus` |
| `/system` | ext4, 남은 공간 669MB. NEMESIS watchdog이 rw로 remount해 둔 상태 |
| `/data` | ext4, 남은 공간 841MB |
| SELinux | Disabled |
| NEMESIS | 1.16.7. HMG-API(`hmgapid`)도 설치되어 있음 |

## 폰트 구성 (`/system/etc/system_fonts.xml`, `fallback_fonts.xml`)

| 역할 | 파일 | 실제 폰트 | 한글 | 사용처 (진단 시점 매핑 기준) |
|---|---|---|---|---|
| 기본 `sans-serif` | `Roboto-Regular/Bold/Italic/BoldItalic.ttf` | Roboto | 없음 | zygote가 미리 읽음. 63개 프로세스 |
| `sans-serif-light`, `-thin`, `-condensed` | `Roboto-Light*`, `Roboto-Thin*`, `RobotoCondensed-*` | Roboto | 없음 | |
| **`devicedefault`** (OEM 기본) | `Mobis-Regular.ttf` / `Mobis-Bold.ttf` | **Kia CubeR / CubeBa1** | 전체 | SystemUI, 후방카메라 등 |
| 한글 대체 폰트(1순위) | `NanumGothic.ttf` | 나눔고딕 | 전체 | Roboto로 그리는 화면의 한글 |
| 그 밖의 대체 폰트 | `DroidSansFallback.ttf` | Droid Sans Fallback | 거의 없음(3자) | 한자 |
| 대체 폰트 목록에만 있음 | `Mobis-Fallback-China.ttf`, `Mobis-Fallback1.ttf` | 파일 없음 | | |

## 시스템 폰트를 바꿔도 그대로인 화면

| 위치 | 폰트 | 비고 |
|---|---|---|
| `Launcher_WP3.apk` assets | CubeN (CubeR) | **홈 화면** |
| `HKMC_HomeSetting_WP.apk` | CubeN | |
| `HKMC_Climate.apk` | CubeB | 공조 |
| `HKMC_BtSettings.apk` | CubeR, New HD2.1 | 블루투스 설정 |
| `HKMC_VoiceHandler.apk` | Cube | 음성인식 |
| `SystemUI.apk` | AndroidClock | 시계 위젯 |
| `/storage/navi2/navi/DATA/COMMON/FONT/` | Cube, New HD, MnSoft, DFHEI 등 15개 | 내비 지도 엔진 |
| `RightScreenHome.apk`(99MB), `HKMC_VehicleSetting.apk`(348MB) | 미확인 | 64MB가 넘어 복사하지 않음 |

APK 파일 이름만 grep해서 찾은 후보는 48개였습니다. 실제로 zip을 열어 보니 폰트가 들어 있는 APK는 위의 6개뿐이었습니다(나머지 2개는 미확인).

## 부팅 순서

```
~2.9s  qb_uid_check (on post-fs-data) → qb_runtime.sh → nemesis watchdog(294) → svcmgr(295)
~3.0s  zygote 프로세스 시작(297)
 4.1s  boot_progress_start
 5.2s  boot_progress_preload_start   ← zygote가 시스템 폰트를 읽는 시점
 7.0s  boot_progress_preload_end
```

- `init.rc`에서 `flash_recovery`는 주석 처리되어 있습니다. NEMESIS는 `qb_runtime.sh` 경로로만 시작됩니다.
- svcmgr는 시작하자마자 등록된 서비스를 모두 실행합니다. `mode=once`만 예외입니다.
- 커널 cmdline에 `androidboot.qb_prebuilt_mode=disable resume=/dev/block/.../snapshot`이 있습니다. 이번 부팅은 일반 콜드부팅이었습니다.

## bind mount 시험

- `/system/fonts/Roboto-Regular.ttf` 위에 같은 내용의 사본을 bind mount했고, 성공했습니다.
- self, zygote, system_server, 앱 프로세스 네임스페이스 **모두에서 보였습니다**(`shared:23` 전파).
- umount도 정상이었습니다. 디렉터리 단위 bind도 동작했습니다.

## 결론

1. **A안(`/system` 무변경, bind mount)이 이 차량에서 성립합니다.** NEMESIS 서비스가 zygote의 폰트 로딩보다 약 2.2초 먼저 실행되고, 마운트는 모든 프로세스에 보입니다.
2. 바꿀 대상은 Roboto(기본), Mobis(`devicedefault`, Kia Cube), NanumGothic(한글 대체)입니다. RobotoCondensed는 Pretendard에 좁은 폭이 없어서 그대로 둡니다.
3. 홈 화면, 공조, 블루투스, 음성, 내비 지도는 앱 자체 폰트를 써서 1단계에서는 바뀌지 않습니다. 2단계 후보:
   - HMG-API 훅으로 `Typeface.createFromAsset` 가로채기
   - 내비 폰트 파일 bind mount
4. 시동 OFF/ON 동작은 아래 QuickBoot 확인에서 정리했습니다. 이미지 복원(hibernation)은 없어서 A안의 위험 요소가 아닙니다.

## QuickBoot 확인 (2026-11-18, `diag/usb-qb/pfqb.sh`)

| 경우 | boot_id | uptime / 경과 시간 | 표식 마운트 | NEMESIS 시작 누적 | 판정 |
|---|---|---|---|---|---|
| 기준 (20:09) | `f970182c` | 1060초 | | 6회 (19:55) | 19:51 콜드부팅 |
| ① 약 15분 OFF 후 ON (20:39) | **`d39bd919`로 바뀜** | 22초 | 없음 | **7회 (+1)** | **콜드부팅**. zygote 새로 시작, boot_progress 새로 기록 |
| ② OFF, 문 열고 바로 ON (20:40) | 같음 | +45.8초 / 46초 | **살아 있음** | 7회 | 재부팅 아님 |
| ③ OFF, 3분 대기 후 ON (20:43) | 같음 | +210.1초 / 210초 | **살아 있음** | 7회 | 재부팅 아님 |

- ②와 ③은 dmesg에 `PM: suspend` 흔적이 없습니다. 커널 로그 시각(약 278초)도 uptime(277.9초)과 같습니다. **suspend조차 들어가지 않고, 화면만 꺼진 채 계속 동작한 것입니다.** "기아 로고 없이 바로 확인 창이 떴다"는 관찰과 맞습니다.
- 저장된 이미지로 복원하는 경우는 관찰되지 않았습니다(`qb_prebuilt_mode=disable`). 꺼지는 경우는 콜드부팅뿐이라, 부팅 때마다 마운트가 다시 걸립니다.
- 콜드부팅으로 넘어가는 OFF 시간의 경계는 3분과 15분 사이로, 정확한 값은 모릅니다.
- 덤: dmesg에 `hmgapi-hook: app_process, exec /system/bin/app_process.hmgapi-stock`가 있습니다. HMG-API가 zygote 실행 파일을 감싸고 있으므로, 2단계(앱 자체 폰트)에서 활용할 수 있습니다.

### 패키지 설계에 주는 의미

- **설치**: 폰트는 다음 **콜드부팅**부터 적용됩니다. 시동을 잠깐 껐다 켜는 것으로는 적용되지 않습니다. postinstall 메시지로 "NEMESIS Manager → Settings → Reboot"을 안내합니다.
- **패키지 삭제**: preuninstall에서 즉시 umount합니다. 이미 실행 중인 앱은 메모리에 Pretendard가 남으므로, 완전한 원복을 위해 재부팅을 안내합니다. 다음 부팅부터는 무조건 순정입니다.
- **NEMESIS wipe**: 끝에서 자동으로 재부팅하므로 바로 순정이 됩니다.
