package dev.wisdomit.pretendard;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;

/**
 * NEMESIS 의 root 채널로 패키지 스크립트를 실행한다.
 * 앱은 일반 uid 로 돌기 때문에 /data/nemesis 를 직접 읽지 못한다.
 * `nemesis root -c` 는 어느 uid 에서든 NEMESIS watchdog 이 root 로 대신 실행해 준다.
 */
final class Root {
    static final String NEMESIS = "/system/xbin/nemesis";
    static final String PKG = "/data/nemesis/apps/pretendard.systemfont";

    private Root() {}

    /** 패키지의 bin/ 스크립트를 실행하고 표준 출력을 돌려준다. 실패하면 null. */
    static String script(String nameAndArgs, int timeoutSec) {
        return run("/system/bin/sh " + PKG + "/bin/" + nameAndArgs, timeoutSec);
    }

    static String run(String command, int timeoutSec) {
        final Process p;
        try {
            p = new ProcessBuilder(NEMESIS, "root", "-c", command).redirectErrorStream(true).start();
        } catch (Exception e) {
            return null;
        }
        // API 19 에는 waitFor(timeout) 이 없으므로 감시 스레드로 끊는다
        final boolean[] done = {false};
        Thread killer = new Thread(new Runnable() {
            @Override public void run() {
                try { Thread.sleep(timeoutSec * 1000L); } catch (InterruptedException e) { return; }
                synchronized (done) { if (!done[0]) p.destroy(); }
            }
        });
        killer.setDaemon(true);
        killer.start();
        try {
            InputStream in = p.getInputStream();
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buf = new byte[4096];
            int n;
            while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
            int rc = p.waitFor();
            synchronized (done) { done[0] = true; }
            killer.interrupt();
            return rc == 0 ? out.toString("UTF-8") : null;
        } catch (Exception e) {
            return null;
        }
    }
}
