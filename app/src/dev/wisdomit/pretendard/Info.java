package dev.wisdomit.pretendard;

import java.net.URLEncoder;
import java.util.HashMap;
import java.util.Map;

/** bin/info.sh 의 key=value 출력과, 그것을 사람 말로 바꾼 문구. */
final class Info {
    static final String REPO = "https://github.com/WisdomIT/pretendard-systemfont";

    final Map<String, String> kv = new HashMap<String, String>();
    /** NEMESIS 를 통해 정보를 읽지 못했으면 false */
    final boolean ok;

    Info(String raw) {
        ok = raw != null && raw.contains("state=");
        if (raw == null) return;
        for (String line : raw.split("\n")) {
            int i = line.indexOf('=');
            if (i > 0) kv.put(line.substring(0, i).trim(), line.substring(i + 1).trim());
        }
    }

    String get(String k) {
        String v = kv.get(k);
        return v == null || v.length() == 0 ? "-" : v;
    }

    int num(String k) {
        try { return Integer.parseInt(kv.get(k)); } catch (Exception e) { return 0; }
    }

    // ---- 배지 ----------------------------------------------------------

    static final int GOOD = 0, WARN = 1, BAD = 2;

    int level() {
        if (!ok) return BAD;
        String s = get("state");
        if ("applied".equals(s)) return GOOD;
        if ("disabled".equals(s)) return BAD;
        return WARN;
    }

    String badge() {
        if (!ok) return "확인 불가";
        String s = get("state");
        String n = num("mounted") + "/" + num("total");
        if ("applied".equals(s)) return "적용됨 " + n;
        if ("partial".equals(s)) return "일부 적용 " + n;
        if ("disabled".equals(s)) return "꺼짐";
        return "적용 안 됨";
    }

    // ---- 적용 안 된 이유 ------------------------------------------------

    /** 정상이면 null. 아니면 [제목, 설명]. */
    String[] problem() {
        if (!ok) return new String[] {
            "NEMESIS에 연결하지 못했습니다",
            "NEMESIS 서비스가 멈춰 있을 수 있습니다. NEMESIS Manager를 다시 열거나 Settings > Reboot 후 다시 확인하세요." };
        String r = get("reason");
        if ("ok".equals(r)) return null;
        if ("reboot_needed".equals(r)) return new String[] {
            "재부팅하면 적용됩니다",
            "설치 후 아직 재부팅하지 않았습니다. NEMESIS Manager > Settings > Reboot 으로 재부팅하세요. 시동을 잠깐 껐다 켜는 것으로는 적용되지 않습니다." };
        if ("late_start".equals(r)) return new String[] {
            "Android보다 늦게 시작해 적용하지 못했습니다",
            "이번 부팅에서 NEMESIS가 Android의 폰트 로딩보다 늦게 시작했습니다. 재부팅해도 계속되면 이 차량은 지원되지 않을 수 있습니다. 진단을 실행한 뒤 오른쪽 QR로 알려 주세요." };
        if ("service_not_run".equals(r)) return new String[] {
            "부팅 서비스가 실행되지 않았습니다",
            "이번 부팅에서 이 패키지의 부팅 서비스 기록이 없습니다. 재부팅해 보고, 계속되면 진단을 실행해 알려 주세요." };
        if ("disabled".equals(r)) return new String[] {
            "안전을 위해 스스로 꺼졌습니다",
            "폰트를 적용한 부팅이 연속 " + num("fails") + "번 정상적으로 끝나지 않았습니다. 지금은 순정 폰트입니다. 패키지를 다시 설치하면 다시 켜집니다." };
        if ("no_targets".equals(r)) return new String[] {
            "바꿀 시스템 폰트를 찾지 못했습니다",
            "이 차량의 펌웨어는 폰트 구성이 달라 지원되지 않을 수 있습니다. 진단을 실행해 알려 주세요." };
        if ("corrupt".equals(r)) return new String[] {
            "패키지 안의 폰트 파일이 손상되었습니다",
            "손상된 폰트를 쓰는 항목은 건너뛰었습니다. 패키지를 다시 설치하세요." };
        if ("mount_fail".equals(r)) return new String[] {
            "일부 폰트를 덮어쓰지 못했습니다",
            "시스템이 폰트 교체를 거부했습니다. 진단을 실행해 알려 주세요." };
        if ("mount_lost".equals(r)) return new String[] {
            "적용했던 폰트가 해제되었습니다",
            "재부팅하면 다시 적용됩니다." };
        return new String[] { "일부만 적용되었습니다", "진단을 실행해 알려 주세요." };
    }

    /** group.Roboto 등 → 화면용 문구 */
    static String groupText(String v) {
        if (v == null || v.length() == 0 || "-".equals(v)) return "-";
        if (v.startsWith("applied")) return "적용 " + v.substring(8);
        if (v.startsWith("partial")) return "일부 " + v.substring(8);
        if (v.startsWith("pending")) return "적용 전";
        if (v.startsWith("absent")) return "이 차량에 없음";
        return v;
    }

    static int groupLevel(String v) {
        if (v == null) return WARN;
        if (v.startsWith("applied")) return GOOD;
        if (v.startsWith("absent")) return -1;
        return WARN;
    }

    // ---- 이슈 QR -------------------------------------------------------

    /** 버그 신고 양식을 이 차의 정보로 미리 채운 주소 (.github/ISSUE_TEMPLATE/bug_report.yml 의 id) */
    String issueUrl() {
        StringBuilder u = new StringBuilder(REPO).append("/issues/new?template=bug_report.yml");
        add(u, "firmware", get("firmware"));
        add(u, "nemesis", get("nemesis"));
        add(u, "package", get("package") + " (Pretendard " + get("pretendard") + ")");
        add(u, "status", ok ? get("state") + " " + num("mounted") + "/" + num("total") + ", reason=" + get("reason")
                            : "info unavailable");
        return u.toString();
    }

    private static void add(StringBuilder u, String k, String v) {
        try { u.append('&').append(k).append('=').append(URLEncoder.encode(v, "UTF-8")); }
        catch (Exception ignored) {}
    }
}
