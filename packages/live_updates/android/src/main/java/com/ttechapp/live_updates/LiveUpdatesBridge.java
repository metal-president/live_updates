package com.ttechapp.live_updates;

import android.Manifest;
import android.app.Activity;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.drawable.Icon;
import android.os.Build;
import android.os.SystemClock;
import android.service.notification.StatusBarNotification;
import android.util.Log;
import androidx.annotation.Keep;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.RequiresApi;
import io.flutter.FlutterInjector;
import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.json.JSONException;
import org.json.JSONObject;

/**
 * Java surface over Android notifications, consumed from Dart through JNIgen.
 *
 * <p>Content is exchanged as the same JSON used on iOS ({@code title, body,
 * progress, icon, androidSmallIcon, route, image, actions, metrics, criticalMetric, steps,
 * journey, publicContent, extra, extraImages}) plus Android options: {@code channelId, channelName,
 * shortCriticalText, colorArgb, whenEpochMillis, showChronometer, androidMode,
 * bodySemanticStyle, progressSemanticStyle, progressSegments, progressPoints,
 * progressTrackerIcon, timeoutAfterMillis, androidAlert, androidLockScreenVisibility,
 * androidLayout, androidExpandedLayout} and the timer
 * ({@code timerStart} or {@code timerEnd}, seconds since 1970). On Android 16+ progress uses
 * {@link Notification.ProgressStyle} and promotion to a Live Update is
 * requested (shown on builds that support promoted notifications, Android 16
 * QPR1 and later); Android 17 shows {@code metrics} with {@code MetricStyle}
 * instead (see {@link LiveUpdatesApi37}). Older versions get a regular ongoing
 * notification with a progress bar. A custom layout ({@code androidLayout}, see {@link
 * LiveUpdatesCustomLayout}) replaces the system template and is never promoted.
 */
@Keep
public final class LiveUpdatesBridge {
  /** Intent extra carrying the tap route. */
  public static final String EXTRA_ROUTE = "com.ttechapp.live_updates.ROUTE";

  static final String EXTRA_UPDATE_ID = "com.ttechapp.live_updates.UPDATE_ID";
  static final String EXTRA_ACTION_ID = "com.ttechapp.live_updates.ACTION_ID";

  static final String TAG_PREFIX = "live_updates/";

  /** Manifest meta-data naming the drawable used when no icon is given. */
  static final String DEFAULT_ICON_META = "com.ttechapp.live_updates.default_icon";

  private static final String LOG_TAG = "live_updates";

  /** Resource id of the default icon, resolved once per engine attach (0: not yet). */
  private static volatile int defaultIconRes;

  /** Longest side of an asset small icon: 24 dp at xxxhdpi. */
  private static final int SMALL_ICON_PX = 96;

  /** Longest side of an asset progress tracker icon. */
  private static final int TRACKER_ICON_PX = 128;
  static final int NOTIFICATION_ID = 0x4C55; // "LU"
  static final int PERMISSION_REQUEST_CODE = 0x4C55;

  /** Receives routes from notification taps. */
  @Keep
  public interface RouteListener {
    void onRoute(@NonNull String route);
  }

  /** Receives lifecycle events as {@code "<event>:<id>"}. */
  @Keep
  public interface EventListener {
    void onEvent(@NonNull String event);
  }

  /** Receives button presses. */
  @Keep
  public interface ActionListener {
    void onAction(@NonNull String updateId, @NonNull String actionId);
  }

  /** Receives the result of {@link #requestPermission}. */
  @Keep
  public interface ResultListener {
    void onResult(boolean granted);
  }

  @Nullable static Context context;
  @Nullable static Activity activity;
  // Listeners belong to the Dart isolate of one engine (by engine id) and are
  // dropped when that engine detaches, so nothing is sent to a dead isolate.
  // Taps and lifecycle events go to every engine that listens, so a
  // background engine does not take them from the app's engine.
  private static final Map<Long, RouteListener> routeListeners = new java.util.LinkedHashMap<>();
  private static final Map<Long, EventListener> eventListeners = new java.util.LinkedHashMap<>();
  private static final Set<String> known = new LinkedHashSet<>();
  /** Callers waiting for the permission prompt that is showing. */
  private static final List<ResultListener> permissionListeners = new ArrayList<>();
  private static final List<String> pendingRoutes = new ArrayList<>();
  @Nullable private static volatile ActionListener actionListener;
  private static long actionEngine;
  /**
   * Updates whose presses Dart takes; {@code null} for all ({@code onAction}).
   * Other presses stay queued for the background handler.
   */
  @Nullable private static Set<String> actionFilter;
  private static final Object actionLock = new Object();

  private static final String PREFS = "com.ttechapp.live_updates";
  private static final String PREF_PENDING_ACTIONS = "pendingActions";
  private static final String PREF_DISMISSED = "dismissedIds";
  private static final String PREF_INTENT_TOKEN = "intentToken";
  private static final String PREF_BG_DISPATCHER = "backgroundDispatcher";
  private static final String PREF_BG_HANDLER = "backgroundHandler";
  static final String EXTRA_TOKEN = "com.ttechapp.live_updates.TOKEN";

  /**
   * NotificationManager updates its active list asynchronously, so recent
   * posts and cancels are tracked here for a short while (id -> uptime ms).
   */
  private static final Map<String, Long> recentlyPosted = new HashMap<>();
  private static final Map<String, Long> recentlyEnded = new HashMap<>();
  private static final long RECENT_MS = 3000;

  private LiveUpdatesBridge() {}

  /** Whether notifications can be shown. */
  public static boolean isSupported() {
    Context c = context;
    return c != null && manager(c).areNotificationsEnabled();
  }

  /** Whether this app may post promoted notifications (Live Updates; the user can turn it off). */
  public static boolean canPostPromotedNotifications() {
    Context c = context;
    if (c == null || Build.VERSION.SDK_INT < 36) return false;
    return manager(c).canPostPromotedNotifications();
  }

  /**
   * Whether the system promoted the shown live update {@code id} to a Live
   * Update ({@code Notification.FLAG_PROMOTED_ONGOING}). This is the system's
   * actual decision, which also depends on the promotion requirements, the
   * user's settings and device maker criteria, unlike {@code
   * canPostPromotedNotifications()}. It reflects the notification as the
   * system currently lists it: the system decides on promotion after posting
   * and updates its list asynchronously, so this may be {@code false} for a
   * moment after a start or update. {@code false} below Android 16, when not
   * attached, or when {@code id} is not shown.
   */
  public static boolean isPromoted(@NonNull String id) {
    Context c = context;
    if (c == null || Build.VERSION.SDK_INT < 36) return false;
    // Ended in this process: the system may still list it for a moment, as
    // in activeIds().
    long now = SystemClock.uptimeMillis();
    synchronized (recentlyPosted) {
      recentlyEnded.values().removeIf(t -> now - t > RECENT_MS);
      if (recentlyEnded.containsKey(id)) return false;
    }
    for (StatusBarNotification n : manager(c).getActiveNotifications()) {
      if (n.getId() == NOTIFICATION_ID && (TAG_PREFIX + id).equals(n.getTag())) {
        return (n.getNotification().flags & Notification.FLAG_PROMOTED_ONGOING) != 0;
      }
    }
    return false;
  }

  /**
   * Requests the notification permission (Android 13+). {@code listener} is
   * called with the result; immediately when no prompt is needed.
   */
  public static void requestPermission(@NonNull ResultListener listener) {
    Context c = context;
    Activity a = activity;
    if (c == null) {
      listener.onResult(false);
      return;
    }
    if (Build.VERSION.SDK_INT < 33
        || c.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
            == PackageManager.PERMISSION_GRANTED) {
      listener.onResult(manager(c).areNotificationsEnabled());
      return;
    }
    if (a == null) {
      listener.onResult(false);
      return;
    }
    synchronized (permissionListeners) {
      permissionListeners.add(listener);
      // A prompt is already showing: this caller gets its result too.
      if (permissionListeners.size() > 1) return;
    }
    a.runOnUiThread(
        () ->
            a.requestPermissions(
                new String[] {Manifest.permission.POST_NOTIFICATIONS}, PERMISSION_REQUEST_CODE));
  }

  /** Completes every waiting {@link #requestPermission} call. */
  static void permissionResult(boolean granted) {
    List<ResultListener> listeners;
    synchronized (permissionListeners) {
      listeners = new ArrayList<>(permissionListeners);
      permissionListeners.clear();
    }
    for (ResultListener l : listeners) l.onResult(granted);
  }

  /** Whether the user turned off the channel the content posts to. */
  private static boolean channelBlocked(Context c, String json) {
    if (Build.VERSION.SDK_INT < 26) return false;
    String channelId = DEFAULT_CHANNEL;
    try {
      channelId = new JSONObject(json).optString("channelId", DEFAULT_CHANNEL);
    } catch (JSONException e) {
      // Reported by post().
    }
    NotificationChannel channel = manager(c).getNotificationChannel(channelId);
    if (channel == null) return false;
    if (channel.getImportance() == NotificationManager.IMPORTANCE_NONE) return true;
    // The user can also turn off the channel's group (Android 9+).
    if (Build.VERSION.SDK_INT >= 28 && channel.getGroup() != null) {
      android.app.NotificationChannelGroup group =
          manager(c).getNotificationChannelGroup(channel.getGroup());
      return group != null && group.isBlocked();
    }
    return false;
  }

  /** Completes waiting permission requests with the current state. */
  static void permissionPromptGone() {
    Context c = context;
    boolean granted =
        c != null
            && (Build.VERSION.SDK_INT < 33
                || c.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                    == PackageManager.PERMISSION_GRANTED)
            && manager(c).areNotificationsEnabled();
    permissionResult(granted);
  }

  /**
   * Fails, as iOS does when Live Activities are turned off, when nothing could be shown:
   * notifications are turned off for the app or for the channel of {@code json}.
   */
  private static void requireShowable(Context c, String json) {
    String reason = notShowableReason(c, json);
    if (reason != null) throw new IllegalStateException(reason);
  }

  /** Why nothing posted with {@code json} could be shown, or {@code null}. */
  @Nullable
  private static String notShowableReason(Context c, String json) {
    if (!manager(c).areNotificationsEnabled()) return "Notifications are turned off for this app";
    if (channelBlocked(c, json)) return "The notification channel of this live update is turned off";
    return null;
  }

  /** Posts a new live update and returns its id. */
  @NonNull
  public static String start(@NonNull String json) throws JSONException {
    requireShowable(requireContext(), json);
    String id = UUID.randomUUID().toString();
    post(id, new JSONObject(json), false, false);
    return id;
  }

  /**
   * Posts or replaces the live update whose id is {@code key}. Keys share the
   * id namespace with remote payloads ({@code live_updates_id}).
   */
  @NonNull
  public static String startOrUpdate(@NonNull String key, @NonNull String json)
      throws JSONException {
    return startOrUpdate(key, json, true);
  }

