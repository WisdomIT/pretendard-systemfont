# pretendard.systemfont 패키지

Gen5W(S5W_M) 인포테인먼트의 시스템 폰트를 Pretendard로 바꾸는 NEMESIS 패키지입니다.
`/system`에는 쓰지 않습니다. 부팅할 때마다 Pretendard를 원래 폰트 파일 위에 bind mount합니다.

## 바뀌는 폰트 ([files/map.conf](pretendard.systemfont/files/map.conf))

| 시스템 폰트 | Pretendard | 쓰이는 곳 |
|---|---|---|
| `Roboto-Regular/Italic` | Regular | Android 기본 글꼴(영문, 숫자) |
| `Roboto-Bold/BoldItalic` | Bold | |
| `Roboto-Light/LightItalic` | Light | |
| `Roboto-Thin/ThinItalic` | Thin | |
| `Mobis-Regular` | Regular | OEM 기본 글꼴(`devicedefault`, 원래 Kia CubeR). 상단바, 후방카메라 등 |
| `Mobis-Bold` | Bold | 원래 CubeBa1 |
| `NanumGothic` | Regular | 한글 대체 폰트 |

`RobotoCondensed`는 그대로 둡니다. 홈 화면, 공조, 블루투스, 음성, 내비 지도처럼 앱이 자체 폰트를 쓰는 화면도 이 패키지로는 바뀌지 않습니다.

## 빌드

```bash
tools/fetch_fonts.sh
```

```bash
python3 tools/build.py
```

- `fetch_fonts.sh`는 Pretendard 1.3.9 공식 릴리스를 받아 sha256을 검증하고, 폰트를 수정하지 않고 그대로 꺼냅니다.
- `build.py`는 `dist/pretendard.systemfont-<버전>.zip`과 USB 구성 `dist/usb/`를 만듭니다.

## 설치

1. `dist/usb/` **안의 내용**(`NEMESIS.data`, `packages/`)을 USB 루트에 복사합니다.
2. Android가 켜진 상태에서 꽂고 **예**를 누릅니다.
3. **NEMESIS Manager → Settings → Reboot**으로 재부팅하면 적용됩니다.
   - 설치 직후에는 바로 바뀌지 않습니다. 이미 실행 중인 화면과 섞이지 않게 하려는 것입니다.
   - 시동을 잠깐 껐다 켜는 것으로는 재부팅되지 않습니다(실측). 15분 정도 꺼 두거나 Manager의 Reboot을 쓰세요.
4. Manager → My Packages → Pretendard System Font → **Launch**로 적용 상태를 볼 수 있습니다.

## 되돌리기

| 방법 | 결과 |
|---|---|
| 패키지 삭제 (`nemesis uninstall pretendard.systemfont` 또는 Manager) | 사용 중이 아닌 폰트는 즉시 해제, 나머지는 **재부팅 후 순정** |
| NEMESIS 삭제 (`nemesis wipe --confirm`) | preuninstall 실행 후 자동 재부팅 → **순정** |
| NEMESIS가 어떤 이유로든 사라짐 (비상 삭제, `/data` 초기화, 펌웨어 업데이트) | 마운트를 걸 주체가 없으므로 **다음 부팅부터 순정** |

`/system/fonts`의 원본 파일은 한 번도 바뀌지 않으므로, 어떤 경우에도 복원할 백업이 필요 없습니다.

## 안전장치

- **zygote가 이미 폰트를 읽었으면 마운트하지 않습니다.** 설치 직후나 NEMESIS가 늦게 뜬 부팅에서는 다음 재부팅으로 미룹니다.
- **부팅 루프를 막습니다.** 마운트한 부팅이 연속 2번 정상 완료되지 않으면 스스로 꺼집니다. 정상 완료는 `sys.boot_completed` 이후 zygote가 60초 동안 유지되는 것으로 판정합니다. 꺼지면 순정 폰트로 부팅되고, 재설치하면 다시 켜집니다.
- **폰트를 검증합니다.** 패키지 안 폰트의 md5가 빌드 때와 다르면 그 폰트를 쓰는 항목은 건너뜁니다.
- **업데이트와 삭제 때 앱이 깨지지 않습니다.** NEMESIS는 기존 폴더를 지운 뒤 새로 복사하고, 파일을 제자리에서 덮어쓰지 않습니다. 사용 중인 폰트는 삭제된 뒤에도 재부팅 전까지 그대로 읽힙니다.

로그는 `/data/nemesis/logs/pretendard.systemfont/overlay.log`, 상태는 `/data/nemesis/state/pretendard.systemfont/`에 있습니다.

## 테스트

```bash
tests/run.sh
```

Docker의 Linux 컨테이너에서 실차 셸(mksh)과 KitKat toolbox 제약을 흉내 내어 수명주기 전체를 검사합니다(37개 항목).

- 설치
- 부팅 적용
- 같은 부팅 재실행
- 부팅 루프 방지
- 업데이트
- 손상 폰트
- 삭제
- NEMESIS 소실

## 라이선스

Pretendard는 SIL OFL 1.1이고, "Pretendard"는 예약 이름(RFN)입니다. 이 패키지는 폰트를 수정하지 않고 원본 그대로 넣습니다. `fonts/LICENSE.txt`가 함께 들어갑니다.
