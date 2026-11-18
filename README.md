# pretendard-systemfont

현대·기아 Gen5W(S5W_M, Android 4.4) 인포테인먼트의 시스템 폰트를 Pretendard로 바꾸는 NEMESIS 패키지입니다.

## 핵심 원칙: 언제든 순정으로

- **패키지를 삭제하면** (`nemesis uninstall pretendard.systemfont`) 원래 시스템 폰트로 돌아옵니다.
- **NEMESIS를 삭제하면** (`nemesis wipe --confirm`) 역시 원래 폰트로 돌아옵니다.
- 원복은 사람이 따로 손댈 필요 없이 자동으로 이뤄져야 합니다.

## 원복 방식 후보

`nemesis wipe`는 설치된 패키지마다 `preuninstall`을 실행합니다. 하나라도 실패하면 wipe를 멈추고, 끝나면 재부팅합니다(`Sources/native/pkg.c` `cmd_wipe`).
그래서 두 경로 모두 `preuninstall`에 원복을 걸 수 있습니다. 다만 NEMESIS CLI가 없을 때 쓰는 USB 비상 삭제 스크립트나 `/data` 초기화는 `preuninstall`을 거치지 않습니다.

| | A안: `/system` 무변경 (bind mount) | B안: 파일 교체 + 백업 복원 |
|---|---|---|
| 방식 | Pretendard는 `/data/nemesis/apps/<id>/`에 두고, 부팅 때마다 원래 폰트 파일 위에 bind mount | `/system/fonts` 원본을 `/data/nemesis/backup/<id>/`에 백업한 뒤 덮어쓰기, 삭제 때 복원 |
| 패키지·NEMESIS 삭제 | 다음 부팅부터 마운트가 없어 **저절로 순정** | `preuninstall`이 복원 |
| 비상 삭제, `/data` 초기화, 펌웨어 업데이트 | 저절로 순정 | 백업이 사라져 **순정 복원 불가** 위험 |
| 부팅 불가 위험 | 낮음 (`/system`은 그대로) | 폰트나 XML이 잘못되면 zygote 반복 재시작 위험 |
| 전제 조건 | zygote가 폰트를 읽기 **전에** 마운트를 걸 수 있어야 함 | `/system` 남은 용량 |

A안이 원칙에 더 맞습니다. 실차 진단 결과 A안이 성립하는 것으로 확인했습니다([docs/diag-findings-DEPEHEV-260902.md](docs/diag-findings-DEPEHEV-260902.md)). NEMESIS 서비스가 zygote의 폰트 로딩보다 약 2.2초 먼저 실행되고, bind mount는 모든 프로세스 네임스페이스에 전파됩니다.

## 구성

```
diag/            실차 진단 USB (1단계)
  usb/NEMESIS.data
  usb/pfdiag.sh
```