  /**
   * {@code strict}: fail when nothing could be shown (calls from Dart), also for a key that is
   * already shown; a schedule whose time comes while notifications are off posts nothing, as
   * before.
   */
  static String startOrUpdate(String key, String json, boolean strict) throws JSONException {
    Context c = requireContext();
    // A key the user dismissed stays hidden until the app ends it.
    if (isDismissed(c, key)) return key;
    // Nothing can be shown: fail, as start() and update() do. A schedule
    // posts nothing then, so no update is reported started.
    if (strict) {
      requireShowable(c, json);
    } else if (!isShown(key)) {
      String reason = notShowableReason(c, json);
      if (reason != null) {
        Log.w(LOG_TAG, "A scheduled live update was not shown: " + reason);
        return key;
      }
    }
    post(key, new JSONObject(json), false, true);
    return key;
  }

  /**
   * Key of the shown live update {@code id}: its id when it was started with
   * a key (startOrUpdate or a remote payload), else {@code null}.
   */
  @Nullable
  public static String keyForId(@NonNull String id) {
    // Posted in this process: known right away (the system lists a new
    // notification only after a moment).
    synchronized (keyedIds) {
      if (keyedIds.contains(id)) return id;
    }
    Context c = context;
    if (c == null) return null;
    // After a process restart: the marker on the shown notification.
    for (android.service.notification.StatusBarNotification n :
        manager(c).getActiveNotifications()) {
      if (n.getId() == NOTIFICATION_ID && (TAG_PREFIX + id).equals(n.getTag())) {
        return n.getNotification().extras.getBoolean(EXTRA_KEYED, false) ? id : null;
      }
    }
    return null;
  }

  /** Ids posted with a key in this process. */
  private static final Set<String> keyedIds = new java.util.HashSet<>();

  /** Notification extra marking updates whose id is an app or server key. */
  private static final String EXTRA_KEYED = "com.ttechapp.live_updates.KEYED";

  /** {@code key} if a live update with that id is shown, else {@code null}. */
  @Nullable
  public static String idForKey(@NonNull String key) {
    return isShown(key) ? key : null;
  }

  /**
   * State of the live update {@code id} as the system shows it: {@code active}, {@code stale}
   * (past its endAt), {@code ended} (the notification kept after the end) or, when it is not
   * shown, {@code dismissed} if the user swiped it away (remembered until the app ends it); else
   * {@code null}. The id of a keyed update is its key.
   */
  @Nullable
  public static String stateOf(@NonNull String id) {
    Context c = context;
    if (c == null) return null;
    boolean stale;
    synchronized (staleIds) {
      stale = staleIds.contains(id);
    }
    // Posted or ended a moment ago: the system list catches up only after a
    // moment, so this process's own record comes first.
    long now = SystemClock.uptimeMillis();
    boolean endedJustNow;
    boolean postedJustNow;
    synchronized (recentlyPosted) {
      Long ended = recentlyEnded.get(id);
      Long posted = recentlyPosted.get(id);
      endedJustNow = ended != null && now - ended <= RECENT_MS;
      postedJustNow = !endedJustNow && posted != null && now - posted <= RECENT_MS;
    }
    if (endedJustNow) {
      boolean kept;
      synchronized (keptEnded) {
        kept = keptEnded.contains(id);
      }
      if (kept) return "ended";
      return isDismissed(c, id) ? "dismissed" : null;
    }
    if (postedJustNow) return stale ? "stale" : "active";
    boolean knownHere;
    synchronized (lastPosted) {
      knownHere = lastPosted.containsKey(id);
    }
    for (StatusBarNotification n : manager(c).getActiveNotifications()) {
      if (n.getId() != NOTIFICATION_ID || !(TAG_PREFIX + id).equals(n.getTag())) continue;
      Notification notification = n.getNotification();
      boolean ongoing = (notification.flags & Notification.FLAG_ONGOING_EVENT) != 0;
      if (notification.extras.getBoolean(EXTRA_STALE, false)) return "stale";
      if (!ongoing) return "ended";
      // After a process restart the stale state is not known here: past the
      // endAt on the notification, it is stale (states reports it when the
      // end alarm runs).
      long endAt = notification.extras.getLong(EXTRA_END_AT, 0);
      boolean pastEndAt = !knownHere && endAt > 0 && System.currentTimeMillis() >= endAt;
      return stale || pastEndAt ? "stale" : "active";
    }
    return isDismissed(c, id) ? "dismissed" : null;
  }

  /** Notification extra with the endAt time (epoch ms) of an update that becomes stale then. */
  private static final String EXTRA_END_AT = "com.ttechapp.live_updates.END_AT";

  /**
   * Calls {@code listener} with presses of {@code updateIds} ({@code null}:
   * all) while the app is in the foreground, starting with queued ones in
   * order. Other presses stay queued for the background handler.
   */
  public static void observeActions(
      @NonNull ActionListener listener, long engineId, @Nullable String[] updateIds) {
    synchronized (actionLock) {
      actionListener = listener;
      actionEngine = engineId;
      actionFilter =
          updateIds == null ? null : new java.util.HashSet<>(Arrays.asList(updateIds));
      drainActions();
    }
    runQueuedInBackground();
  }

  /** Limits the presses Dart takes to those of {@code updateIds} ({@code null}: all). */
  public static void setActionFilter(long engineId, @Nullable String[] updateIds) {
    synchronized (actionLock) {
      if (actionEngine != engineId) return;
      actionFilter =
          updateIds == null ? null : new java.util.HashSet<>(Arrays.asList(updateIds));
      drainActions();
    }
    runQueuedInBackground();
  }

  /**
   * Queues presses again that reached Dart but no listener took (it stopped
   * listening in the meantime), for a listener that takes them or the
   * background handler.
   */
  public static void requeueActions(@NonNull String[] presses) {
    Context c = context;
    if (c == null) return;
    synchronized (actionLock) {
      // In front: they were pressed before anything queued since.
      List<String[]> pending = new ArrayList<>();
      for (String press : presses) {
        int i = press.indexOf('\n');
        if (i > 0) pending.add(new String[] {press.substring(0, i), press.substring(i + 1)});
      }
      pending.addAll(readPendingActions(c));
      writePendingActions(c, pending);
      drainActions();
    }
    runQueuedInBackground();
  }

  /** Whether the Dart listener takes presses of {@code updateId}; under actionLock. */
  private static boolean dartTakes(String updateId) {
    // Not while the app is in the background: its process could be frozen
    // mid-handler, so the background handler (which holds the receiver) runs it.
    if (actionListener == null || !inForeground()) return false;
    Set<String> filter = actionFilter;
    return filter == null || filter.contains(updateId);
  }

  private static boolean inForeground() {
    android.app.ActivityManager.RunningAppProcessInfo info =
        new android.app.ActivityManager.RunningAppProcessInfo();
    android.app.ActivityManager.getMyMemoryState(info);
    return info.importance
        <= android.app.ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND;
  }

  /** Hands the queued presses Dart takes over (for example when the app comes back). */
  static void deliverQueuedActions() {
    synchronized (actionLock) {
      drainActions();
    }
  }

  /** Hands Dart the queued presses it takes; the rest stay queued. Under actionLock. */
  private static void drainActions() {
    ActionListener listener = actionListener;
    Context c = context;
    if (listener == null || c == null) return;
    List<String[]> keep = new ArrayList<>();
    List<String[]> take = new ArrayList<>();
    for (String[] a : takePendingActions(c)) (dartTakes(a[0]) ? take : keep).add(a);
    writePendingActions(c, keep);
    for (String[] a : take) listener.onAction(a[0], a[1]);
  }

  /** Runs the background handler for queued presses no Dart listener takes. */
  static void runQueuedInBackground() {
    Context c = context;
    if (c == null || !hasQueuedBackgroundActions()) return;
    long dispatcher = prefs(c).getLong(PREF_BG_DISPATCHER, 0);
    if (dispatcher != 0) LiveUpdatesBackgroundRunner.run(c, dispatcher, null);
  }

  /**
   * Stops delivering presses to Dart (nothing listens any more): queued and
   * later presses are run by the background handler.
   */
  public static void unobserveActions(long engineId) {
    synchronized (actionLock) {
      if (actionEngine != engineId) return;
      actionListener = null;
      actionFilter = null;
    }
    runQueuedInBackground();
  }

  static void emitAction(Context c, String updateId, String actionId) {
    emitAction(c, updateId, actionId, null);
  }

  /**
   * Delivers a press to the Dart listener, or queues it and, when a
   * background handler is registered, runs it in a headless engine.
   * [result] (from a receiver's goAsync) is finished when that is done.
   */
  static void emitAction(
      Context c,
      String updateId,
      String actionId,
      @Nullable android.content.BroadcastReceiver.PendingResult result) {
    emitAction(c, updateId, actionId, result, true);
  }

  private static void emitAction(
      Context c,
      String updateId,
      String actionId,
      @Nullable android.content.BroadcastReceiver.PendingResult result,
      boolean allowBackground) {
    long dispatcher;
    synchronized (actionLock) {
      ActionListener listener = actionListener;
      if (listener != null && dartTakes(updateId)) {
        listener.onAction(updateId, actionId);
        if (result != null) result.finish();
        return;
      }
      SharedPreferences prefs = prefs(c);
      org.json.JSONArray pending = readArray(prefs, PREF_PENDING_ACTIONS);
      pending.put(new org.json.JSONArray().put(updateId).put(actionId));
      // commit (not apply): the headless engine reads it right away.
      prefs.edit().putString(PREF_PENDING_ACTIONS, pending.toString()).commit();
      dispatcher = allowBackground ? prefs.getLong(PREF_BG_DISPATCHER, 0) : 0;
    }
    if (dispatcher != 0) {
      LiveUpdatesBackgroundRunner.run(c, dispatcher, result);
    } else if (result != null) {
      result.finish();
    }
  }

  /** Stores the Dart callback handles of the background action handler. */
  public static void setBackgroundActionHandler(long dispatcher, long handler) {
    prefs(requireContext())
        .edit()
        .putLong(PREF_BG_DISPATCHER, dispatcher)
        .putLong(PREF_BG_HANDLER, handler)
        .apply();
  }

  /** Raw callback handle of the background handler, or 0. */
  public static long backgroundActionHandler() {
    Context c = context;
    return c == null ? 0 : prefs(c).getLong(PREF_BG_HANDLER, 0);
  }

  /** Removes and returns queued presses as {@code "<update id>\n<action id>"}. */
  @NonNull
  public static String[] takeQueuedActions() {
    Context c = context;
    if (c == null) return new String[0];
    List<String> out = new ArrayList<>();
    synchronized (actionLock) {
      // Presses a Dart listener of the app takes are left to it.
      List<String[]> keep = new ArrayList<>();
      for (String[] a : takePendingActions(c)) {
        if (dartTakes(a[0])) keep.add(a);
        else out.add(a[0] + "\n" + a[1]);
      }
      writePendingActions(c, keep);
      takeCount++;
    }
    return out.toArray(new String[0]);
  }

  /** How many times the background handler took queued presses. */
  static int takeCount;

