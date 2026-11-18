package dev.wisdomit.pretendard;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.view.View;

import io.nayuki.qrcodegen.QrCode;

/** 흰 바탕에 검은 QR 코드를 정사각형으로 그린다. 어두운 화면에서도 휴대폰이 읽을 수 있게 여백(quiet zone)을 둔다. */
final class QrView extends View {
    private QrCode qr;
    private final Paint black = new Paint();

    QrView(Context c) {
        super(c);
        black.setColor(Color.BLACK);
        black.setAntiAlias(false);
    }

    void setText(String text) {
        try { qr = QrCode.encodeText(text, QrCode.Ecc.MEDIUM); }
        catch (Exception e) { qr = null; }
        invalidate();
    }

    @Override
    protected void onMeasure(int w, int h) {
        int size = Math.min(MeasureSpec.getSize(w), MeasureSpec.getSize(h));
        if (MeasureSpec.getMode(h) == MeasureSpec.UNSPECIFIED) size = MeasureSpec.getSize(w);
        setMeasuredDimension(size, size);
    }

    @Override
    protected void onDraw(Canvas c) {
        int size = Math.min(getWidth(), getHeight());
        c.drawColor(Color.WHITE);
        if (qr == null) return;
        int modules = qr.size + 8;                 // 양쪽 4칸씩 여백
        float cell = (float) size / modules;
        for (int y = 0; y < qr.size; y++) {
            for (int x = 0; x < qr.size; x++) {
                if (qr.getModule(x, y)) {
                    float l = (x + 4) * cell, t = (y + 4) * cell;
                    c.drawRect(l, t, l + cell + 0.5f, t + cell + 0.5f, black);
                }
            }
        }
    }
}
