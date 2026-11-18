package dev.wisdomit.pretendard;

import android.app.Activity;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.ScrollView;
import android.widget.TextView;

/**
 * NEMESIS Manager 에서 Launch 하면 열리는 화면.
 * 왼쪽: 적용 상태, 적용 안 된 이유, 진단. 오른쪽: 이 차의 정보를 채운 이슈 등록 QR.
 * 레이아웃 XML 없이 코드로 만든다 (리소스 빌드를 단순하게 유지하려고).
 */
public final class StatusActivity extends Activity {
    // 차량 화면에 맞춘 어두운 색
    static final int BG = 0xFF111317, CARD = 0xFF1C1F24, CARD2 = 0xFF252931, LINE = 0xFF2A2E35;
    static final int TEXT = 0xFFF2F3F5, SUB = 0xFF9AA0A8, MUTED = 0xFF6B717A;
    static final int GOOD_FG = 0xFF4ADE9B, GOOD_BG = 0xFF143326;
    static final int WARN_FG = 0xFFF5C451, WARN_BG = 0xFF3A2F12;
    static final int BAD_FG = 0xFFFF7B7B, BAD_BG = 0xFF3D1A1A;
    static final int ACCENT = 0xFF3D8BFD, STOP = 0xFF4A4F58;

    /** 차량 상단 상태바(시계)가 앱 위에 겹쳐 그려지는 높이 */
    static final int TOP_INSET_DP = 56;

    /** pfdiag.sh 의 stage 순서와 같아야 한다 */
    static final String[] STAGES = {
        "차량 정보", "저장공간", "시스템 폰트", "다른 폰트 파일", "앱 안의 폰트",
        "사용 중인 폰트", "부팅 순서", "NEMESIS", "마운트 시험" };
    /** 이 시간이 지나면 "평소보다 오래 걸린다" 고 알린다 */
    static final int SLOW_SEC = 180;

    private final Handler ui = new Handler(Looper.getMainLooper());
    private TextView badge, problemTitle, problemBody;
    private LinearLayout problemBox, infoRow, groupBox;
    private Button diagButton;
    private TextView diagHint;
    private LinearLayout diagPanel;
    private TextView diagTitle, diagDetail, summary;
    private ProgressBar diagProgress;
    private final TextView[] stepViews = new TextView[STAGES.length];
    private QrView qr;

