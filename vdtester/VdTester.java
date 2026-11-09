// vdtester —— 设备侧虚拟屏测试器（root 运行，不需要 adb、不改被测试的 App）。
//
// 做三件事：
//   1. 用 ActivityThread.systemMain() 造一个系统 Context（app_process 里没有 Application）；
//   2. 用 DisplayManager.createVirtualDisplay 建一块 PUBLIC 虚拟屏，Surface 用 ImageReader 接；
//   3. 用 ActivityOptions.setLaunchDisplayId 把目标 App 启动到这块屏，再从 ImageReader 取帧存 PNG。
//
// 为什么不是 `am start --display`：那条路在 SafeActivityOptions 里会按 display 权限拒绝
// （root / shell / system 三个身份实测都被拒）；而 app_process 里走系统 Context + public VD 的
// 组合，正是 scrcpy / MaaFwApp 用的那条路。
import android.app.ActivityOptions;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.PixelFormat;
import android.hardware.display.DisplayManager;
import android.hardware.display.VirtualDisplay;
import android.media.Image;
import android.media.ImageReader;
import android.os.Looper;
import android.view.Surface;

import java.io.FileOutputStream;
import java.nio.ByteBuffer;

public final class VdTester {
    private static final String VD_NAME = "TestVD";

    public static void main(String[] args) throws Exception {
        int width = args.length > 0 ? Integer.parseInt(args[0]) : 1280;
        int height = args.length > 1 ? Integer.parseInt(args[1]) : 720;
        int dpi = args.length > 2 ? Integer.parseInt(args[2]) : 240;
        String pkg = args.length > 3 ? args[3] : "com.jmnext";
        String outDir = args.length > 4 ? args[4] : "/data/local/tmp";

        Looper.prepareMainLooper();
        // ActivityThread 是隐藏类：android.jar 里没有，只能反射
        Class<?> atClass = Class.forName("android.app.ActivityThread");
        Object at = atClass.getMethod("systemMain").invoke(null);
        Context ctx = null;
        try {
            ctx = (Context) atClass.getMethod("getSystemContext").invoke(at);
        } catch (Throwable ignore) {
            // 部分版本没有公开该方法
        }
        if (ctx == null) {
            java.lang.reflect.Field f = atClass.getDeclaredField("mSystemContext");
            f.setAccessible(true);
            ctx = (Context) f.get(at);
        }
        System.out.println("[vdtester] system context = " + ctx);

        ImageReader reader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2);
        Surface surface = reader.getSurface();

        DisplayManager dm = (DisplayManager) ctx.getSystemService(Context.DISPLAY_SERVICE);
        int flags = DisplayManager.VIRTUAL_DISPLAY_FLAG_PUBLIC
                | DisplayManager.VIRTUAL_DISPLAY_FLAG_PRESENTATION
                | DisplayManager.VIRTUAL_DISPLAY_FLAG_OWN_CONTENT_ONLY
                | (1 << 6);   // VIRTUAL_DISPLAY_FLAG_SUPPORTS_TOUCH（隐藏常量）
        VirtualDisplay vd = dm.createVirtualDisplay(VD_NAME, width, height, dpi, surface, flags);
        if (vd == null) {
            System.err.println("[vdtester] createVirtualDisplay 返回 null");
            System.exit(2);
        }
        int displayId = vd.getDisplay().getDisplayId();
        System.out.println("[vdtester] VD created id=" + displayId
                + " size=" + width + "x" + height + " dpi=" + dpi);

        Intent intent = ctx.getPackageManager().getLaunchIntentForPackage(pkg);
        if (intent == null) {
            System.err.println("[vdtester] 找不到包 " + pkg);
            System.exit(3);
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
        ActivityOptions opts = ActivityOptions.makeBasic();
        opts.setLaunchDisplayId(displayId);
        try {
            ctx.startActivity(intent, opts.toBundle());
            System.out.println("[vdtester] startActivity 已发出：" + intent);
        } catch (Throwable t) {
            System.err.println("[vdtester] startActivity 失败：" + t);
        }

        // 取若干帧：先等界面渲染，再落 3 张 PNG
        long deadline = System.currentTimeMillis() + 25000;
        int saved = 0;
        while (System.currentTimeMillis() < deadline && saved < 3) {
            Image img = reader.acquireLatestImage();
            if (img == null) {
                Thread.sleep(500);
                continue;
            }
            if (saved > 0 || System.currentTimeMillis() > deadline - 18000) {
                save(img, outDir + "/vd-" + saved + ".png");
                saved++;
            }
            img.close();
            Thread.sleep(1500);
        }
        System.out.println("[vdtester] 帧数=" + saved + " 输出目录=" + outDir);
        vd.release();
        reader.close();
        System.exit(0);
    }

    private static void save(Image img, String path) throws Exception {
        Image.Plane plane = img.getPlanes()[0];
        ByteBuffer buf = plane.getBuffer();
        int rowStride = plane.getRowStride();
        int pixelStride = plane.getPixelStride();
        int w = img.getWidth(), h = img.getHeight();
        int[] argb = new int[w * h];
        for (int y = 0; y < h; y++) {
            int row = y * rowStride;
            for (int x = 0; x < w; x++) {
                int p = row + x * pixelStride;
                int r = buf.get(p) & 0xff;
                int g = buf.get(p + 1) & 0xff;
                int b = buf.get(p + 2) & 0xff;
                int a = buf.get(p + 3) & 0xff;
                argb[y * w + x] = (a << 24) | (r << 16) | (g << 8) | b;
            }
        }
        Bitmap bmp = Bitmap.createBitmap(argb, w, h, Bitmap.Config.ARGB_8888);
        try (FileOutputStream fos = new FileOutputStream(path)) {
            bmp.compress(Bitmap.CompressFormat.PNG, 100, fos);
        }
        System.out.println("[vdtester] 已保存 " + path);
    }

}
