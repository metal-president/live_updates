package com.ttechapp.live_updates;

import android.Manifest;
import android.app.Activity;
import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import android.util.Log;
import androidx.annotation.Nullable;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

/**
 * Scheduled live updates: an alarm per key posts the stored content with {@code startOrUpdate}
 * when it fires, without a Flutter engine.
 *
 * <p>Schedules are stored in SharedPreferences ({@code schedules}: key -> {@code {"at": epoch
 * ms, "json": content, "exact": bool, "window": ms}}) because Android drops alarms on reboot and
 * force stop; {@link #restoreAll} sets them again after boot, app updates, clock and time zone
 * changes, exact alarm permission changes and whenever an engine attaches.
 */
final class LiveUpdatesScheduler {
  static final String ACTION_FIRE = "com.ttechapp.live_updates.SCHEDULED";
  /** Alarm of {@code LiveUpdateContent.endAt}: the update becomes stale. */
  static final String ACTION_END = "com.ttechapp.live_updates.END";
  static final String EXTRA_KEY = "com.ttechapp.live_updates.KEY";

  private static final String LOG_TAG = "live_updates";
  private static final String PREFS = "com.ttechapp.live_updates";
  private static final String PREF_SCHEDULES = "schedules";
  /** Live update id -> {@code {"at", "json" (stale content, "" for none), "remote"}}. */
  private static final String PREF_ENDS = "ends";
  private static final Object lock = new Object();

  private LiveUpdatesScheduler() {}

  /** Whether alarms fire on time: below Android 12 always; then if the app may set exact ones. */
  static boolean canScheduleExactly(Context c) {
    if (Build.VERSION.SDK_INT < 31) return true;
    return alarms(c).canScheduleExactAlarms();
  }

  /**
   * Opens the screen where the user allows exact alarms for this app (Android 12+). Returns
   * whether it was opened: not below Android 12 or when the app does not declare {@code
   * SCHEDULE_EXACT_ALARM} (the screen does not list it then).
   */
  static boolean openExactAlarmSettings(Context c, @Nullable Activity activity) {
    if (Build.VERSION.SDK_INT < 31 || !declares(c, Manifest.permission.SCHEDULE_EXACT_ALARM)) {
      return false;
    }
    Intent intent =
        new Intent(
            Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
            Uri.parse("package:" + c.getPackageName()));
    try {
      if (activity != null) {
        activity.startActivity(intent);
      } else {
        c.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
      }
      return true;
    } catch (ActivityNotFoundException | SecurityException e) {
      return false;
    }
  }

  private static boolean declares(Context c, String permission) {
    try {
      PackageInfo info =
          c.getPackageManager().getPackageInfo(c.getPackageName(), PackageManager.GET_PERMISSIONS);
      if (info.requestedPermissions == null) return false;
      for (String p : info.requestedPermissions) if (permission.equals(p)) return true;
    } catch (PackageManager.NameNotFoundException e) {
      // Our own package: always found.
    }
    return false;
  }

  /**
   * Schedules {@code json} for {@code key} at {@code atMillis} (epoch ms), replacing the schedule
   * with that key. A time that is not in the future posts it now.
   */
  static void schedule(
      Context c, String key, String json, long atMillis, boolean exact, long windowMillis)
      throws JSONException {
    new JSONObject(json); // Reject malformed content now rather than when the alarm fires.
    JSONObject entry =
        new JSONObject()
            .put("at", atMillis)
            .put("json", json)
            .put("exact", exact)
            .put("window", Math.max(0, windowMillis));
    synchronized (lock) {
      JSONObject all = read(c);
      all.put(key, entry);
      write(c, all);
    }
    arm(c, key, entry);
  }

  /**
   * Moves the schedule with {@code key} to {@code atMillis}, with {@code json} as its content
   * when given. Throws when nothing is scheduled with {@code key}.
   */
  static void reschedule(Context c, String key, @Nullable String json, long atMillis)
      throws JSONException {
    JSONObject entry;
    synchronized (lock) {
      JSONObject all = read(c);
      entry = all.optJSONObject(key);
      if (entry == null) {
        throw new IllegalStateException("No live update is scheduled with this key");
      }
      if (json != null) {
        new JSONObject(json);
        entry.put("json", json);
      } else {
        // Unchanged content: its images must now last until the new time.
        keepImages(c, new JSONObject(entry.optString("json", "{}")), atMillis);
      }
      entry.put("at", atMillis);
      write(c, all);
    }
    arm(c, key, entry);
  }

  /**
   * Protects the images that {@code content} names ({@code image}, {@code endedContent.image})
   * from the clean-up of unused images (Dart's ImageStore deletes files a day after their
   * modification time) until {@code untilMillis}.
   */
  static void keepImages(Context c, JSONObject content, long untilMillis) {
    JSONObject ended = content.optJSONObject("endedContent");
    for (String name :
        new String[] {
          LiveUpdatesBridge.optString(content, "image"),
          ended == null ? null : LiveUpdatesBridge.optString(ended, "image")
        }) {
      if (name == null || name.contains("/") || name.startsWith(".")) continue;
      java.io.File file = new java.io.File(LiveUpdatesBridge.imageDirectory(c), name);
      if (file.exists() && file.lastModified() < untilMillis) file.setLastModified(untilMillis);
    }
  }