    private boolean polling;
    /** 이번에 화면을 연 동안 진단이 도는 것을 봤는가. 아니면 지난 결과는 "지난 진단" 으로만 보여 준다 */
    private boolean sawRunning;
    private boolean running;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        setContentView(build());
    }

    @Override
    protected void onResume() {
        super.onResume();
        refresh();
        poll();   // 화면을 떠난 사이에 진단이 돌고 있었을 수 있다
    }

    @Override
    protected void onPause() {
        super.onPause();
        polling = false;
        ui.removeCallbacksAndMessages(null);
    }

    // ---- 화면 구성 -------------------------------------------------------

    private View build() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.HORIZONTAL);
        root.setBackgroundColor(BG);

        // 왼쪽 (내용이 길어지면 스크롤)
        ScrollView leftScroll = new ScrollView(this);
        leftScroll.setFillViewport(true);
        root.addView(leftScroll, new LinearLayout.LayoutParams(0, -1, 1f));
        LinearLayout left = new LinearLayout(this);
        left.setOrientation(LinearLayout.VERTICAL);
        left.setPadding(dp(32), dp(TOP_INSET_DP), dp(24), dp(16));
        leftScroll.addView(left, new ScrollView.LayoutParams(-1, -1));

        LinearLayout head = row();
        head.setGravity(Gravity.CENTER_VERTICAL);
        TextView title = text("Pretendard System Font", 26, TEXT);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        head.addView(title);
        badge = text("…", 16, TEXT);
        badge.setPadding(dp(14), dp(4), dp(14), dp(4));
        head.addView(badge, margins(-2, -2, dp(16), 0, 0, 0));
        head.addView(new View(this), new LinearLayout.LayoutParams(0, 1, 1f));
        TextView close = text("✕  닫기", 17, TEXT);
        close.setPadding(dp(18), dp(8), dp(18), dp(8));
        close.setBackground(round(CARD2, 8));
        close.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { finish(); }
        });
        head.addView(close);
        left.addView(head);

        problemBox = new LinearLayout(this);
        problemBox.setOrientation(LinearLayout.VERTICAL);
        problemBox.setPadding(dp(16), dp(10), dp(16), dp(12));
        problemTitle = text("", 18, TEXT);
        problemTitle.setTypeface(Typeface.DEFAULT_BOLD);
        problemBody = text("", 15, TEXT);
        problemBox.addView(problemTitle);
        problemBox.addView(problemBody);
        problemBox.setVisibility(View.GONE);
        left.addView(problemBox, margins(-1, -2, 0, dp(14), 0, 0));

        infoRow = row();
        left.addView(infoRow, margins(-1, -2, 0, dp(14), 0, 0));

        groupBox = new LinearLayout(this);
        groupBox.setOrientation(LinearLayout.VERTICAL);
        left.addView(groupBox, margins(-1, -2, 0, dp(10), 0, 0));

        LinearLayout diagRow = row();
        diagRow.setGravity(Gravity.CENTER_VERTICAL);
        diagButton = new Button(this);
        diagButton.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
        diagButton.setTextColor(Color.WHITE);
        diagButton.setPadding(dp(24), dp(10), dp(24), dp(10));
        diagButton.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { if (running) stopDiag(); else startDiag(); }
        });
        setButtonIdle();
        diagRow.addView(diagButton);
        diagHint = text("빠른 진단 · 보통 1분 안팎 · 결과는 꽂아 둔 USB에 저장됩니다", 15, SUB);
        diagRow.addView(diagHint, margins(0, -2, dp(16), 0, 0, 0, 1f));
        left.addView(diagRow, margins(-1, -2, 0, dp(14), 0, 0));

        left.addView(buildDiagPanel(), margins(-1, -2, 0, dp(10), 0, 0));

        left.addView(new View(this), new LinearLayout.LayoutParams(-1, 0, 1f));
        left.addView(text("made by WisdomIT  ·  github.com/WisdomIT/pretendard-systemfont", 13, SUB),
                margins(-2, -2, 0, dp(12), 0, 0));

        // 오른쪽: 이슈 QR
        LinearLayout right = new LinearLayout(this);
        right.setOrientation(LinearLayout.VERTICAL);
        right.setGravity(Gravity.CENTER);
        right.setBackgroundColor(CARD);
        right.setPadding(dp(24), dp(TOP_INSET_DP), dp(28), dp(20));
        root.addView(right, new LinearLayout.LayoutParams(dp(330), -1));

        qr = new QrView(this);
        right.addView(qr, new LinearLayout.LayoutParams(dp(230), dp(230)));
        TextView qrTitle = text("문제 신고 · 기능 제안", 19, TEXT);
        qrTitle.setTypeface(Typeface.DEFAULT_BOLD);
        qrTitle.setGravity(Gravity.CENTER);
        right.addView(qrTitle, margins(-2, -2, 0, dp(14), 0, 0));
        TextView qrCaption = text("휴대폰으로 스캔하면 GitHub 이슈 작성 화면이 열립니다. 이 차의 펌웨어와 버전이 미리 채워집니다. 진단을 했다면 SUMMARY.txt를 첨부해 주세요.", 14, SUB);
        qrCaption.setGravity(Gravity.CENTER);
        right.addView(qrCaption, margins(-1, -2, 0, dp(6), 0, 0));
        return root;
    }

    private View buildDiagPanel() {
        diagPanel = new LinearLayout(this);
        diagPanel.setOrientation(LinearLayout.VERTICAL);
        diagPanel.setBackground(round(CARD, 10));
        diagPanel.setPadding(dp(16), dp(12), dp(16), dp(12));
        diagPanel.setVisibility(View.GONE);

        diagTitle = text("", 17, TEXT);
        diagTitle.setTypeface(Typeface.DEFAULT_BOLD);
        diagPanel.addView(diagTitle);

        diagProgress = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        diagProgress.setMax(STAGES.length);
        diagPanel.addView(diagProgress, margins(-1, dp(8), 0, dp(10), 0, 0));

        // 9단계를 3열로
        for (int r = 0; r < 3; r++) {
            LinearLayout line = row();
            for (int c = 0; c < 3; c++) {
                int i = r * 3 + c;
                stepViews[i] = text("", 15, MUTED);
                line.addView(stepViews[i], new LinearLayout.LayoutParams(0, -2, 1f));
            }
            diagPanel.addView(line, margins(-1, -2, 0, r == 0 ? 0 : dp(4), 0, 0));
        }

        diagDetail = text("", 14, SUB);
        diagPanel.addView(diagDetail, margins(-1, -2, 0, dp(10), 0, 0));

        summary = text("", 13, SUB);
        summary.setTypeface(Typeface.MONOSPACE);
        summary.setVisibility(View.GONE);
        diagPanel.addView(summary, margins(-1, -2, 0, dp(10), 0, 0));
        return diagPanel;
    }

    // ---- 상태 ----------------------------------------------------------

    private void refresh() {
        new Thread(new Runnable() {
            @Override public void run() {
                final Info info = new Info(Root.script("info.sh", 15));
                ui.post(new Runnable() { @Override public void run() { show(info); } });
            }
        }).start();
    }

    private void show(Info info) {
        int lv = info.level();
        badge.setText(info.badge());
        badge.setTextColor(lv == Info.GOOD ? GOOD_FG : lv == Info.WARN ? WARN_FG : BAD_FG);
        badge.setBackground(round(lv == Info.GOOD ? GOOD_BG : lv == Info.WARN ? WARN_BG : BAD_BG, 8));

        String[] p = info.problem();
        if (p == null) {
            problemBox.setVisibility(View.GONE);
        } else {
            problemBox.setVisibility(View.VISIBLE);
            problemBox.setBackground(round(lv == Info.BAD ? BAD_BG : WARN_BG, 10));
            problemTitle.setTextColor(lv == Info.BAD ? BAD_FG : WARN_FG);
            problemTitle.setText(p[0]);
            problemBody.setText(p[1]);
        }

        infoRow.removeAllViews();
        addInfo("펌웨어", shortFirmware(info.get("firmware")), 1.6f);
        addInfo("NEMESIS", info.get("nemesis"), 1f);
        addInfo("패키지", info.get("package"), 0.8f);
        addInfo("Pretendard", info.get("pretendard"), 1f);
        addInfo("부팅 안전장치", info.ok ? ("disabled".equals(info.get("state")) ? "꺼짐" : "정상 · 실패 " + info.num("fails") + "회") : "-", 1.3f);

        groupBox.removeAllViews();
        addGroup("Roboto · Android 기본 글꼴", info.kv.get("group.Roboto"));
        addGroup("Mobis · OEM 기본 글꼴", info.kv.get("group.Mobis"));
        addGroup("NanumGothic · 한글 대체 폰트", info.kv.get("group.NanumGothic"));

        qr.setText(info.issueUrl());
    }

    private void addInfo(String k, String v, float weight) {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setBackground(round(CARD, 8));
        box.setPadding(dp(12), dp(8), dp(12), dp(8));
        box.addView(text(k, 13, SUB));
        TextView val = text(v, 16, TEXT);
        val.setSingleLine(true);
        box.addView(val);
        infoRow.addView(box, margins(0, -2, infoRow.getChildCount() == 0 ? 0 : dp(8), 0, 0, 0, weight));
    }

    private void addGroup(String name, String v) {
        LinearLayout r = row();
        r.setPadding(0, dp(6), 0, dp(6));
        r.addView(text(name, 16, TEXT), new LinearLayout.LayoutParams(0, -2, 1f));
        int lv = Info.groupLevel(v);
        r.addView(text(Info.groupText(v), 16, lv == Info.GOOD ? GOOD_FG : lv < 0 ? SUB : WARN_FG));
        groupBox.addView(r);
        View line = new View(this);
        line.setBackgroundColor(LINE);
        groupBox.addView(line, new LinearLayout.LayoutParams(-1, 1));
    }

    private static String shortFirmware(String fw) {
        // DEPEHEV.KOR.S5W_M.V039.001.260902 → DEPEHEV.KOR 260902
        String[] p = fw.split("\\.");
        return p.length >= 6 ? p[0] + "." + p[1] + " " + p[p.length - 1] : fw;
    }

    // ---- 진단 ----------------------------------------------------------

    private void startDiag() {
        diagButton.setEnabled(false);
        diagHint.setText("진단을 시작하는 중…");
        new Thread(new Runnable() {
            @Override public void run() {
                final String r = Root.script("diag.sh start", 20);
                ui.post(new Runnable() { @Override public void run() {
                    diagButton.setEnabled(true);
                    if (r != null && r.startsWith("error no_usb")) {
                        diagHint.setText("USB가 꽂혀 있지 않습니다. USB를 꽂은 뒤 다시 눌러 주세요.");
                        diagHint.setTextColor(WARN_FG);
                    } else if (r == null) {
                        diagHint.setText("진단을 시작하지 못했습니다 (NEMESIS 연결 실패)");
                        diagHint.setTextColor(BAD_FG);
                    } else {
                        sawRunning = true;
                        summary.setVisibility(View.GONE);
                        poll();
                    }
                }});
            }
        }).start();
    }

    private void stopDiag() {
        diagButton.setEnabled(false);
        new Thread(new Runnable() {
            @Override public void run() {
                Root.script("diag.sh stop", 15);
                ui.post(new Runnable() { @Override public void run() { diagButton.setEnabled(true); poll(); } });
            }
        }).start();
    }

    private void poll() {
        if (polling) return;
        polling = true;
        ui.post(new Runnable() {
            @Override public void run() {
                final Runnable self = this;
                new Thread(new Runnable() {
                    @Override public void run() {
                        final Info st = new Info(Root.script("diag.sh status", 10));
                        final boolean done = "done".equals(st.kv.get("state"));
                        final String sum = done && sawRunning ? Root.script("diag.sh summary", 10) : null;
                        ui.post(new Runnable() { @Override public void run() {
                            if (!polling) return;
                            boolean again = showDiag(st, sum);
                            if (again) ui.postDelayed(self, 1000);
                            else polling = false;
                        }});
                    }
                }).start();
            }
        });
    }

    /** 진단 상태를 그린다. 계속 지켜봐야 하면 true. */
    private boolean showDiag(Info st, String sum) {
        String state = st.kv.get("state");
        diagHint.setTextColor(SUB);
        if ("running".equals(state)) {
            sawRunning = true;
            running = true;
            setButtonStop();
            int idx = stageIndex(st.kv.get("stage"));        // 0-based, 시작 전이면 -1
            int sec = st.num("elapsed");
            diagPanel.setVisibility(View.VISIBLE);
            diagTitle.setTextColor(TEXT);
            diagTitle.setText("진단 중 · " + (idx < 0 ? "준비" : (idx + 1) + "/" + STAGES.length + " " + STAGES[idx]));
            diagProgress.setVisibility(View.VISIBLE);
            diagProgress.setProgress(Math.max(idx, 0));
            drawSteps(idx);
            String now = st.kv.get("detail");
            StringBuilder d = new StringBuilder();
            if (now != null && now.length() > 0) d.append("지금: ").append(now).append("\n");
            d.append(sec).append("초 경과 · USB를 뽑지 마세요");
            if (sec >= SLOW_SEC) d.append("\n평소보다 오래 걸리고 있습니다. 더 기다리거나 \"진단 중지\"를 누를 수 있습니다.");
            diagDetail.setText(d.toString());
            diagHint.setText("진단이 끝나면 결과 요약이 아래에 나옵니다");
            return true;
        }
        running = false;
        setButtonIdle();
        if ("done".equals(state)) {
            String dir = st.get("dir");
            String folder = dir.substring(dir.lastIndexOf('/') + 1);
            diagPanel.setVisibility(View.VISIBLE);
            diagProgress.setVisibility(View.VISIBLE);
            diagProgress.setProgress(STAGES.length);
            drawSteps(STAGES.length);
            if (sawRunning) {
                diagTitle.setTextColor(GOOD_FG);
                diagTitle.setText("진단 완료 · " + st.num("elapsed") + "초");
                diagDetail.setText("USB의 " + folder + " 폴더에 저장했습니다. 문제를 알릴 때는 그 안의 SUMMARY.txt를 첨부해 주세요.");
                if (sum != null) { summary.setText(sum.trim()); summary.setVisibility(View.VISIBLE); }
            } else {
                diagTitle.setTextColor(SUB);
                diagTitle.setText("지난 진단 결과 · " + st.get("started") + " 시작");
                diagDetail.setText("USB의 " + folder + " 폴더 (새로 진단하려면 진단 실행을 누르세요)");
                summary.setVisibility(View.GONE);
            }
            return false;
        }
        if ("error".equals(state) && sawRunning) {
            diagPanel.setVisibility(View.VISIBLE);
            diagProgress.setVisibility(View.GONE);
            drawSteps(-1);
            diagTitle.setTextColor(WARN_FG);
            if ("usb_removed".equals(st.kv.get("error"))) {
                diagTitle.setText("USB가 분리되어 진단을 멈췄습니다");
                diagDetail.setText("USB를 다시 꽂고 진단 실행을 눌러 주세요.");
            } else {
                diagTitle.setText("진단을 멈췄습니다");
                diagDetail.setText("다시 실행해 주세요. 계속 끝나지 않으면 이슈로 알려 주세요.");
            }
            summary.setVisibility(View.GONE);
            return false;
        }
        // idle, 또는 이번에 보지 않은 지난 오류: 패널을 숨긴다
        diagPanel.setVisibility(View.GONE);
        diagHint.setText("빠른 진단 · 보통 1분 안팎 · 결과는 꽂아 둔 USB에 저장됩니다");
        return false;
    }

    private void drawSteps(int current) {
        for (int i = 0; i < STAGES.length; i++) {
            if (i < current) { stepViews[i].setText("✓ " + STAGES[i]); stepViews[i].setTextColor(GOOD_FG); }
            else if (i == current) { stepViews[i].setText("● " + STAGES[i]); stepViews[i].setTextColor(ACCENT); }
            else { stepViews[i].setText("○ " + STAGES[i]); stepViews[i].setTextColor(MUTED); }
        }
    }

    /** "4/9 다른 폰트 파일" → 3 */
    static int stageIndex(String stage) {
        if (stage == null) return -1;
        int slash = stage.indexOf('/');
        try { return Integer.parseInt(stage.substring(0, slash).trim()) - 1; }
        catch (Exception e) { return -1; }
    }

    private void setButtonIdle() {
        diagButton.setText("진단 실행");
        diagButton.setBackground(round(ACCENT, 8));
    }

    private void setButtonStop() {
        diagButton.setText("진단 중지");
        diagButton.setBackground(round(STOP, 8));
    }

    // ---- 도우미 --------------------------------------------------------

    private int dp(int v) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, getResources().getDisplayMetrics());
    }

    private TextView text(String s, int sp, int color) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        t.setTextColor(color);
        return t;
    }

    private LinearLayout row() {
        LinearLayout r = new LinearLayout(this);
        r.setOrientation(LinearLayout.HORIZONTAL);
        return r;
    }

    private GradientDrawable round(int color, int radiusDp) {
        GradientDrawable d = new GradientDrawable();
        d.setColor(color);
        d.setCornerRadius(dp(radiusDp));
        return d;
    }

    private static LinearLayout.LayoutParams margins(int w, int h, int l, int t, int r, int b) {
        return margins(w, h, l, t, r, b, 0f);
    }

    private static LinearLayout.LayoutParams margins(int w, int h, int l, int t, int r, int b, float weight) {
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(w, h, weight);
        p.setMargins(l, t, r, b);
        return p;
    }
}
