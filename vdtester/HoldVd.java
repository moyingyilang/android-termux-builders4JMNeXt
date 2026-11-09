// 只建屏并挂住，供别的命令往这块屏上放 App
import android.content.Context;
import android.graphics.PixelFormat;
import android.hardware.display.DisplayManager;
import android.hardware.display.VirtualDisplay;
import android.media.ImageReader;
import android.os.Looper;

public final class HoldVd {
    public static void main(String[] args) throws Exception {
        int w = 1280, h = 720, dpi = 240;
        Looper.prepareMainLooper();
        Class<?> atClass = Class.forName("android.app.ActivityThread");
        Object at = atClass.getMethod("systemMain").invoke(null);
        Context ctx = null;
        try { ctx = (Context) atClass.getMethod("getSystemContext").invoke(at); } catch (Throwable ignored) {}
        if (ctx == null) {
            java.lang.reflect.Field f = atClass.getDeclaredField("mSystemContext");
            f.setAccessible(true);
            ctx = (Context) f.get(at);
        }
        ImageReader reader = ImageReader.newInstance(w, h, PixelFormat.RGBA_8888, 2);
        DisplayManager dm = (DisplayManager) ctx.getSystemService(Context.DISPLAY_SERVICE);
        int flags = DisplayManager.VIRTUAL_DISPLAY_FLAG_PUBLIC
                | DisplayManager.VIRTUAL_DISPLAY_FLAG_PRESENTATION
                | DisplayManager.VIRTUAL_DISPLAY_FLAG_OWN_CONTENT_ONLY
                | (1 << 6);
        VirtualDisplay vd = dm.createVirtualDisplay("TestVD", w, h, dpi, reader.getSurface(), flags);
        System.out.println("[holdvd] id=" + vd.getDisplay().getDisplayId());
        Thread.sleep(600000);
    }
}
