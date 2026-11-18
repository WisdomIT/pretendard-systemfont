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
import android.widget.ScrollView;
import android.widget.TextView;

/**
 * NEMESIS Manager 에서 Launch 하면 열리는 화면.
 * 왼쪽: 적용 상태, 적용 안 된 이유, 진단 실행. 오른쪽: 이 차의 정보를 채운 이슈 등록 QR.
 * 레이아웃 XML 없이 코드로 만든다 (리소스 빌드를 단순하게 유지하려고).
 */
public final class StatusActivity extends Activity {
    // 차량 화면에 맞춘 어두운 색
    static final int BG = 0xFF111317, CARD = 0xFF1C1F24, LINE = 0xFF2A2E35;
    static final int TEXT = 0xFFF2F3F5, SUB = 0xFF9AA0A8;
    static final int GOOD_FG = 0xFF4ADE9B, GOOD_BG = 0xFF143326;
    static final int WARN_FG = 0xFFF5C451, WARN_BG = 0xFF3A2F12;
    static final int BAD_FG = 0xFFFF7B7B, BAD_BG = 0xFF3D1A1A;
    static final int ACCENT = 0xFF3D8BFD;

    private final Handler ui = new Handler(Looper.getMainLooper());
    private TextView badge, problemTitle, problemBody, diagStatus, summary, qrCaption;
    private LinearLayout problemBox, infoRow, groupBox;
    private Button diagButton;
    private ScrollView summaryScroll;
    private View spacer;
    private QrView qr;
    private boolean diagPolling;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        setContentView(build());
    }

    @Override
    protected void onResume() {
        super.onResume();
        refresh();
        pollDiag();   // 화면을 떠난 사이에 진단이 돌고 있었을 수 있다
    }

    @Override
    protected void onPause() {
        super.onPause();
        diagPolling = false;
        ui.removeCallbacksAndMessages(null);
    }

    // ---- 화면 구성 -------------------------------------------------------

    private View build() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.HORIZONTAL);
        root.setBackgroundColor(BG);

        // 왼쪽
        LinearLayout left = new LinearLayout(this);
        left.setOrientation(LinearLayout.VERTICAL);
        left.setPadding(dp(32), dp(24), dp(24), dp(16));
        root.addView(left, new LinearLayout.LayoutParams(0, -1, 1f));

        LinearLayout head = row();
        head.setGravity(Gravity.CENTER_VERTICAL);
        TextView title = text("Pretendard System Font", 28, TEXT);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        head.addView(title);
        badge = text("…", 17, TEXT);
        badge.setPadding(dp(14), dp(5), dp(14), dp(5));
        LinearLayout.LayoutParams bp = new LinearLayout.LayoutParams(-2, -2);
        bp.leftMargin = dp(16);
        head.addView(badge, bp);
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
        left.addView(groupBox, margins(-1, -2, 0, dp(12), 0, 0));

        LinearLayout diagRow = row();
        diagRow.setGravity(Gravity.CENTER_VERTICAL);
        diagButton = new Button(this);
        diagButton.setText("진단 실행");
        diagButton.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
        diagButton.setTextColor(Color.WHITE);
        diagButton.setBackground(round(ACCENT, 8));
        diagButton.setPadding(dp(24), dp(10), dp(24), dp(10));
        diagButton.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { startDiag(); }
        });
        diagRow.addView(diagButton);
        diagStatus = text("결과는 USB의 pfdiag 폴더에 저장됩니다", 15, SUB);
        diagRow.addView(diagStatus, margins(0, -2, dp(16), 0, 0, 0, 1f));
        left.addView(diagRow, margins(-1, -2, 0, dp(14), 0, 0));

        summaryScroll = new ScrollView(this);
        summary = text("", 13, SUB);
        summary.setTypeface(Typeface.MONOSPACE);
        summaryScroll.addView(summary);
        summaryScroll.setVisibility(View.GONE);
        left.addView(summaryScroll, margins(-1, 0, 0, dp(10), 0, 0, 1f));

        spacer = new View(this);   // 진단 결과가 없을 때 footer 를 아래로 민다
        left.addView(spacer, new LinearLayout.LayoutParams(-1, 0, 1f));
        TextView made = text("made by WisdomIT  ·  github.com/WisdomIT/pretendard-systemfont", 13, SUB);
        left.addView(made);

        // 오른쪽: 이슈 QR
        LinearLayout right = new LinearLayout(this);
        right.setOrientation(LinearLayout.VERTICAL);
        right.setGravity(Gravity.CENTER);
        right.setBackgroundColor(CARD);
        right.setPadding(dp(24), dp(20), dp(24), dp(20));
        root.addView(right, new LinearLayout.LayoutParams(dp(330), -1));

        qr = new QrView(this);
        right.addView(qr, new LinearLayout.LayoutParams(dp(240), dp(240)));
        TextView qrTitle = text("문제 신고 · 기능 제안", 19, TEXT);
        qrTitle.setTypeface(Typeface.DEFAULT_BOLD);
        qrTitle.setGravity(Gravity.CENTER);
        right.addView(qrTitle, margins(-2, -2, 0, dp(14), 0, 0));
        qrCaption = text("휴대폰으로 스캔하면 GitHub 이슈 작성 화면이 열립니다. 이 차의 펌웨어와 버전이 미리 채워집니다.", 14, SUB);
        qrCaption.setGravity(Gravity.CENTER);
        right.addView(qrCaption, margins(-1, -2, 0, dp(6), 0, 0));
        return root;
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
        addInfo("펌웨어", shortFirmware(info.get("firmware")));
        addInfo("NEMESIS", info.get("nemesis"));
        addInfo("패키지", info.get("package"));
        addInfo("Pretendard", info.get("pretendard"));
        addInfo("부팅 안전장치", info.ok ? ("disabled".equals(info.get("state")) ? "꺼짐" : "정상 · 실패 " + info.num("fails") + "회") : "-");

        groupBox.removeAllViews();
        addGroup("Roboto · Android 기본 글꼴", info.kv.get("group.Roboto"));
        addGroup("Mobis · OEM 기본 글꼴", info.kv.get("group.Mobis"));
        addGroup("NanumGothic · 한글 대체 폰트", info.kv.get("group.NanumGothic"));

        qr.setText(info.issueUrl());
    }

    private void addInfo(String k, String v) {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setBackground(round(CARD, 8));
        box.setPadding(dp(12), dp(8), dp(12), dp(8));
        box.addView(text(k, 13, SUB));
        TextView val = text(v, 16, TEXT);
        val.setSingleLine(true);
        box.addView(val);
        infoRow.addView(box, margins(0, -2, infoRow.getChildCount() == 0 ? 0 : dp(8), 0, 0, 0, 1f));
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
        diagStatus.setText("진단을 시작하는 중…");
        new Thread(new Runnable() {
            @Override public void run() {
                final String r = Root.script("diag.sh start", 20);
                ui.post(new Runnable() { @Override public void run() {
                    if (r != null && r.startsWith("error no_usb")) {
                        diagButton.setEnabled(true);
                        diagStatus.setText("USB를 꽂은 뒤 다시 눌러 주세요");
                    } else if (r == null) {
                        diagButton.setEnabled(true);
                        diagStatus.setText("진단을 시작하지 못했습니다 (NEMESIS 연결 실패)");
                    } else {
                        pollDiag();
                    }
                }});
            }
        }).start();
    }

    private void pollDiag() {
        if (diagPolling) return;
        diagPolling = true;
        ui.post(new Runnable() {
            @Override public void run() {
                final Runnable self = this;
                new Thread(new Runnable() {
                    @Override public void run() {
                        final String s = Root.script("diag.sh status", 10);
                        final String sum = s != null && s.startsWith("done") ? Root.script("diag.sh summary", 10) : null;
                        ui.post(new Runnable() { @Override public void run() {
                            if (!diagPolling) return;
                            String st = s == null ? "" : s.trim();
                            if (st.startsWith("running")) {
                                diagButton.setEnabled(false);
                                diagStatus.setText("진단 중… " + st.substring(7).trim() + "초  (USB를 뽑지 마세요)");
                                ui.postDelayed(self, 2000);
                                return;
                            }
                            diagPolling = false;
                            diagButton.setEnabled(true);
                            if (st.startsWith("done")) {
                                String dir = st.substring(4).trim();
                                diagStatus.setText("진단 완료 · USB의 " + dir.substring(dir.lastIndexOf('/') + 1) + " 폴더");
                                if (sum != null) {
                                    summary.setText(sum);
                                    summaryScroll.setVisibility(View.VISIBLE);
                                    spacer.setVisibility(View.GONE);
                                }
                            } else if (st.startsWith("error")) {
                                diagStatus.setText("진단이 결과 없이 끝났습니다 (USB 분리 또는 시간 초과)");
                            }
                        }});
                    }
                }).start();
            }
        });
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
