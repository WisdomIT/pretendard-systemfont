# 릴리스 절차

릴리스는 `dev`에 모인 변경을 `main`에 합치고, `main`에서 태그와 GitHub 릴리스를 만드는 것입니다.

## 준비물

- 앱 서명 키 `~/.pretendard-systemfont/app-release.p12`와 비밀번호 파일 `app-release.pass`
  - **릴리스는 항상 이 키로 서명합니다.** 다른 키로 서명하면 기존 사용자의 업데이트가 실패합니다.
  - 키를 잃어버리면 사용자가 Uninstall 후 새로 설치해야 합니다. 반드시 안전한 곳에 백업해 두세요.
- `gh` 로그인, Docker(테스트), JDK 17 이상

## 1. dev에서 릴리스 준비

```bash
git switch dev
```

```bash
git pull
```

```bash
git switch -c release/<버전>
```

1. `package/pretendard.systemfont/NEMESIS.data`의 `package-version`을 올립니다(예: `0.6` → `0.7`).
2. `tests/lifecycle.sh`의 버전 검사(`^package=…$`)도 같은 값으로 바꿉니다.
3. `docs/changes/v<버전>.md`에 바뀐 점을 사용자 눈높이로 적습니다. 릴리스 노트에 그대로 들어갑니다.
4. README의 "개발 현황" 표를 고칩니다. 새로 실차 확인한 차가 있으면 [COMPATIBILITY.md](COMPATIBILITY.md)에도 추가합니다.
5. 확인용 빌드를 합니다. 빌드, 테스트, 릴리스 파일 생성까지 하고 게시는 하지 않습니다.
   ```bash
   tools/release.sh
   ```
   `dist/release/`에 파일이 생깁니다. 가능하면 `pretendard-systemfont-<버전>-usb.zip`으로 실차에 설치해 확인합니다.
6. 커밋하고 `dev`로 PR을 열어 합칩니다.

## 2. dev → main

`dev`에서 `main`으로 PR을 열어 **merge commit**으로 합칩니다.

```bash
gh pr create --base main --head dev --title "Release v<버전>"
```

## 3. main에서 게시

```bash
git switch main
```

```bash
git pull
```

```bash
tools/release.sh --publish
```

`--publish`는 다음을 확인한 뒤 진행합니다.
- 지금 브랜치가 `main`이고, 커밋되지 않은 변경이 없고, `origin/main`과 같은지
- 같은 버전의 태그가 아직 없는지
- 테스트가 모두 통과하는지

그다음 태그 `v<버전>`을 만들어 푸시하고, GitHub 릴리스를 만들어 아래 파일을 올립니다. 릴리스 노트는 설치 안내와 `docs/changes/v<버전>.md`로 만듭니다.

| 파일 | 내용 |
|---|---|
| `pretendard-systemfont-<버전>-usb.zip` | USB 맨 위에 풀면 바로 설치되는 묶음 |
| `pretendard.systemfont-<버전>.zip` | NEMESIS 패키지 하나 |
| `pretendard-systemfont-<버전>-diag-usb.zip` | USB 직접 진단 |
| `SHA256SUMS.txt` | 위 파일들의 sha256 |

## 4. main을 dev에 다시 합치기

`main`과 `dev`의 기록을 맞춰 둡니다.

```bash
git switch dev
```

```bash
git merge --ff-only main || git merge main
```

```bash
git push
```

## 급한 수정 (hotfix)

1. `main`에서 `hotfix/<주제>`를 만들고 수정합니다.
2. 버전을 올립니다(예: `0.6` → `0.6.1`). `docs/changes/v0.6.1.md`를 씁니다.
3. `main`으로 PR을 열어 합칩니다.
4. 위 3단계(게시)와 4단계(dev에 합치기)를 합니다.
