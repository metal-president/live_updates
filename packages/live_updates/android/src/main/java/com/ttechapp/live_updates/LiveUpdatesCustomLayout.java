package com.ttechapp.live_updates;

import android.app.Notification;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.SystemClock;
import android.util.Log;
import android.view.View;
import android.widget.RemoteViews;
import androidx.annotation.Nullable;
import java.io.File;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.Map;
import java.util.Set;
import org.json.JSONObject;

/**
 * Custom notification layouts ({@code androidLayout} and {@code androidExpandedLayout}: layout
 * resource names of the app), filled by view id name:
 *
 * <ul>
 *   <li>{@code live_update_title}: title
 *   <li>{@code live_update_body}: body (gone without one)
 *   <li>{@code live_update_progress}: progress (gone without one)
 *   <li>{@code live_update_timer}: the timer, as a chronometer (gone without one)
 *   <li>{@code live_update_image}: image (gone without one)
 *   <li>{@code live_update_extra_<key>}: {@code extra[key]} (made visible)
 *   <li>{@code live_update_extra_image_<key>}: {@code extraImages[key]} (made visible)
 * </ul>
 *
 * <p>A layout that cannot be found falls back to the system template with a warning: remote and
 * scheduled posts cannot report errors.
 */
final class LiveUpdatesCustomLayout {
  private static final String LOG_TAG = "live_updates";

  static final String ID_TITLE = "live_update_title";
  static final String ID_BODY = "live_update_body";
  static final String ID_PROGRESS = "live_update_progress";
  static final String ID_TIMER = "live_update_timer";
  static final String ID_IMAGE = "live_update_image";
  static final String ID_EXTRA_PREFIX = "live_update_extra_";
  static final String ID_EXTRA_IMAGE_PREFIX = "live_update_extra_image_";

  /** Resolution of {@code live_update_progress}, whose maximum is set to this. */
  static final int PROGRESS_MAX = 1000;

  /** Resource names Android accepts (and no "pkg:type/name" form of getIdentifier). */
  private static final java.util.regex.Pattern NAME =
      java.util.regex.Pattern.compile("[a-z][a-z0-9_]{0,99}");

  /** Keys of {@code extra} and {@code extraImages} that can be part of a view id name. */
  private static final java.util.regex.Pattern KEY =
      java.util.regex.Pattern.compile("[a-z0-9_]{1,64}");

  /** Warnings logged once per process, by their text. */
  private static final Set<String> warned = new HashSet<>();

  /** View ids by name ({@code 0}: none); the app's resources do not change while it runs. */
  private static final Map<String, Integer> ids = new HashMap<>();

  private LiveUpdatesCustomLayout() {}

  /** Whether {@code content} asks for a custom layout (found or not). */
  static boolean requested(JSONObject content) {
    return LiveUpdatesBridge.optString(content, "androidLayout") != null;
  }

  /**
   * The collapsed and expanded views for {@code content}, or {@code null} when it has no custom
   * layout or the layout cannot be found (then the system template is used). {@code ended}:
   * the ended or stale look, without progress and timer.
   */
  @Nullable
  static RemoteViews[] views(Context c, JSONObject content, boolean ended) {
    String name = LiveUpdatesBridge.optString(content, "androidLayout");
    if (name == null) return null;
    int collapsed = layout(c, name);
    if (collapsed == 0) return null;
    String expandedName = LiveUpdatesBridge.optString(content, "androidExpandedLayout");
    int expanded = expandedName == null ? collapsed : layout(c, expandedName);
    // A missing expanded layout: the collapsed one there too.
    if (expanded == 0) expanded = collapsed;
    if (!ended && "liveUpdate".equals(LiveUpdatesBridge.androidMode(content))) {
      warnOnce(
          "Custom layout \""
              + name
              + "\": custom layouts are never promoted to Live Updates; it is shown as an"
              + " ongoing notification (set AndroidLiveUpdateMode.ongoing to say so).");
    }
    Images images = new Images(c);
    RemoteViews small = new RemoteViews(c.getPackageName(), collapsed);
    bind(c, small, content, ended, images);
    RemoteViews big;
    if (expanded == collapsed) {
      big = small;
    } else {
      big = new RemoteViews(c.getPackageName(), expanded);
      bind(c, big, content, ended, images);
    }
    return new RemoteViews[] {small, big};
  }

  /**
   * Shows {@code views} in {@code b} inside the system's decoration (app icon, name, time and
   * actions).
   */
  static void apply(Notification.Builder b, RemoteViews[] views) {
    b.setStyle(new Notification.DecoratedCustomViewStyle())
        .setCustomContentView(views[0])
        .setCustomBigContentView(views[1]);
  }

  /** Hides the progress and timer of custom views kept from a shown notification (ended look). */
  static void hideRunning(Context c, @Nullable RemoteViews views) {
    if (views == null) return;
    for (String name : new String[] {ID_PROGRESS, ID_TIMER}) {
      int id = id(c, name);
      if (id == 0) continue;
      if (ID_TIMER.equals(name)) views.setChronometer(id, SystemClock.elapsedRealtime(), null, false);
      views.setViewVisibility(id, View.GONE);
    }
  }

  private static int layout(Context c, String name) {
    int res =
        NAME.matcher(name).matches()
            ? c.getResources().getIdentifier(name, "layout", c.getPackageName())
            : 0;
    if (res == 0) {
      warnOnce(
          "Custom layout \""
              + name
              + "\" not found: showing the system template. Give the name of a file in"
              + " res/layout without \".xml\", and keep it in release builds (see the README).");
    }
    return res;
  }

