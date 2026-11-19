# 런처 글꼴 조사

기본 패키지를 설치해도 런처의 메인 화면과 앱 목록만 순정 글꼴로 남습니다. 런처가 시스템 글꼴을 쓰지 않고 APK 안에 넣어 둔 글꼴을 직접 불러오기 때문입니다. 이 문서는 런처가 그 글꼴을 어떻게 불러오는지 확인한 결과입니다.

- 차량: DEPEHEV.KOR.S5W_M.V039.001.260902 (Android 4.4.2)
- 수집: `diag/usb-launcher/pflauncher.sh` (2026-11-19)
- 분석: `python3 tools/dexrefs.py pflauncher-*/app/*.odex`

## 결과

**런처(`Launcher_WP3`)는 `Typeface.createFromAsset(AssetManager, "fonts/CubeN.ttf")`로 글꼴을 불러옵니다.**

- APK 안의 글꼴은 `assets/fonts/CubeN.ttf` 하나뿐입니다.
- 코드에 들어 있는 글꼴 이름 문자열도 `fonts/CubeN.ttf` 하나뿐입니다.
- 이 문자열을 쓰는 곳은 `CustomTextView.init`과 `StrokeTextView.init`입니다. 두 곳 모두 글꼴 도우미 객체 `utils/S`를 거칩니다.
- 실제로 글꼴을 만드는 곳은 `utils/S.W`뿐입니다.
  - 경로별로 `Map`에 저장해 두고 재사용합니다.
  - 처음 한 번만 `Typeface.createFromAsset`를 호출합니다(`invoke-static`).
- 런처가 쓰는 `Typeface` 메서드는 `createFromAsset`과 `getStyle` 두 가지뿐입니다. `create`와 `createFromFile`은 쓰지 않습니다.

런처 글꼴을 바꾸려면 **`Typeface.createFromAsset` 하나만 가로채면 됩니다.** 결과를 저장해 두므로 런처 프로세스 안에서 첫 호출만 바꿔도 충분합니다.

### 다른 앱

| 앱 | 글꼴 | 불러오는 방식 |
|---|---|---|
| HKMC_HomeSetting_WP (홈 편집) | `fonts/CubeN.ttf` | `createFromAsset` (`c/o.b`) |
| HKMC_BtSettings | `fonts/CubeR.ttf`, `fonts/New_HD2.1-Regular_20181005.ttf` | `createFromAsset` |
| HKMC_Climate | 글꼴 이름 없음 | `Typeface.create`(시스템 글꼴 계열). 기본 패키지로 이미 바뀝니다 |
| HKMC_VoiceHandler, RightScreenHome | 글꼴 코드 없음 | 시스템 글꼴. 기본 패키지로 이미 바뀝니다 |

홈 편집 화면도 런처와 같은 방식이라 같은 훅으로 함께 바꿀 수 있습니다.

## 바꾸는 방법 (선택 기능, HMG-API 필요)

기본 패키지는 NEMESIS만으로 동작하고, 앞으로도 그렇게 유지합니다. 런처 글꼴은 HMG-API 모드를 따로 설치하는 선택 기능으로 만듭니다.

- `Typeface.createFromAsset(AssetManager, String)`의 경로가 `fonts/Cube*.ttf`이면 `/system/fonts/Mobis-Regular.ttf`(또는 `-Bold`)로 만든 `Typeface`를 대신 돌려줍니다.
  - 이 파일은 기본 패키지가 Pretendard로 bind mount해 둔 것입니다.
  - 기본 패키지를 지우면 순정 Mobis(Cube)로 돌아갑니다.
  - 그러면 모드만 남아도 런처는 순정 글꼴 그대로 보입니다.
- 적용 대상은 런처와 홈 편집 프로세스로 한정합니다.
- `/system`에는 쓰지 않습니다. 모드를 지우면 바로 순정입니다.

## HMG-API에 요청한 내용

2026-11-19에 [Open-HMG/HMG-API#338](https://github.com/Open-HMG/HMG-API/issues/338)으로 요청했습니다(영문). 아래는 그 요약입니다.

HMG-API는 목록에 있는 훅 포인트만 걸 수 있으므로 새 훅 포인트가 필요합니다. 저장소의 "New hook point" 이슈 양식으로 요청합니다.

> **제목**: New hook point: `framework.typeface.create_from_asset`
>
> **대상**: `android.graphics.Typeface.createFromAsset(android.content.res.AssetManager, java.lang.String)`. static이고 framework.jar에 있습니다.
>
> **쓰임새**: 앱이 APK에 넣어 둔 글꼴을 시스템 글꼴로 바꿉니다. 순정 런처 `Launcher_WP3`와 홈 편집 `HKMC_HomeSetting_WP`는 `fonts/CubeN.ttf`를 이 메서드로만 불러옵니다(S5W_M V039.001.260902에서 확인).
>
> **필요한 동작**: 호출 전에 인자 `path`를 볼 수 있어야 하고, 반환값을 다른 `Typeface`로 바꿀 수 있어야 합니다. 원래 메서드 호출을 건너뛰는 것까지는 필요 없습니다. 호출 후에 반환값만 바꿀 수 있어도 충분합니다.
>
> **범위**: 프로세스나 패키지 이름으로 적용 대상을 좁힐 수 있으면 좋습니다(`com.android.launcher3` 등).