  /** Whether presses wait for the background handler (no Dart listener takes them). */
  static boolean hasQueuedBackgroundActions() {
    Context c = context;
    if (c == null) return false;
    synchronized (actionLock) {
      for (String[] a : readPendingActions(c)) if (!dartTakes(a[0])) return true;
      return false;
    }
  }

  /** Called by the background engine when the handler finished. */
  public static void backgroundActionsDone() {
    LiveUpdatesBackgroundRunner.finish();
  }

  private static List<String[]> takePendingActions(Context c) {
    List<String[]> out = readPendingActions(c);
    prefs(c).edit().remove(PREF_PENDING_ACTIONS).apply();
    return out;
  }

  private static void writePendingActions(Context c, List<String[]> presses) {
    org.json.JSONArray a = new org.json.JSONArray();
    for (String[] p : presses) a.put(new org.json.JSONArray().put(p[0]).put(p[1]));
    SharedPreferences.Editor e = prefs(c).edit();
    // commit (not apply): the headless engine reads it right away.
    if (a.length() == 0) e.remove(PREF_PENDING_ACTIONS).commit();
    else e.putString(PREF_PENDING_ACTIONS, a.toString()).commit();
  }

  private static List<String[]> readPendingActions(Context c) {
    org.json.JSONArray pending = readArray(prefs(c), PREF_PENDING_ACTIONS);
    List<String[]> out = new ArrayList<>();
    for (int i = 0; i < pending.length(); i++) {
      org.json.JSONArray a = pending.optJSONArray(i);
      if (a != null && a.length() == 2) out.add(new String[] {a.optString(0), a.optString(1)});
    }
    return out;
  }

  /** Called by the plugin when an engine attaches or detaches. */
  static void engineAttached(Context c) {
    context = c.getApplicationContext();
    defaultIconRes = 0;
    // Alarms are gone after a force stop, which sends no broadcast.
    LiveUpdatesScheduler.restoreAll(context);
  }

  static void engineDetached(long engineId) {
    // The listeners of this engine's isolate are gone: queue from now on.
    synchronized (actionLock) {
      if (actionEngine == engineId) {
        actionListener = null;
        actionFilter = null;
      }
      routeListeners.remove(engineId);
      eventListeners.remove(engineId);
    }
    runQueuedInBackground();
  }

  /** At most this many dismissed ids are remembered (oldest are dropped). */
  private static final int MAX_DISMISSED = 200;

  /** Records that the user swiped the update away (see DismissReceiver). */
  static void markDismissed(Context c, String id) {
    forgetPostsInProcess(id);
    LiveUpdatesScheduler.cancelEnd(c, id);
    forgetStartTime(c, id);
    synchronized (staleIds) {
      staleIds.remove(id);
    }
    synchronized (actionLock) {
      List<String> ids = readStrings(c, PREF_DISMISSED);
      ids.remove(id);
      ids.add(id);
      while (ids.size() > MAX_DISMISSED) ids.remove(0);
      writeStrings(c, PREF_DISMISSED, ids);
    }
  }

  private static void clearDismissed(Context c, String id) {
    synchronized (actionLock) {
      List<String> ids = readStrings(c, PREF_DISMISSED);
      if (ids.remove(id)) writeStrings(c, PREF_DISMISSED, ids);
    }
  }

  private static boolean isDismissed(Context c, String id) {
    return readStrings(c, PREF_DISMISSED).contains(id);
  }

  private static List<String> readStrings(Context c, String key) {
    org.json.JSONArray a = readArray(prefs(c), key);
    List<String> out = new ArrayList<>();
    for (int i = 0; i < a.length(); i++) out.add(a.optString(i));
    return out;
  }

  private static void writeStrings(Context c, String key, List<String> values) {
    prefs(c).edit().putString(key, new org.json.JSONArray(values).toString()).apply();
  }

  /**
   * Random per-install secret put into the plugin's own launch intents. The
   * launcher activity is exported, so extras without it may come from another
   * app and are ignored.
   */
  private static String intentToken(Context c) {
    SharedPreferences prefs = prefs(c);
    String token = prefs.getString(PREF_INTENT_TOKEN, null);
    if (token == null) {
      token = UUID.randomUUID().toString();
      prefs.edit().putString(PREF_INTENT_TOKEN, token).apply();
    }
    return token;
  }

  private static SharedPreferences prefs(Context c) {
    return c.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
  }

  private static org.json.JSONArray readArray(SharedPreferences prefs, String key) {
    try {
      return new org.json.JSONArray(prefs.getString(key, "[]"));
    } catch (JSONException e) {
      return new org.json.JSONArray();
    }
  }

  /**
   * Replaces the content of the live update {@code id}. Fails when the user
   * dismissed it (platform guidance: never repost it) or when it is no
   * longer shown.
   */
  public static void update(@NonNull String id, @NonNull String json) throws JSONException {
    Context c = requireContext();
    if (isDismissed(c, id)) {
      throw new IllegalStateException("Live update " + id + " was dismissed by the user");
    }
    // Nothing can be shown (the system also stops listing the update).
    requireShowable(c, json);
    if (!isShown(id)) throw new IllegalStateException("Unknown live update " + id);
    post(id, new JSONObject(json));
  }

  private static boolean isShown(String id) {
    return java.util.Arrays.asList(activeIds()).contains(id);
  }

  /**
   * Ends the live update {@code id}. Unless {@code dismissAfterSeconds} is 0, the final content
   * (else the content shown last) stays as a regular notification for at most four hours.
   */
  public static void end(@NonNull String id, @Nullable String json, double dismissAfterSeconds)
      throws JSONException {
    // Never bring back an update the user dismissed (it already reported
    // dismissed).
    boolean dismissed = isDismissed(requireContext(), id);
    end(id, dismissed ? null : json, dismissAfterSeconds, false, !dismissed);
  }

  private static void end(
      String id, @Nullable String json, double dismissAfterSeconds, boolean remote, boolean emit)
      throws JSONException {
    Context c = requireContext();
    Object[] last;
    synchronized (lastPosted) {
      last = lastPosted.remove(id);
    }
    // Whether it is running: posted a moment ago (the system lists a new
    // notification only after a moment) or listed as running.
    // An update ended a moment ago may still be listed as running.
    boolean recent;
    boolean endedJustNow;
    long nowUptime = SystemClock.uptimeMillis();
    synchronized (recentlyPosted) {
      Long ended = recentlyEnded.get(id);
      Long posted = recentlyPosted.get(id);
      endedJustNow = ended != null && nowUptime - ended <= RECENT_MS;
      recent = posted != null && nowUptime - posted <= RECENT_MS && !endedJustNow;
    }
    Notification shown = recent || endedJustNow ? null : activeNotification(c, id);
    boolean running = recent || shown != null;
    synchronized (recentlyPosted) {
      recentlyPosted.remove(id);
      recentlyEnded.put(id, SystemClock.uptimeMillis());
    }
    // Reported once, like the iOS activity state: not again for an update
    // that already ended (also when nothing is shown, for example with
    // notifications blocked, as long as it was reported started).
    boolean wasKnown;
    synchronized (known) {
      wasKnown = known.contains(id);
    }
    if (emit && (running || wasKnown)) emit("ended", id);
    synchronized (keyedIds) {
      keyedIds.remove(id);
    }
    clearDismissed(c, id);
    LiveUpdatesScheduler.cancelEnd(c, id);
    forgetStartTime(c, id);
    synchronized (staleIds) {
      staleIds.remove(id);
    }
    // As on iOS, the ended update stays as a regular notification (the final
    // content, else what was shown) and is removed after at most four hours.
    // Below Android 8 nothing can remove it later, so only final content
    // stays there (until the user dismisses it). Never for an update the
    // user dismissed (emit is false then).
    Notification.Builder builder = null;
    boolean keep = dismissAfterSeconds != 0;
    // An ended notification this process kept may be replaced by final
    // content; one cancelled a moment ago may still be listed.
    boolean keptBefore;
    synchronized (keptEnded) {
      keptBefore = keptEnded.contains(id);
    }
    boolean endedShown = endedJustNow ? keptBefore : isListed(c, id);
    if (json != null && keep && (running || endedShown)) {
      // Final content replaces the update or its ended notification, but
      // does not bring back one that is gone.
      builder = builder(c, endedContent(new JSONObject(json)), remote, true);
    } else if (keep && emit && running && Build.VERSION.SDK_INT >= 26) {
      if (last != null) {
        // The content posted last, also when the system does not list it yet.
        builder = builder(c, endedContent((JSONObject) last[0]), (Boolean) last[1], true);
      } else if (shown != null) {
        // After a process restart: rebuilt from the shown notification.
        builder = endedLook(c, shown);
      }
    }
    if (builder != null) {
      if (Build.VERSION.SDK_INT >= 26) {
        builder.setTimeoutAfter(keepEndedMillis(dismissAfterSeconds));
      }
      synchronized (keptEnded) {
        keptEnded.add(id);
      }
      manager(c).notify(TAG_PREFIX + id, NOTIFICATION_ID, builder.build());
    } else if (json == null && keep && !running) {
      // Ended before (for example a repeated remote end): an ended
      // notification stays as it is.
    } else {
      // Removed: a later end with final content must not bring it back.
      synchronized (keptEnded) {
        keptEnded.remove(id);
      }
      manager(c).cancel(TAG_PREFIX + id, NOTIFICATION_ID);
    }
  }

  /** Whether the system shows a notification for {@code id}, running or ended. */
  private static boolean isListed(Context c, String id) {
    for (StatusBarNotification n : manager(c).getActiveNotifications()) {
      if (n.getId() == NOTIFICATION_ID && (TAG_PREFIX + id).equals(n.getTag())) return true;
    }
    return false;
  }

  /** Ids whose ended notification this process posted (endAll removes them). */
  private static final Set<String> keptEnded = new java.util.HashSet<>();

  /** Content and remote flag of the latest post of each running update, in this process. */
  private static final Map<String, Object[]> lastPosted = new HashMap<>();

  private static void forgetLastPosted(String id) {
    synchronized (lastPosted) {
      lastPosted.remove(id);
    }
  }

  /** Forgets what this process posted for {@code id} (also used by tests, as after a restart). */
  static void forgetPostsInProcess(String id) {
    forgetLastPosted(id);
    synchronized (recentlyPosted) {
      recentlyPosted.remove(id);
    }
  }

  /** Keys of the content that an ended update does not keep. */
  private static final String[] RUNNING_ONLY_KEYS = {
    "timerStart", "timerEnd", "showChronometer", "actions", "endAt", "endedContent",
    "removeAtEnd", "maxDurationMillis", "timeoutAfterMillis", "androidAlert", "alert",
    "removeAtCountdownEnd",
  };

  /**
   * {@code content} as an ended update shows it: without running timers (a countdown would run
   * past zero), buttons and running-only options.
   */
  static JSONObject endedContent(JSONObject content) throws JSONException {
    JSONObject out = new JSONObject(content.toString());
    for (String key : RUNNING_ONLY_KEYS) out.remove(key);
    org.json.JSONArray metrics = out.optJSONArray("metrics");
    if (metrics != null) {
      org.json.JSONArray still = new org.json.JSONArray();
      for (int i = 0; i < metrics.length(); i++) {
        JSONObject m = metrics.optJSONObject(i);
        String type = m == null ? "" : m.optString("type");
        if (!type.equals("timer") && !type.equals("stopwatch")) still.put(metrics.get(i));
      }
      if (still.length() != metrics.length()) {
        out.remove("criticalMetric");
        if (still.length() == 0) out.remove("metrics");
        else out.put("metrics", still);
      }
    }
    return out;
  }