  /** Cancels the schedule with {@code key}, if any. */
  static void cancel(Context c, String key) {
    synchronized (lock) {
      JSONObject all = read(c);
      if (all.remove(key) != null) write(c, all);
    }
    cancelAlarm(c, key);
  }

  private static void cancelAlarm(Context c, String key) {
    PendingIntent pi = alarmIntent(c, key, PendingIntent.FLAG_NO_CREATE);
    if (pi != null) {
      alarms(c).cancel(pi);
      pi.cancel();
    }
  }

  /** Cancels every schedule. */
  static void cancelAll(Context c) {
    List<String> keys = new ArrayList<>();
    synchronized (lock) {
      for (Iterator<String> it = read(c).keys(); it.hasNext(); ) keys.add(it.next());
    }
    for (String key : keys) cancel(c, key);
  }

  /** Schedules as a JSON array of {@code {"key", "at"}} (epoch seconds). */
  static String scheduledJson(Context c) {
    JSONArray out = new JSONArray();
    synchronized (lock) {
      JSONObject all = read(c);
      for (Iterator<String> it = all.keys(); it.hasNext(); ) {
        String key = it.next();
        JSONObject entry = all.optJSONObject(key);
        if (entry == null) continue;
        try {
          out.put(new JSONObject().put("key", key).put("at", entry.optLong("at") / 1000.0));
        } catch (JSONException e) {
          // Not for finite numbers.
        }
      }
    }
    return out.toString();
  }

  /** Sets every stored alarm again; runs those whose time has passed. */
  static void restoreAll(Context c) {
    List<String> keys = new ArrayList<>();
    JSONObject all;
    JSONObject ends;
    synchronized (lock) {
      all = read(c);
      ends = read(c, PREF_ENDS);
      for (Iterator<String> it = all.keys(); it.hasNext(); ) keys.add(it.next());
    }
    for (String key : keys) {
      JSONObject entry = all.optJSONObject(key);
      if (entry != null) arm(c, key, entry);
    }
    List<String> ids = new ArrayList<>();
    for (Iterator<String> it = ends.keys(); it.hasNext(); ) ids.add(it.next());
    for (String id : ids) {
      JSONObject entry = ends.optJSONObject(id);
      if (entry != null) armEnd(c, id, entry);
    }
  }

  // MARK: endAt

  /**
   * Makes the live update {@code id} stale at {@code atMillis}, showing {@code staleJson} (empty:
   * no change), replacing its earlier endAt alarm.
   */
  static void scheduleEnd(Context c, String id, long atMillis, String staleJson, boolean remote) {
    JSONObject entry = new JSONObject();
    try {
      entry.put("at", atMillis).put("json", staleJson).put("remote", remote);
    } catch (JSONException e) {
      return; // Not for these values.
    }
    synchronized (lock) {
      JSONObject all = read(c, PREF_ENDS);
      JSONObject old = all.optJSONObject(id);
      // The same end again (an update that kept endAt): nothing to change.
      if (old != null && old.toString().equals(entry.toString())) return;
      try {
        all.put(id, entry);
      } catch (JSONException e) {
        return;
      }
      write(c, PREF_ENDS, all);
    }
    armEnd(c, id, entry);
  }

  /** Cancels the end alarm of the live update {@code id}, if any. */
  static void cancelEnd(Context c, String id) {
    boolean had;
    synchronized (lock) {
      JSONObject all = read(c, PREF_ENDS);
      had = all.remove(id) != null;
      if (had) write(c, PREF_ENDS, all);
    }
    if (!had) return;
    PendingIntent pi = endIntent(c, id, PendingIntent.FLAG_NO_CREATE);
    if (pi != null) {
      alarms(c).cancel(pi);
      pi.cancel();
    }
  }

  /** The end alarm of {@code id} fired. */
  static void fireEnd(Context c, String id) {
    JSONObject entry;
    synchronized (lock) {
      JSONObject all = read(c, PREF_ENDS);
      entry = all.optJSONObject(id);
      if (entry == null) return;
      if (entry.optLong("at") > System.currentTimeMillis() + EARLY_SLACK_MS) {
        armEnd(c, id, entry);
        return;
      }
      all.remove(id);
      write(c, PREF_ENDS, all);
    }
    PendingIntent pi = endIntent(c, id, PendingIntent.FLAG_NO_CREATE);
    if (pi != null) {
      alarms(c).cancel(pi);
      pi.cancel();
    }
    try {
      LiveUpdatesBridge.endAlarmFired(
          c, id, entry.optString("json"), entry.optBoolean("remote"));
    } catch (RuntimeException e) {
      Log.e(LOG_TAG, "Could not make a live update stale", e);
    }
  }