  private static void bind(
      Context c, RemoteViews v, JSONObject content, boolean ended, Images images) {
    int title = id(c, ID_TITLE);
    if (title != 0) v.setTextViewText(title, content.optString("title"));

    int body = id(c, ID_BODY);
    if (body != 0) {
      String text = LiveUpdatesBridge.optString(content, "body");
      if (text == null || text.isEmpty()) {
        v.setViewVisibility(body, View.GONE);
      } else {
        v.setTextViewText(body, text);
        v.setViewVisibility(body, View.VISIBLE);
      }
    }

    int progress = id(c, ID_PROGRESS);
    if (progress != 0) {
      double p = content.optDouble("progress", Double.NaN);
      if (ended || Double.isNaN(p) || Double.isInfinite(p)) {
        v.setViewVisibility(progress, View.GONE);
      } else {
        int value = (int) Math.round(Math.max(0, Math.min(p, 1)) * PROGRESS_MAX);
        v.setProgressBar(progress, PROGRESS_MAX, value, false);
        v.setViewVisibility(progress, View.VISIBLE);
      }
    }

    int timer = id(c, ID_TIMER);
    if (timer != 0) {
      long target = ended ? 0 : timerTarget(content);
      if (target == 0) {
        v.setChronometer(timer, SystemClock.elapsedRealtime(), null, false);
        v.setViewVisibility(timer, View.GONE);
      } else {
        boolean countdown = isTime(content.optDouble("timerEnd", Double.NaN));
        // A chronometer counts from a base in the elapsed realtime clock.
        long base = SystemClock.elapsedRealtime() + (target - System.currentTimeMillis());
        v.setChronometer(timer, base, null, true);
        v.setChronometerCountDown(timer, countdown);
        v.setViewVisibility(timer, View.VISIBLE);
      }
    }

    int image = id(c, ID_IMAGE);
    if (image != 0) {
      Bitmap bitmap = images.get(LiveUpdatesBridge.optString(content, "image"));
      if (bitmap == null) {
        v.setViewVisibility(image, View.GONE);
      } else {
        v.setImageViewBitmap(image, bitmap);
        v.setViewVisibility(image, View.VISIBLE);
      }
    }

    JSONObject extra = content.optJSONObject("extra");
    for (Iterator<String> it = extra == null ? null : extra.keys(); it != null && it.hasNext(); ) {
      String key = it.next();
      Object value = extra.opt(key);
      if (!(value instanceof String)) continue;
      if (!KEY.matcher(key).matches()) {
        Log.d(LOG_TAG, "extra \"" + key + "\": only a-z, 0-9 and _ can name a view; skipped.");
        continue;
      }
      int id = id(c, ID_EXTRA_PREFIX + key);
      if (id == 0) continue;
      v.setTextViewText(id, (String) value);
      v.setViewVisibility(id, View.VISIBLE);
    }

    JSONObject extraImages = content.optJSONObject("extraImages");
    for (Iterator<String> it = extraImages == null ? null : extraImages.keys();
        it != null && it.hasNext(); ) {
      String key = it.next();
      if (!KEY.matcher(key).matches()) {
        Log.d(
            LOG_TAG, "extraImages \"" + key + "\": only a-z, 0-9 and _ can name a view; skipped.");
        continue;
      }
      int id = id(c, ID_EXTRA_IMAGE_PREFIX + key);
      if (id == 0) continue;
      Bitmap bitmap = images.get(LiveUpdatesBridge.optString(extraImages, key));
      if (bitmap == null) continue;
      v.setImageViewBitmap(id, bitmap);
      v.setViewVisibility(id, View.VISIBLE);
    }
  }

  /**
   * When the timer counts to or from (epoch ms): the end of a countdown that is not over, else
   * the start of a stopwatch; 0 for none.
   */
  private static long timerTarget(JSONObject content) {
    double end = content.optDouble("timerEnd", Double.NaN);
    if (isTime(end)) {
      long ms = (long) (end * 1000);
      // A countdown that is over would show below zero: no timer then.
      return ms > System.currentTimeMillis() ? ms : 0;
    }
    double start = content.optDouble("timerStart", Double.NaN);
    return isTime(start) ? (long) (start * 1000) : 0;
  }

  private static boolean isTime(double seconds) {
    return !Double.isNaN(seconds) && !Double.isInfinite(seconds) && Math.abs(seconds) < 1e11;
  }

  /** The app's view id {@code name}, or 0. */
  static int id(Context c, String name) {
    synchronized (ids) {
      Integer cached = ids.get(name);
      if (cached != null) return cached;
      int id = c.getResources().getIdentifier(name, "id", c.getPackageName());
      ids.put(name, id);
      return id;
    }
  }

  private static void warnOnce(String message) {
    synchronized (warned) {
      if (!warned.add(message)) return;
    }
    Log.w(LOG_TAG, message);
  }

  /** Forgets cached ids and logged warnings (tests). */
  static void reset() {
    synchronized (ids) {
      ids.clear();
    }
    synchronized (warned) {
      warned.clear();
    }
  }

  /** Stored pictures by file name, decoded once for both layouts. */
  private static final class Images {
    private final Context c;
    private final Map<String, Bitmap> decoded = new HashMap<>();

    Images(Context c) {
      this.c = c;
    }

    @Nullable
    Bitmap get(@Nullable String name) {
      // A file name in the image directory only.
      if (name == null || name.isEmpty() || name.contains("/") || name.startsWith(".")) {
        return null;
      }
      if (decoded.containsKey(name)) return decoded.get(name);
      File file = new File(LiveUpdatesBridge.imageDirectory(c), name);
      Bitmap bitmap = null;
      try {
        // Such as a file removed since: nothing to show.
        if (file.isFile()) bitmap = BitmapFactory.decodeFile(file.getPath());
      } catch (OutOfMemoryError e) {
        // Too large to show.
      }
      decoded.put(name, bitmap);
      return bitmap;
    }
  }
}