  /** How long an ended update stays at most, as on iOS (four hours). */
  static final long MAX_ENDED_MS = 4 * 60 * 60 * 1000L;

  /**
   * How long an ended update stays for {@code dismissAfterSeconds}: a
   * negative value (no duration given) keeps it the longest.
   */
  static long keepEndedMillis(double dismissAfterSeconds) {
    if (dismissAfterSeconds < 0 || Double.isNaN(dismissAfterSeconds)) return MAX_ENDED_MS;
    return Math.max(1, Math.min((long) (dismissAfterSeconds * 1000), MAX_ENDED_MS));
  }

  /** The running live update {@code id} as the system shows it, or {@code null}. */
  @Nullable
  private static Notification activeNotification(Context c, String id) {
    for (StatusBarNotification n : manager(c).getActiveNotifications()) {
      if (n.getId() == NOTIFICATION_ID && (TAG_PREFIX + id).equals(n.getTag())) {
        Notification notification = n.getNotification();
        boolean running =
            (notification.flags & Notification.FLAG_ONGOING_EVENT) != 0
                || notification.extras.getBoolean(EXTRA_STALE, false);
        return running ? notification : null;
      }
    }
    return null;
  }

  /**
   * {@code shown} as an ended update: the same content, but no longer ongoing
   * or promoted, without buttons or running chronometer, removed by a tap and
   * not reported as dismissed when swiped away.
   */
  @RequiresApi(26)
  private static Notification.Builder endedLook(Context c, Notification shown) {
    // The recovered builder writes into the notification it was made from,
    // and build() keeps its actions when the builder has none: drop them on
    // a copy.
    Notification copy = shown.clone();
    copy.actions = null;
    if (Build.VERSION.SDK_INT >= 36) copy.flags &= ~Notification.FLAG_PROMOTED_ONGOING;
    copy.extras.remove(EXTRA_STALE);
    copy.extras.remove(EXTRA_KEYED);
    copy.extras.remove(EXTRA_END_AT);
    Notification.Builder b =
        Notification.Builder.recoverBuilder(c, copy)
            .setOngoing(false)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setDeleteIntent(null)
            .setUsesChronometer(false)
            .setChronometerCountDown(false)
            .setActions();
    // A chronometer's base would show as a time in the future or the past.
    if (shown.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER, false)) {
      b.setWhen(System.currentTimeMillis());
    }
    // Time metrics (Android 17) would keep running: no metric style.
    String template = copy.extras.getString(Notification.EXTRA_TEMPLATE);
    if (template != null && template.endsWith("MetricStyle")) b.setStyle(null);
    requestPromotedOngoing(b, false);
    // Custom layouts: the progress and timer views (the system template's
    // are handled above).
    LiveUpdatesCustomLayout.hideRunning(c, copy.contentView);
    if (copy.bigContentView != copy.contentView) {
      LiveUpdatesCustomLayout.hideRunning(c, copy.bigContentView);
    }
    android.os.Bundle extras = b.getExtras();
    extras.remove(EXTRA_STALE);
    extras.remove(EXTRA_KEYED);
    extras.remove(EXTRA_END_AT);
    if (copy.publicVersion != null) b.setPublicVersion(endedLook(c, copy.publicVersion).build());
    return b;
  }

  /** Directory where Dart stores images referenced by {@code "image"}. */
  @Nullable
  public static String imageDirectory() {
    Context c = context;
    return c == null ? null : imageDir(c).getPath();
  }

  static java.io.File imageDirectory(Context c) {
    return imageDir(c);
  }

  private static java.io.File imageDir(Context c) {
    return new java.io.File(c.getCacheDir(), "live_updates");
  }

  /** Ids of live updates currently shown. */
  @NonNull
  public static String[] activeIds() {
    Context c = context;
    if (c == null) return new String[0];
    Set<String> ids = new LinkedHashSet<>();
    for (StatusBarNotification n : manager(c).getActiveNotifications()) {
      String tag = n.getTag();
      if (n.getId() == NOTIFICATION_ID && tag != null && tag.startsWith(TAG_PREFIX)) {
        Notification notification = n.getNotification();
        if ((notification.flags & Notification.FLAG_ONGOING_EVENT) != 0
            || notification.extras.getBoolean(EXTRA_STALE, false)) {
          ids.add(tag.substring(TAG_PREFIX.length()));
        }
      }
    }
    long now = SystemClock.uptimeMillis();
    synchronized (recentlyPosted) {
      recentlyPosted.values().removeIf(t -> now - t > RECENT_MS);
      recentlyEnded.values().removeIf(t -> now - t > RECENT_MS);
      ids.addAll(recentlyPosted.keySet());
      ids.removeAll(recentlyEnded.keySet());
    }
    return ids.toArray(new String[0]);
  }

  /**
   * Applies a remote payload, e.g. an FCM data message. Keys: {@code
   * live_updates_event} (start, update or end), {@code live_updates_id} and
   * {@code live_updates_content} (content JSON). Returns {@code false} when the
   * payload is not a live_updates message.
   */
  public static boolean handleRemotePayload(@NonNull String json) throws JSONException {
    JSONObject data = new JSONObject(json);
    String event = data.optString("live_updates_event", "");
    String id = data.optString("live_updates_id", "");
    if (event.isEmpty() || id.isEmpty()) return false;
    String content = data.has("live_updates_content") ? data.getString("live_updates_content") : null;
    switch (event) {
      case "start":
        if (content == null) return false;
        {
          Context c = requireContext();
          clearDismissed(c, id);
          // Nothing could be shown: post nothing, so nothing is reported
          // started (as for local starts and schedules).
          String reason = notShowableReason(c, content);
          if (reason != null) {
            Log.w(LOG_TAG, "A remote live update was not shown: " + reason);
            return true;
          }
          post(id, warnIfUntitled(new JSONObject(content)), true);
          return true;
        }
      case "update":
        if (content == null) return false;
        // Do not bring back an update that ended or that the user dismissed.
        if (!isDismissed(requireContext(), id) && isShown(id)) {
          post(id, warnIfUntitled(new JSONObject(content)), true);
        }
        return true;
      case "end":
        {
          // Final content only for an update that is shown: never bring back
          // one the user dismissed. Without a dismiss time it stays for four
          // hours, as with LiveUpdate.end().
          Context c = requireContext();
          boolean visible = isShown(id) && !isDismissed(c, id);
          end(
              id,
              visible ? content : null,
              // Missing or not a number: the default (NaN keeps it the longest).
              data.has("live_updates_dismiss_after")
                  ? data.optDouble("live_updates_dismiss_after", Double.NaN)
                  : -1,
              true,
              visible);
          return true;
        }
      default:
        return false;
    }
  }

  /**
   * Calls {@code listener} with lifecycle events: {@code started} (new live
   * update, local or remote), {@code ended} (ended by the app, a payload or a
   * timeout)
   * and {@code dismissed} (swiped away by the user).
   */
  public static void observeEvents(@NonNull EventListener listener, long engineId) {
    synchronized (actionLock) {
      eventListeners.put(engineId, listener);
    }
  }

  /** Called by the dismiss receiver when a timeout removed the update. */
  static void timedOut(Context c, String id) {
    forgetPostsInProcess(id);
    LiveUpdatesScheduler.cancelEnd(c, id);
    forgetStartTime(c, id);
    synchronized (staleIds) {
      staleIds.remove(id);
    }
    synchronized (keyedIds) {
      keyedIds.remove(id);
    }
    emit("ended", id);
  }

  /** Whether live updates can be scheduled: as {@link #isSupported}. */
  public static boolean canSchedule() {
    return isSupported();
  }

  /** Whether scheduled live updates are shown on time (exact alarms). */
  public static boolean canScheduleExactly() {
    Context c = context;
    return c != null && LiveUpdatesScheduler.canScheduleExactly(c);
  }

  /**
   * Opens the screen where the user allows exact alarms for this app (Android 12+); returns
   * whether it was opened.
   */
  public static boolean openExactAlarmSettings() {
    Context c = context;
    return c != null && LiveUpdatesScheduler.openExactAlarmSettings(c, activity);
  }

  /**
   * Shows {@code json} as the live update {@code key} at {@code atMillis} (epoch ms), as {@link
   * #startOrUpdate} would then, replacing the schedule with that key. Uses an exact alarm when
   * {@code exact} and allowed, else an alarm within {@code windowMillis}.
   */
  public static void schedule(
      @NonNull String key, @NonNull String json, long atMillis, boolean exact, long windowMillis)
      throws JSONException {
    requireShowableNow(key, json, atMillis);
    LiveUpdatesScheduler.schedule(requireContext(), key, json, atMillis, exact, windowMillis);
  }

  /**
   * Moves the schedule with {@code key} to {@code atMillis}, with {@code json} as its content when
   * given. Throws when nothing is scheduled with {@code key}.
   */
  public static void reschedule(@NonNull String key, @Nullable String json, long atMillis)
      throws JSONException {
    // Not for a key without a schedule: the scheduler reports that.
    String stored = LiveUpdatesScheduler.storedJson(requireContext(), key);
    if (stored != null) requireShowableNow(key, json != null ? json : stored, atMillis);
    LiveUpdatesScheduler.reschedule(requireContext(), key, json, atMillis);
  }

  /**
   * A schedule for a time that has passed shows its update now: it fails as startOrUpdate does
   * (not for a key the user dismissed, which startOrUpdate leaves alone).
   */
  private static void requireShowableNow(String key, @Nullable String json, long atMillis) {
    Context c = requireContext();
    if (json == null || atMillis > System.currentTimeMillis() || isDismissed(c, key)) return;
    requireShowable(c, json);
  }

  /** Scheduled live updates as a JSON array of {@code {"key", "at"}} (epoch seconds). */
  @NonNull
  public static String scheduledJson() {
    Context c = context;
    return c == null ? "[]" : LiveUpdatesScheduler.scheduledJson(c);
  }

  /** Cancels every schedule (not the endAt alarms of shown updates). */
  public static void cancelAllScheduled() {
    Context c = context;
    if (c != null) LiveUpdatesScheduler.cancelAll(c);
  }

  /** Cancels the schedule with {@code key}, if any. */
  public static void cancelScheduled(@NonNull String key) {
    LiveUpdatesScheduler.cancel(requireContext(), key);
  }

  /** Removes every live update of this app, also ended ones (not the scheduled ones). */
  public static void endAll() throws JSONException {
    for (String id : activeIds()) end(id, null, 0);
    Context c = requireContext();
    List<String> kept;
    synchronized (keptEnded) {
      kept = new ArrayList<>(keptEnded);
      keptEnded.clear();
    }
    for (String id : kept) manager(c).cancel(TAG_PREFIX + id, NOTIFICATION_ID);
    for (StatusBarNotification n : manager(c).getActiveNotifications()) {
      String tag = n.getTag();
      if (n.getId() == NOTIFICATION_ID && tag != null && tag.startsWith(TAG_PREFIX)) {
        manager(c).cancel(tag, NOTIFICATION_ID);
      }
    }
  }

  static void emit(String event, String id) {
    if (event.equals("ended") || event.equals("dismissed")) {
      synchronized (known) {
        known.remove(id);
      }
    }
    List<EventListener> listeners;
    synchronized (actionLock) {
      listeners = new ArrayList<>(eventListeners.values());
    }
    for (EventListener l : listeners) l.onEvent(event + ":" + id);
  }

  /** Calls {@code listener} with every tap route, including one that launched the app. */
  public static void observeTaps(@NonNull RouteListener listener, long engineId) {
    List<String> pending;
    synchronized (actionLock) {
      routeListeners.put(engineId, listener);
      pending = new ArrayList<>(pendingRoutes);
      pendingRoutes.clear();
    }
    for (String route : pending) listener.onRoute(route);
  }

  /** Called by the plugin for launch and new intents. */
  static void handleIntent(@Nullable Intent intent) {
    Context c = context;
    if (intent == null || c == null) return;
    String token, actionId, updateId, route;
    try {
      token = intent.getStringExtra(EXTRA_TOKEN);
      actionId = intent.getStringExtra(EXTRA_ACTION_ID);
      updateId = intent.getStringExtra(EXTRA_UPDATE_ID);
      route = intent.getStringExtra(EXTRA_ROUTE);
    } catch (RuntimeException e) {
      return; // Malformed extras from another app.
    }
    if (token == null && actionId == null && route == null) return;
    intent.removeExtra(EXTRA_TOKEN);
    intent.removeExtra(EXTRA_ACTION_ID);
    intent.removeExtra(EXTRA_UPDATE_ID);
    intent.removeExtra(EXTRA_ROUTE);
    if (!intentToken(c).equals(token)) return; // Not from our notifications.
    // The data URI only keeps the PendingIntents apart; clear it before
    // Flutter reads it as a deep link (plugins see the intent first).
    Uri data = intent.getData();
    if (data != null && INTENT_SCHEME.equals(data.getScheme())) intent.setData(null);
    // Recreated from Recents: the original launch intent comes back; it was
    // handled when it first arrived.
    if ((intent.getFlags() & Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return;
    if (actionId != null && updateId != null) {
      // Open-app press: the app is coming to the foreground, so its onAction
      // listener takes it. If none does soon, the background handler runs it.
      emitAction(c, updateId, actionId, null, false);
      new android.os.Handler(android.os.Looper.getMainLooper())
          .postDelayed(
              () -> {
                synchronized (actionLock) {
                  drainActions();
                }
                runQueuedInBackground();
              },
              OPEN_APP_GRACE_MS);
    }
    if (route == null) return;
    List<RouteListener> listeners;
    synchronized (actionLock) {
      listeners = new ArrayList<>(routeListeners.values());
      if (listeners.isEmpty()) pendingRoutes.add(route);
    }
    for (RouteListener l : listeners) l.onRoute(route);
  }

  private static void post(String id, JSONObject content) {
    post(id, content, false, false);
  }

  private static void post(String id, JSONObject content, boolean remote) {
    post(id, content, remote, remote);
  }

  /** {@code keyed}: the id is a key (startOrUpdate, remote payloads). */
  private static void post(String id, JSONObject content, boolean remote, boolean keyed) {
    post(id, content, remote, keyed, false);
  }

  /**
   * {@code stale}: {@code content} is the ended content shown from endAt on, as a regular
   * notification that still counts as running (see {@link #EXTRA_STALE}).
   */
  private static void post(
      String id, JSONObject content, boolean remote, boolean keyed, boolean stale) {
    Context c = requireContext();
    // Survives process restarts: a notification already shown is not new.
    boolean wasShown = isShown(id);
    long now = System.currentTimeMillis();
    // When the update must be removed (maxDuration from its start, or endAt
    // with removeAtEnd), and when it becomes stale (endAt).
    long started = startTime(c, id, wasShown, now);
    long maxDuration = content.optLong("maxDurationMillis", DEFAULT_MAX_DURATION_MS);
    long removeAt = maxDuration > 0 ? started + maxDuration : 0;
    long endAt = epochMillis(content, "endAt");
    JSONObject endedContent = content.optJSONObject("endedContent");
    if (endedContent != null && optString(endedContent, "title") == null) endedContent = null;
    boolean removeAtEnd = content.optBoolean("removeAtEnd", false);
    if (endAt > 0 && removeAtEnd && (removeAt == 0 || endAt < removeAt)) removeAt = endAt;
    boolean staleAtEnd = !stale && endAt > 0 && !removeAtEnd;
    if (removeAt > 0 && removeAt <= now) {
      // Already over: never posted, and ended if it was shown.
      LiveUpdatesScheduler.cancelEnd(c, id);
      try {
        end(id, null, 0, remote, wasShown);
      } catch (JSONException e) {
        // Not without content.
      }
      return;
    }
    boolean staleNow = false;
    if (staleAtEnd) {
      JSONObject staleContent =
          endedContent == null ? null : staleContent(content, endedContent);
      if (endAt <= now) {
        // Already over: shown as stale right away.
        LiveUpdatesScheduler.cancelEnd(c, id);
        if (staleContent != null) {
          post(id, staleContent, remote, keyed, true);
          markStale(id);
          return;
        }
        staleNow = true;
      } else {
        LiveUpdatesScheduler.scheduleEnd(
            c, id, endAt, staleContent == null ? "" : staleContent.toString(), remote);
      }
    } else if (!stale) {
      LiveUpdatesScheduler.cancelEnd(c, id);
    }
    // New content that is not over makes a stale update active again.
    boolean activeAgain = false;
    if (!stale && !staleNow) {
      synchronized (staleIds) {
        activeAgain = staleIds.remove(id);
      }
      // After a process restart: the marker on the shown notification.
      if (!activeAgain && wasShown) activeAgain = showsStale(c, id);
    }
    synchronized (recentlyPosted) {
      recentlyEnded.remove(id);
      recentlyPosted.put(id, SystemClock.uptimeMillis());
    }
    boolean isNew;
    synchronized (known) {
      isNew = known.add(id) && !wasShown;
    }
    // Before "started", so a listener can read the key at once.
    if (keyed) {
      synchronized (keyedIds) {
        keyedIds.add(id);
      }
    }
    if (isNew) emit("started", id);
    // Stale: the ended content's look (not ongoing or promoted, dismissible),
    // but not cancelled by a tap, as the update keeps running.
    Notification.Builder b =
        stale ? builder(c, content, remote, true).setAutoCancel(false) : builder(c, content, remote);
    if (wantsAlert(content, remote) && !mayAlert(id)) b.setOnlyAlertOnce(true);
    // The system sends the delete intent for timeouts too; the deadline lets
    // the receiver tell them from a swipe.
    long timeout = content.optLong("timeoutAfterMillis", 0);
    if (timeout > 0) timeout = Math.max(timeout, MIN_TIMEOUT_MS);
    if (removeAt > 0 && (timeout <= 0 || removeAt - now < timeout)) timeout = removeAt - now;
    // A notification's countdown cannot stop at zero and would run below it
    // (iOS stops at zero): the update is removed when it ends, unless
    // removeAtCountdownEnd is false, or endedContent replaces it by then
    // (without the timer) on time, which needs exact alarms.
    double countdownEnd = content.optDouble("timerEnd", Double.NaN);
    if (!stale && isTime(countdownEnd) && content.optBoolean("removeAtCountdownEnd", true)) {
      long end = (long) (countdownEnd * 1000);
      boolean replacedFirst =
          staleAtEnd
              && endedContent != null
              && endAt <= end
              && LiveUpdatesScheduler.canScheduleExactly(c);
      // When the ended content should replace it first, a later removal
      // still covers an alarm that never comes (the user can revoke exact
      // alarms, which cancels them); the replacement resets it.
      long left = (replacedFirst ? end + ENDED_CONTENT_GRACE_MS : end) - now;
      // A payload cannot make an update vanish at once (as timeoutAfter).
      if (remote) left = Math.max(left, MIN_TIMEOUT_MS);
      if (end > now && (timeout <= 0 || left < timeout)) timeout = left;
    }
    long deadline = 0;
    if (timeout > 0 && Build.VERSION.SDK_INT >= 26) {
      b.setTimeoutAfter(timeout);
      deadline = now + timeout;
    }
    b.setDeleteIntent(LiveUpdatesDismissReceiver.intent(c, id, deadline));
    // update() keeps the marker of the shown notification.
    android.os.Bundle extras = new android.os.Bundle();
    if (keyed || keyForId(id) != null) extras.putBoolean(EXTRA_KEYED, true);
    if (stale) extras.putBoolean(EXTRA_STALE, true);
    // Lets stateOf() tell a stale update after a process restart.
    if (staleAtEnd) extras.putLong(EXTRA_END_AT, endAt);
    if (!extras.isEmpty()) b.addExtras(extras);
    if (!stale) addActions(c, b, id, content);
    synchronized (lastPosted) {
      lastPosted.put(id, new Object[] {content, remote});
    }
    boolean replacesEnded;
    synchronized (keptEnded) {
      replacesEnded = keptEnded.remove(id);
    }
    // A new update with the id of an ended one that is still shown: remove
    // that one first, so the start alerts like any other.
    if (!wasShown && !stale && (replacesEnded || isListed(c, id))) {
      manager(c).cancel(TAG_PREFIX + id, NOTIFICATION_ID);
    }
    manager(c).notify(TAG_PREFIX + id, NOTIFICATION_ID, b.build());
    if (staleNow) markStale(id);
    if (activeAgain) emit("active", id);
  }

  /**
   * Notification extra marking the ended content of a stale update: not ongoing, but still
   * listed by {@link #activeIds}.
   */
  static final String EXTRA_STALE = "com.ttechapp.live_updates.STALE";

  /** Updates reported stale in this process, so each change is reported once. */
  private static final Set<String> staleIds = new java.util.HashSet<>();

  private static boolean showsStale(Context c, String id) {
    for (StatusBarNotification n : manager(c).getActiveNotifications()) {
      if (n.getId() == NOTIFICATION_ID && (TAG_PREFIX + id).equals(n.getTag())) {
        return n.getNotification().extras.getBoolean(EXTRA_STALE, false);
      }
    }
    return false;
  }

  private static void markStale(String id) {
    boolean changed;
    synchronized (staleIds) {
      changed = staleIds.add(id);
    }
    if (changed) emit("stale", id);
  }

  private static final String DEFAULT_CHANNEL = "live_updates";

  /** {@code AndroidLiveUpdateOptions.maxDuration} when the content has none: 8 hours. */
  static final long DEFAULT_MAX_DURATION_MS = 8 * 60 * 60_000L;

  private static final String PREF_START_TIMES = "startTimes";

  /**
   * When the live update {@code id} started (epoch ms), for maxDuration: now for a new one, the
   * stored time for one that is shown (later posts do not reset it).
   */
  private static long startTime(Context c, String id, boolean wasShown, long now) {
    synchronized (actionLock) {
      JSONObject times = readObject(prefs(c), PREF_START_TIMES);
      long stored = times.optLong(id, 0);
      if (wasShown && stored > 0 && stored <= now) return stored;
      try {
        if (!wasShown) {
          // Drop updates that are no longer shown.
          Set<String> shown = new java.util.HashSet<>(Arrays.asList(activeIds()));
          List<String> stale = new ArrayList<>();
          for (java.util.Iterator<String> it = times.keys(); it.hasNext(); ) {
            String key = it.next();
            if (!shown.contains(key)) stale.add(key);
          }
          for (String key : stale) times.remove(key);
        }
        times.put(id, now);
      } catch (JSONException e) {
        // Not for a number.
      }
      prefs(c).edit().putString(PREF_START_TIMES, times.toString()).apply();
      return now;
    }
  }

  private static void forgetStartTime(Context c, String id) {
    synchronized (actionLock) {
      JSONObject times = readObject(prefs(c), PREF_START_TIMES);
      if (times.remove(id) != null) {
        prefs(c).edit().putString(PREF_START_TIMES, times.toString()).apply();
      }
    }
  }

  private static JSONObject readObject(SharedPreferences prefs, String key) {
    try {
      return new JSONObject(prefs.getString(key, "{}"));
    } catch (JSONException e) {
      return new JSONObject();
    }
  }

  /** {@code key} in seconds since 1970 as epoch ms, or 0 when missing or out of range. */
  private static long epochMillis(JSONObject content, String key) {
    double seconds = content.optDouble(key, Double.NaN);
    return isTime(seconds) ? (long) (seconds * 1000) : 0;
  }

  /**
   * The notification shown from endAt on: {@code ended}'s title, body, icon (else the content's)
   * and image with the channel, small icon option, color, tap route, lock screen setting, custom
   * layout and time limits (maxDuration, timeoutAfter) of {@code content}.
   */
  static JSONObject staleContent(JSONObject content, JSONObject ended) {
    JSONObject out = new JSONObject();
    try {
      copy(
          content,
          out,
          new String[] {
            "channelId",
            "channelName",
            "icon",
            "androidSmallIcon",
            "colorArgb",
            "route",
            "androidLockScreenVisibility",
            "maxDurationMillis",
            "timeoutAfterMillis",
            "androidLayout",
            "androidExpandedLayout"
          });
      out.put("title", ended.optString("title"));
      String body = optString(ended, "body");
      if (body != null) out.put("body", body);
      // The ended icon replaces the content's icon (androidSmallIcon still
      // wins); the ended image is the only image.
      JSONObject icon = ended.optJSONObject("icon");
      if (icon != null) out.put("icon", icon);
      String image = optString(ended, "image");
      if (image != null) out.put("image", image);
    } catch (JSONException e) {
      // Cannot happen: values come from parsed JSON.
    }
    return out;
  }

  /**
   * The endAt alarm of {@code id} fired: the update becomes stale, showing its ended content
   * ({@code json}, empty for none) if it is still shown.
   */
  static void endAlarmFired(Context c, String id, String json, boolean remote) {
    if (context == null) context = c.getApplicationContext();
    if (!isShown(id) || isDismissed(c, id)) return;
    if (!json.isEmpty()) {
      try {
        post(id, new JSONObject(json), remote, keyForId(id) != null, true);
      } catch (JSONException e) {
        Log.w(LOG_TAG, "endedContent: " + e.getClass().getName());
        return;
      }
    }
    markStale(id);
  }

  private static Notification.Builder builder(Context c, JSONObject content) {
    return builder(c, content, false);
  }

  /**
   * Remote payloads may only use the default channel or channels that already
   * exist, so a server cannot create arbitrary channels on the device.
   */
  private static Notification.Builder builder(Context c, JSONObject content, boolean remote) {
    return builder(c, content, remote, false);
  }

  /**
   * {@code ended}: final content of an ended update, no longer ongoing or promoted (its public
   * version too).
   */
  private static Notification.Builder builder(
      Context c, JSONObject content, boolean remote, boolean ended) {
    Notification.Builder b;
    if (Build.VERSION.SDK_INT >= 26) {
      String channelId = content.optString("channelId", DEFAULT_CHANNEL);
      NotificationManager manager = manager(c);
      if (remote
          && !channelId.equals(DEFAULT_CHANNEL)
          && manager.getNotificationChannel(channelId) == null) {
        channelId = DEFAULT_CHANNEL;
      }
      if (manager.getNotificationChannel(channelId) == null) {
        manager.createNotificationChannel(
            new NotificationChannel(
                channelId,
                remote ? "Live updates" : content.optString("channelName", "Live updates"),
                NotificationManager.IMPORTANCE_DEFAULT));
      }
      b = new Notification.Builder(c, channelId);
    } else {
      b = new Notification.Builder(c);
    }
    b.setContentTitle(content.optString("title"))
        .setOngoing(true)
        // Only the first post alerts, unless this post asks to.
        .setOnlyAlertOnce(!wantsAlert(content, remote))
        .setSmallIcon(smallIcon(c, content));
    String body = optString(content, "body");
    if (body != null) {
      b.setContentText(
          LiveUpdatesApi37.styledText(
              body, LiveUpdatesApi37.semanticStyle(optString(content, "bodySemanticStyle"))));
    }
    // Custom layouts (androidLayout) replace the system template: no progress
    // style, metrics, promotion or large icon (the layout shows the image).
    android.widget.RemoteViews[] custom = LiveUpdatesCustomLayout.views(c, content, ended);
    String image = optString(content, "image");
    if (custom == null && image != null && !image.contains("/")) {
      android.graphics.Bitmap bitmap =
          android.graphics.BitmapFactory.decodeFile(new java.io.File(imageDir(c), image).getPath());
      if (bitmap != null) b.setLargeIcon(Icon.createWithBitmap(bitmap));
    }
    if (content.has("colorArgb")) b.setColor((int) content.optLong("colorArgb"));
    if (content.has("whenEpochMillis")) {
      b.setWhen(content.optLong("whenEpochMillis")).setShowWhen(true);
    }
    if (content.optBoolean("showChronometer", false)) b.setUsesChronometer(true);
    // LiveUpdateContent.timer: a chronometer counted by the system.
    double timerEnd = content.optDouble("timerEnd", Double.NaN);
    double timerStart = content.optDouble("timerStart", Double.NaN);
    boolean countdown = isTime(timerEnd);
    // A countdown that is over would show below zero: no timer then.
    boolean over = countdown && timerEnd * 1000 <= System.currentTimeMillis();
    if (!over && (countdown || isTime(timerStart))) {
      b.setWhen((long) ((countdown ? timerEnd : timerStart) * 1000))
          .setShowWhen(true)
          .setUsesChronometer(true)
          .setChronometerCountDown(countdown);
    }
    // timeoutAfterMillis is applied by post(), with the other time limits.

    String route = optString(content, "route");
    PendingIntent tap = tapIntent(c, route);
    if (tap != null) b.setContentIntent(tap);

    boolean hasProgress = content.has("progress") && !content.isNull("progress");
    int progress = hasProgress ? (int) Math.round(content.optDouble("progress") * 100) : 0;
    JSONObject steps = content.optJSONObject("steps");
    int stepCount = steps == null ? 0 : stepLabels(steps).size();
    int currentStep =
        stepCount == 0 ? 0 : Math.max(0, Math.min(steps.optInt("current", 0), stepCount - 1));
    String mode = androidMode(content);
    boolean metrics = false;
    boolean styled = false;
    if (custom != null) {
      LiveUpdatesCustomLayout.apply(b, custom);
    } else if (Build.VERSION.SDK_INT >= 36 && !"classic".equals(mode)) {
      requestPromotedOngoing(b, "liveUpdate".equals(mode));
      String chip = optString(content, "shortCriticalText");
      if (chip != null) b.setShortCriticalText(chip);
      metrics =
          LiveUpdatesApi37.setMetricStyle(
              b, content.optJSONArray("metrics"), content.optInt("criticalMetric", -1));
      if (!metrics && (hasProgress || stepCount >= 2)) {
        double fraction =
            hasProgress
                ? content.optDouble("progress")
                : (double) currentStep / (stepCount - 1);
        b.setStyle(progressStyle(c, content, fraction));
      }
      // Android 16+ (liveUpdate, ongoing) keeps the sub text as before:
      // ProgressStyle and MetricStyle show it as a line of its own; without a
      // style it stays in the header.
      styled = true;
    } else if (hasProgress) {
      b.setProgress(100, progress, false);
    } else if (stepCount >= 2) {
      b.setProgress(stepCount - 1, currentStep, false);
    }
    // Steps, journey and (unless MetricStyle shows them) metrics as text: the
    // body line when there is no body. Otherwise the sub text on Android 16+
    // (liveUpdate, ongoing); the regular notification (classic, Android 15 and
    // earlier) squeezes the sub text into the header, so there it becomes a
    // second line of the expanded notification instead.
    String detail = custom != null ? null : detailText(content, !metrics);
    if (detail != null) {
      if (body == null) {
        b.setContentText(detail);
      } else if (styled) {
        b.setSubText(detail);
      } else {
        b.setStyle(new Notification.BigTextStyle().bigText(body + "\n" + detail));
      }
    }
    if (ended) {
      b.setOngoing(false).setAutoCancel(true);
      requestPromotedOngoing(b, false);
    }
    lockScreen(c, b, content, remote, ended);
    return b;
  }

  /**
   * Visibility on a secure lock screen while the user hides sensitive content there: {@code
   * androidLockScreenVisibility} {@code secret} hides the notification; otherwise it is private,
   * with a public version made from {@code publicContent} when present (without it the system
   * shows only basic information without the content).
   */
  private static void lockScreen(
      Context c, Notification.Builder b, JSONObject content, boolean remote, boolean ended) {
    boolean secret = "secret".equals(optString(content, "androidLockScreenVisibility"));
    b.setVisibility(secret ? Notification.VISIBILITY_SECRET : Notification.VISIBILITY_PRIVATE);
    JSONObject pub = secret ? null : content.optJSONObject("publicContent");
    if (pub == null || optString(pub, "title") == null) return;
    try {
      b.setPublicVersion(builder(c, publicContent(content, pub), remote, ended).build());
    } catch (JSONException e) {
      // Cannot happen: only strings, numbers and parsed JSON values are put.
      Log.w(LOG_TAG, "publicContent: " + e.getMessage());
    }
  }

  /** Keys of the full content that the public version keeps (the rest may be private). */
  private static final String[] PUBLIC_KEYS = {
    "channelId", "channelName", "androidSmallIcon", "icon", "colorArgb", "androidMode",
    "requestPromotion", "route",
  };

  private static final String[] PUBLIC_PROGRESS_KEYS = {
    "progress", "progressSegments", "progressPoints", "progressSemanticStyle",
  };

  private static final String[] PUBLIC_TIMER_KEYS = {
    "timerStart", "timerEnd", "whenEpochMillis", "showChronometer",
  };

  /**
   * The content of the public version: {@code publicContent}'s title and body, the icon, color,
   * channel, mode and tap route of {@code content}, and its progress and timer unless {@code
   * keepProgress} or {@code keepTimer} is false. Images, actions, metrics, steps, the journey, the
   * progress tracker icon and {@code shortCriticalText} are left out.
   */
  static JSONObject publicContent(JSONObject content, JSONObject pub) throws JSONException {
    JSONObject out = new JSONObject();
    copy(content, out, PUBLIC_KEYS);
    if (keep(pub, "keepProgress")) copy(content, out, PUBLIC_PROGRESS_KEYS);
    if (keep(pub, "keepTimer")) copy(content, out, PUBLIC_TIMER_KEYS);
    out.put("title", optString(pub, "title"));
    String body = optString(pub, "body");
    if (body != null) out.put("body", body);
    return out;
  }

  /**
   * {@code true} when the key is missing or null; otherwise only a real {@code true} keeps the
   * value ({@code "false"} or {@code 0} hides it).
   */
  private static boolean keep(JSONObject pub, String key) {
    return !present(pub, key) || Boolean.TRUE.equals(pub.opt(key));
  }

  private static void copy(JSONObject from, JSONObject to, String[] keys) throws JSONException {
    for (String key : keys) {
      if (present(from, key)) to.put(key, from.get(key));
    }
  }

  private static List<String> stepLabels(JSONObject steps) {
    List<String> labels = new ArrayList<>();
    org.json.JSONArray a = steps.optJSONArray("labels");
    for (int i = 0; a != null && i < a.length() && labels.size() < MAX_STEPS; i++) {
      labels.add(a.optString(i));
    }
    return labels;
  }

  private static final int MAX_DETAIL_TEXT = 80;

  /** Limit for remote payloads; more stages than segments are shown as text only. */
  private static final int MAX_STEPS = 100;

  /** Length of each segment made from steps, so {@code progress} keeps its resolution. */
  private static final int STEP_SEGMENT_LENGTH = 100;

  /**
   * "2/4 Preparing", "From → To" and, with {@code withMetrics}, "Label: value
   * unit" for numbers and text (timers are left to the chronometer), joined
   * with " · ". Null when there is nothing to show.
   */
  @Nullable
  static String detailText(JSONObject content, boolean withMetrics) {
    List<String> parts = new ArrayList<>();
    JSONObject steps = content.optJSONObject("steps");
    if (steps != null) {
      List<String> labels = stepLabels(steps);
      if (labels.size() >= 2) {
        int current = Math.max(0, Math.min(steps.optInt("current", 0), labels.size() - 1));
        parts.add((current + 1) + "/" + labels.size() + " " + clip(labels.get(current)));
      }
    }
    JSONObject journey = content.optJSONObject("journey");
    String from = journey == null ? null : optString(journey, "from");
    String to = journey == null ? null : optString(journey, "to");
    if (from != null && to != null && !from.isEmpty() && !to.isEmpty()) {
      parts.add(clip(from) + " → " + clip(to));
    }
    org.json.JSONArray metrics = withMetrics ? content.optJSONArray("metrics") : null;
    for (int i = 0; metrics != null && i < metrics.length() && i < 3; i++) {
      JSONObject m = metrics.optJSONObject(i);
      if (m == null) continue;
      Object value = m.opt("value");
      String type = m.optString("type");
      String text;
      if ("integer".equals(type) && value instanceof Number) {
        text = String.valueOf(((Number) value).longValue());
      } else if ("decimal".equals(type) && value instanceof Number) {
        double d = ((Number) value).doubleValue();
        if (Double.isNaN(d) || Double.isInfinite(d)) continue;
        int digits = Math.max(0, Math.min(m.optInt("fractionDigits", 1), 6));
        java.text.NumberFormat f = java.text.NumberFormat.getNumberInstance();
        f.setMaximumFractionDigits(digits);
        text = f.format(d);
      } else if ("text".equals(type) && value instanceof String) {
        text = clip((String) value);
      } else {
        continue;
      }
      String unit = optString(m, "unit");
      parts.add(clip(m.optString("label")) + ": " + text + (unit == null ? "" : " " + clip(unit)));
    }
    if (parts.isEmpty()) return null;
    return android.text.TextUtils.join(" · ", parts);
  }

  private static String clip(String text) {
    if (text.length() <= MAX_DETAIL_TEXT) return text;
    int end = MAX_DETAIL_TEXT;
    // Do not split a surrogate pair.
    if (Character.isHighSurrogate(text.charAt(end - 1))) end--;
    return text.substring(0, end);
  }

  /**
   * {@code liveUpdate} (default), {@code ongoing} or {@code classic}. Payloads
   * from before {@code androidMode} existed may send {@code requestPromotion:
   * false}, which means {@code ongoing}.
   */
  static String androidMode(JSONObject content) {
    String mode = optString(content, "androidMode");
    if ("ongoing".equals(mode) || "classic".equals(mode)) return mode;
    if (mode == null && !content.optBoolean("requestPromotion", true)) return "ongoing";
    return "liveUpdate";
  }

  /**
   * Logs a warning when remote {@code content} asks for promotion without a
   * title, which Android requires to promote a notification; returns {@code
   * content}.
   */
  private static JSONObject warnIfUntitled(JSONObject content) {
    // A custom layout is never promoted.
    if ("liveUpdate".equals(androidMode(content))
        && !LiveUpdatesCustomLayout.requested(content)
        && content.optString("title").isEmpty()) {
      Log.w(
          LOG_TAG,
          "title is empty; Android only promotes a notification to a Live Update when it has"
              + " a title.");
    }
    return content;
  }

  /** Time an app opened by a button gets to start listening to {@code onAction}. */
  private static final long OPEN_APP_GRACE_MS = 5_000;

  /** At most one requested alert per update in this interval (remote payloads included). */
  private static final long MIN_ALERT_INTERVAL_MS = 10_000;

  /**
   * Whether this post should alert: {@code androidAlert} when given, else in a remote payload the
   * iOS {@code alert} object, so one content alerts on both platforms.
   */
  static boolean wantsAlert(JSONObject content, boolean remote) {
    if (content.has("androidAlert")) return content.optBoolean("androidAlert", false);
    return remote && content.optJSONObject("alert") != null;
  }

  private static final Map<String, Long> lastAlert = new HashMap<>();

  private static boolean mayAlert(String id) {
    long now = SystemClock.uptimeMillis();
    synchronized (lastAlert) {
      Long last = lastAlert.get(id);
      if (last != null && now - last < MIN_ALERT_INTERVAL_MS) return false;
      lastAlert.put(id, now);
      return true;
    }
  }

  private static boolean isTime(double seconds) {
    return !Double.isNaN(seconds) && !Double.isInfinite(seconds) && Math.abs(seconds) < 1e11;
  }

  private static final long MIN_TIMEOUT_MS = 60_000;

  /** Longest window Android gives an inexact alarm: the ended content comes by then. */
  private static final long ENDED_CONTENT_GRACE_MS = 10 * 60_000;

  /** Limits for remote payloads; the system draws far fewer anyway. */
  private static final int MAX_PROGRESS_PARTS = 20;

  private static final int MAX_SEGMENT_LENGTH = 10_000;

  /**
   * Android 16 {@code ProgressStyle}: {@code progressSegments} (relative
   * lengths), {@code progressPoints} (positions from 0 to 1) and {@code
   * progressTrackerIcon}. {@code fraction} runs over the whole bar.
   */
  @androidx.annotation.RequiresApi(36)
  private static Notification.ProgressStyle progressStyle(
      Context c, JSONObject content, double fraction) {
    Notification.ProgressStyle style = new Notification.ProgressStyle();
    int total = 0;
    org.json.JSONArray segments = content.optJSONArray("progressSegments");
    if (segments != null) {
      for (int i = 0; i < segments.length() && i < MAX_PROGRESS_PARTS; i++) {
        JSONObject s = segments.optJSONObject(i);
        if (s == null) continue;
        int length = Math.max(1, Math.min(s.optInt("length", 1), MAX_SEGMENT_LENGTH));
        Notification.ProgressStyle.Segment segment = new Notification.ProgressStyle.Segment(length);
        if (s.has("colorArgb")) segment.setColor((int) s.optLong("colorArgb"));
        LiveUpdatesApi37.styleSegment(
            segment, LiveUpdatesApi37.semanticStyle(optString(s, "semanticStyle")));
        style.addProgressSegment(segment);
        total += length;
      }
    }
    JSONObject steps = content.optJSONObject("steps");
    int stepCount = steps == null ? 0 : stepLabels(steps).size();
    if (total == 0
        && stepCount >= 2
        && stepCount - 1 <= MAX_PROGRESS_PARTS
        && content.optJSONArray("progressPoints") == null) {
      // One segment between each pair of stages and a point at each stage
      // after the first (the system ignores a point at the start).
      int semantic = LiveUpdatesApi37.semanticStyle(optString(content, "progressSemanticStyle"));
      for (int i = 1; i < stepCount; i++) {
        Notification.ProgressStyle.Segment segment =
            new Notification.ProgressStyle.Segment(STEP_SEGMENT_LENGTH);
        LiveUpdatesApi37.styleSegment(segment, semantic);
        style.addProgressSegment(segment);
        style.addProgressPoint(new Notification.ProgressStyle.Point(i * STEP_SEGMENT_LENGTH));
      }
      total = (stepCount - 1) * STEP_SEGMENT_LENGTH;
    }
    if (total == 0) {
      total = 100;
      int semantic = LiveUpdatesApi37.semanticStyle(optString(content, "progressSemanticStyle"));
      if (semantic != 0 && LiveUpdatesApi37.available()) {
        Notification.ProgressStyle.Segment segment = new Notification.ProgressStyle.Segment(total);
        LiveUpdatesApi37.styleSegment(segment, semantic);
        style.addProgressSegment(segment);
      }
    }
    org.json.JSONArray points = content.optJSONArray("progressPoints");
    if (points != null) {
      for (int i = 0; i < points.length() && i < MAX_PROGRESS_PARTS; i++) {
        JSONObject p = points.optJSONObject(i);
        if (p == null) continue;
        double position = p.optDouble("position", Double.NaN);
        if (Double.isNaN(position)) continue;
        int at = (int) Math.round(Math.max(0, Math.min(position, 1)) * total);
        Notification.ProgressStyle.Point point = new Notification.ProgressStyle.Point(at);
        if (p.has("colorArgb")) point.setColor((int) p.optLong("colorArgb"));
        LiveUpdatesApi37.stylePoint(
            point, LiveUpdatesApi37.semanticStyle(optString(p, "semanticStyle")));
        style.addProgressPoint(point);
      }
    }
    JSONObject tracker = iconSpec(content, "progressTrackerIcon");
    Icon trackerIcon =
        tracker == null ? null : icon(c, tracker, TRACKER_ICON_PX, "progress tracker icon");
    if (trackerIcon != null) style.setProgressTrackerIcon(trackerIcon);
    double clamped = Double.isNaN(fraction) ? 0 : Math.max(0, Math.min(fraction, 1));
    return style.setProgress((int) Math.round(clamped * total));
  }

  /** Adds {@code actions} (at most three are shown by the system). */
  private static void addActions(
      Context c, Notification.Builder b, String id, JSONObject content) {
    org.json.JSONArray actions = content.optJSONArray("actions");
    if (actions == null) return;
    for (int i = 0; i < actions.length(); i++) {
      JSONObject a = actions.optJSONObject(i);
      if (a == null) continue;
      String actionId = a.optString("id");
      PendingIntent pi;
      if (a.optBoolean("opensApp", false)) {
        Intent launch = c.getPackageManager().getLaunchIntentForPackage(c.getPackageName());
        if (launch == null) continue;
        launch.setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        launch
            .putExtra(EXTRA_UPDATE_ID, id)
            .putExtra(EXTRA_ACTION_ID, actionId)
            .putExtra(EXTRA_TOKEN, intentToken(c));
        launch.setData(intentUri("action", id, actionId));
        pi =
            PendingIntent.getActivity(
                c, 0, launch, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
      } else {
        pi = LiveUpdatesActionReceiver.intent(c, id, actionId);
      }
      Notification.Action.Builder action =
          new Notification.Action.Builder(actionIcon(c, a), a.optString("title"), pi);
      if (a.optBoolean("requiresUnlock", false) && Build.VERSION.SDK_INT >= 31) {
        action.setAuthenticationRequired(true);
      }
      b.addAction(action.build());
    }
  }

  /**
   * Same as {@code Notification.Builder#setRequestPromotedOngoing}, which is
   * not in the API 36 stubs; the extra is honored from Android 16 on and is
   * not written on older versions.
   */
  private static void requestPromotedOngoing(Notification.Builder b, boolean value) {
    if (Build.VERSION.SDK_INT < 36) return;
    b.getExtras().putBoolean(EXTRA_REQUEST_PROMOTED_ONGOING, value);
  }

  private static final String EXTRA_REQUEST_PROMOTED_ONGOING = "android.requestPromotedOngoing";

  @Nullable
  private static PendingIntent tapIntent(Context c, @Nullable String route) {
    Intent launch = c.getPackageManager().getLaunchIntentForPackage(c.getPackageName());
    if (launch == null) return null;
    launch.setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
    if (route != null) {
      launch.putExtra(EXTRA_ROUTE, route).putExtra(EXTRA_TOKEN, intentToken(c));
      launch.setData(intentUri("tap", route, ""));
    }
    return PendingIntent.getActivity(
        c, 0, launch, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
  }

  /**
   * Makes each PendingIntent distinct by its data URI (request codes from
   * hashes can collide and FLAG_UPDATE_CURRENT would overwrite extras).
   */
  private static final String INTENT_SCHEME = "liveupdates";

  static Uri intentUri(String kind, String a, String b) {
    return new Uri.Builder()
        .scheme(INTENT_SCHEME)
        .authority(kind)
        .appendQueryParameter("a", a)
        .appendQueryParameter("b", b)
        .build();
  }

  /**
   * The small icon: {@code androidSmallIcon}, else {@code icon}, else the default. An icon that
   * cannot be shown falls back to the default (not to the next key), with a warning.
   */
  static Icon smallIcon(Context c, JSONObject content) {
    return iconOrDefault(c, content, "androidSmallIcon", "small icon");
  }

  private static final String ACTION_ICON = "action icon";

  /**
   * An action's icon: {@code androidIcon}, else {@code icon}, else the default. Android 7.0+
   * templates do not show it, but it is required and passed on (for example to watches).
   */
  private static Icon actionIcon(Context c, JSONObject action) {
    return iconOrDefault(c, action, "androidIcon", ACTION_ICON);
  }

  /**
   * The icon under {@code key} if present, else under {@code icon}, else the default. Only the
   * first present key is used: if it cannot be shown (including a value that is not an icon
   * object), the default is used, not the next key.
   */
  private static Icon iconOrDefault(Context c, JSONObject obj, String key, String what) {
    String chosen = present(obj, key) ? key : present(obj, "icon") ? "icon" : null;
    JSONObject spec = chosen == null ? null : iconSpec(obj, chosen);
    Icon icon = spec == null ? null : icon(c, spec, SMALL_ICON_PX, what);
    return icon != null ? icon : defaultIcon(c);
  }

  private static boolean present(JSONObject obj, String key) {
    return obj.has(key) && !obj.isNull(key);
  }

  /**
   * The drawable named by the {@link #DEFAULT_ICON_META} meta-data, else the app icon. A
   * meta-data value that is not a drawable or mipmap is ignored with a warning: the system rejects
   * a notification whose small icon cannot be loaded.
   */
  static Icon defaultIcon(Context c) {
    int res = defaultIconRes;
    if (res == 0) {
      try {
        ApplicationInfo info =
            c.getPackageManager()
                .getApplicationInfo(c.getPackageName(), PackageManager.GET_META_DATA);
        if (info.metaData != null && info.metaData.containsKey(DEFAULT_ICON_META)) {
          res = info.metaData.getInt(DEFAULT_ICON_META, 0);
          if (!isDrawable(c, res)) {
            Log.w(
                LOG_TAG,
                DEFAULT_ICON_META
                    + " must be android:resource=\"@drawable/...\"; using the app icon.");
            res = 0;
          }
        }
      } catch (PackageManager.NameNotFoundException e) {
        // Our own package: cannot happen.
      }
      if (res == 0) res = c.getApplicationInfo().icon;
      // An app without an icon: a system drawable, so the notification is still valid.
      if (res == 0) res = android.R.drawable.sym_def_app_icon;
      defaultIconRes = res;
    }
    return Icon.createWithResource(c, res);
  }

  /** Whether {@code res} is a drawable or mipmap resource. */
  private static boolean isDrawable(Context c, int res) {
    if (res == 0) return false;
    try {
      String type = c.getResources().getResourceTypeName(res);
      return "drawable".equals(type) || "mipmap".equals(type);
    } catch (RuntimeException e) {
      // Resources.NotFoundException: no such resource.
      return false;
    }
  }

  /** The icon object under {@code key}, or null (with a warning if it is not an object). */
  @Nullable
  private static JSONObject iconSpec(JSONObject content, String key) {
    if (!present(content, key)) return null;
    JSONObject spec = content.optJSONObject(key);
    if (spec == null) {
      Log.w(LOG_TAG, key + " must be an object with \"native\", \"asset\" or \"symbol\".");
    }
    return spec;
  }

  /**
   * The icon described by {@code spec} ({@code native}, {@code asset} or {@code symbol}), or null
   * with a warning when it cannot be shown.
   */
  @Nullable
  static Icon icon(Context c, JSONObject spec, int maxPx, String what) {
    String name = optString(spec, "native");
    if (name != null) {
      Icon icon = drawable(c, name);
      if (icon == null) {
        Log.w(
            LOG_TAG,
            what
                + ": no drawable or mipmap named \""
                + name
                + "\" (give the resource name only, and keep it in release builds; see the README).");
      }
      return icon;
    }
    String asset = optString(spec, "asset");
    if (asset != null) {
      Icon icon = asset(c, asset, maxPx);
      if (icon == null) {
        Log.w(LOG_TAG, what + ": Flutter asset \"" + asset + "\" not found or not an image.");
      }
      return icon;
    }
    if (optString(spec, "symbol") != null) {
      // A symbol is fine for an action: Android 7.0+ does not show action icons, so the default
      // passed on to other devices is enough. Elsewhere it is a mistake worth a warning.
      if (!ACTION_ICON.equals(what)) {
        Log.w(LOG_TAG, what + ": symbols are iOS only; using the default.");
      }
      return null;
    }
    Log.w(LOG_TAG, what + ": expected \"native\", \"asset\" or \"symbol\".");
    return null;
  }

  /** A Flutter asset of the app, scaled to at most {@code maxPx}, or null. */
  @Nullable
  private static Icon asset(Context c, String path, int maxPx) {
    // Assets of this app only, by a plain relative path: no empty, "." or ".." segment, no
    // backslash or control character.
    if (path.isEmpty() || path.length() > 1024 || path.indexOf('\\') >= 0) return null;
    for (int i = 0; i < path.length(); i++) {
      if (Character.isISOControl(path.charAt(i))) return null;
    }
    for (String segment : path.split("/", -1)) {
      if (segment.isEmpty() || segment.equals(".") || segment.equals("..")) return null;
    }
    String key;
    try {
      key = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(path);
    } catch (RuntimeException | LinkageError e) {
      // Loader not initialized: the default location of Flutter assets.
      key = "flutter_assets/" + path;
    }
    BitmapFactory.Options bounds = new BitmapFactory.Options();
    bounds.inJustDecodeBounds = true;
    try (InputStream in = c.getAssets().open(key)) {
      BitmapFactory.decodeStream(in, null, bounds);
    } catch (IOException e) {
      return null;
    }
    if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null;
    BitmapFactory.Options options = new BitmapFactory.Options();
    options.inSampleSize = 1; // The default is 0.
    int longest = Math.max(bounds.outWidth, bounds.outHeight);
    while (longest / (options.inSampleSize * 2) >= maxPx) options.inSampleSize *= 2;
    Bitmap bitmap;
    try (InputStream in = c.getAssets().open(key)) {
      bitmap = BitmapFactory.decodeStream(in, null, options);
    } catch (IOException | RuntimeException | OutOfMemoryError e) {
      // Fall back to the default icon rather than failing the post.
      return null;
    }
    if (bitmap == null) return null;
    int w = bitmap.getWidth();
    int h = bitmap.getHeight();
    if (Math.max(w, h) > maxPx) {
      double scale = (double) maxPx / Math.max(w, h);
      bitmap =
          Bitmap.createScaledBitmap(
              bitmap,
              Math.max(1, (int) Math.round(w * scale)),
              Math.max(1, (int) Math.round(h * scale)),
              true);
    }
    return Icon.createWithBitmap(bitmap);
  }

  /** The app's drawable or mipmap {@code name}, or null. */
  @Nullable
  private static Icon drawable(Context c, String name) {
    // A plain resource name only: getIdentifier also accepts "pkg:type/name".
    if (!name.matches("[A-Za-z0-9_]{1,100}")) return null;
    int res = c.getResources().getIdentifier(name, "drawable", c.getPackageName());
    if (res == 0) res = c.getResources().getIdentifier(name, "mipmap", c.getPackageName());
    return res == 0 ? null : Icon.createWithResource(c, res);
  }

  @Nullable
  static String optString(JSONObject o, String key) {
    return o.has(key) && !o.isNull(key) ? o.optString(key) : null;
  }

  private static NotificationManager manager(Context c) {
    return (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
  }

  private static Context requireContext() {
    Context c = context;
    if (c == null) throw new IllegalStateException("live_updates is not attached to an engine");
    return c;
  }
}