  private static void armEnd(Context c, String id, JSONObject entry) {
    long at = entry.optLong("at");
    if (at <= System.currentTimeMillis()) {
      fireEnd(c, id);
      return;
    }
    setAlarm(c, endIntent(c, id, PendingIntent.FLAG_UPDATE_CURRENT), at, true, DEFAULT_WINDOW_MS);
  }

  @Nullable
  private static PendingIntent endIntent(Context c, String id, int flags) {
    Intent intent =
        new Intent(c, LiveUpdatesScheduleReceiver.class)
            .setAction(ACTION_END)
            .putExtra(EXTRA_KEY, id)
            .setData(LiveUpdatesBridge.intentUri("end", id, ""));
    return PendingIntent.getBroadcast(c, 0, intent, PendingIntent.FLAG_IMMUTABLE | flags);
  }

  /** The alarm for {@code key} fired: posts its content with startOrUpdate. */
  static void fire(Context c, String key) {
    JSONObject entry;
    synchronized (lock) {
      JSONObject all = read(c);
      entry = all.optJSONObject(key);
      if (entry == null) return; // Cancelled, or already posted.
      // A rescheduled alarm that fired early (old PendingIntent racing an update).
      if (entry.optLong("at") > System.currentTimeMillis() + EARLY_SLACK_MS) {
        arm(c, key, entry);
        return;
      }
      all.remove(key);
      write(c, all);
    }
    // Shown now because its time passed while the alarm was not set (or is
    // still pending): the alarm must not show it again.
    cancelAlarm(c, key);
    // Without an engine (the alarm started the process) the bridge has no
    // context yet.
    if (LiveUpdatesBridge.context == null) LiveUpdatesBridge.context = c.getApplicationContext();
    try {
      LiveUpdatesBridge.startOrUpdate(key, entry.getString("json"));
    } catch (JSONException | RuntimeException e) {
      Log.e(LOG_TAG, "Could not show a scheduled live update", e);
    }
  }

  /** Alarms may fire a little before their time. */
  private static final long EARLY_SLACK_MS = 60_000;

  /** Sets the alarm of {@code entry}, or posts it now when its time has passed. */
  private static void arm(Context c, String key, JSONObject entry) {
    long at = entry.optLong("at");
    if (at <= System.currentTimeMillis()) {
      fire(c, key);
      return;
    }
    setAlarm(
        c,
        alarmIntent(c, key, PendingIntent.FLAG_UPDATE_CURRENT),
        at,
        entry.optBoolean("exact", true),
        entry.optLong("window", DEFAULT_WINDOW_MS));
  }

  /** An exact alarm when {@code exact} and allowed, else one within {@code window} ms. */
  private static void setAlarm(Context c, PendingIntent pi, long at, boolean exact, long window) {
    AlarmManager am = alarms(c);
    try {
      if (exact && canScheduleExactly(c)) {
        try {
          am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi);
          return;
        } catch (SecurityException e) {
          // Permission revoked in between: fall back to a window.
        }
      }
      am.setWindow(AlarmManager.RTC_WAKEUP, at, window, pi);
    } catch (RuntimeException e) {
      // Such as the per-app alarm limit: the schedule stays stored and is
      // set again at the next restore, rather than crashing a receiver.
      Log.e(LOG_TAG, "Could not set the alarm of a scheduled live update", e);
    }
  }

  private static final long DEFAULT_WINDOW_MS = 10 * 60_000;

  /** One PendingIntent per key: the data URI keeps them apart. */
  @Nullable
  private static PendingIntent alarmIntent(Context c, String key, int flags) {
    Intent intent =
        new Intent(c, LiveUpdatesScheduleReceiver.class)
            .setAction(ACTION_FIRE)
            .putExtra(EXTRA_KEY, key)
            .setData(LiveUpdatesBridge.intentUri("schedule", key, ""));
    return PendingIntent.getBroadcast(c, 0, intent, PendingIntent.FLAG_IMMUTABLE | flags);
  }

  private static AlarmManager alarms(Context c) {
    return (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
  }

  private static SharedPreferences prefs(Context c) {
    return c.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
  }

  private static JSONObject read(Context c) {
    return read(c, PREF_SCHEDULES);
  }

  private static JSONObject read(Context c, String key) {
    try {
      return new JSONObject(prefs(c).getString(key, "{}"));
    } catch (JSONException e) {
      return new JSONObject();
    }
  }

  private static void write(Context c, JSONObject all) {
    write(c, PREF_SCHEDULES, all);
  }

  private static void write(Context c, String key, JSONObject all) {
    SharedPreferences.Editor e = prefs(c).edit();
    // commit (not apply): a receiver may run in a process that ends soon after.
    if (all.length() == 0) e.remove(key).commit();
    else e.putString(key, all.toString()).commit();
  }
}
