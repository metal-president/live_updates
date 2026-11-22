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
import android.content.pm.PackageManager;
import android.graphics.drawable.Icon;
import android.os.Build;
import android.os.SystemClock;
import android.service.notification.StatusBarNotification;
import androidx.annotation.Keep;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import java.util.ArrayList;
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
 * progress, iconName, route, image, actions}) plus Android options: {@code
 * channelId, channelName, shortCriticalText, colorArgb, whenEpochMillis,
 * showChronometer, androidMode, metrics, criticalMetric,
 * bodySemanticStyle, progressSemanticStyle, progressSegments, progressPoints,
 * progressTrackerIcon, timeoutAfterMillis, androidAlert} and the timer
 * ({@code timerStart} or {@code timerEnd}, seconds since 1970). On Android 16+ progress uses
 * {@link Notification.ProgressStyle} and promotion to a Live Update is
 * requested (shown on builds that support promoted notifications, Android 16
 * QPR1 and later); Android 17 shows {@code metrics} with {@code MetricStyle}
 * instead (see {@link LiveUpdatesApi37}). Older versions get a regular ongoing
 * notification with a progress bar.
 */
@Keep
public final class LiveUpdatesBridge {
  /** Intent extra carrying the tap route. */
  public static final String EXTRA_ROUTE = "com.ttechapp.live_updates.ROUTE";

  static final String EXTRA_UPDATE_ID = "com.ttechapp.live_updates.UPDATE_ID";
  static final String EXTRA_ACTION_ID = "com.ttechapp.live_updates.ACTION_ID";

  static final String TAG_PREFIX = "live_updates/";
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
  @Nullable private static RouteListener routeListener;
  @Nullable private static EventListener eventListener;
  private static final Set<String> known = new LinkedHashSet<>();
  @Nullable static ResultListener permissionListener;
  private static final List<String> pendingRoutes = new ArrayList<>();
  @Nullable private static volatile ActionListener actionListener;
  private static final Object actionLock = new Object();
  private static int attachedEngines = 0;

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

  /** Whether this device shows Live Updates (Android 16+ promoted notifications). */
  public static boolean canPostPromotedNotifications() {
    Context c = context;
    if (c == null || Build.VERSION.SDK_INT < 36) return false;
    return manager(c).canPostPromotedNotifications();
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
    permissionListener = listener;
    a.runOnUiThread(
        () ->
            a.requestPermissions(
                new String[] {Manifest.permission.POST_NOTIFICATIONS}, PERMISSION_REQUEST_CODE));
  }

  /** Posts a new live update and returns its id. */
  @NonNull
  public static String start(@NonNull String json) throws JSONException {
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
    // A key the user dismissed stays hidden until the app ends it.
    if (!isDismissed(requireContext(), key)) post(key, new JSONObject(json), false, true);
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
   * Calls {@code listener} with button presses. Presses made while no Dart
   * listener was attached (including while the app was not running) are
   * persisted and delivered first, in order.
   */
  public static void observeActions(@NonNull ActionListener listener) {
    synchronized (actionLock) {
      Context c = context;
      if (c != null) {
        for (String[] a : takePendingActions(c)) listener.onAction(a[0], a[1]);
      }
      actionListener = listener;
    }
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
      if (listener != null) {
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
      for (String[] a : takePendingActions(c)) out.add(a[0] + "\n" + a[1]);
    }
    return out.toArray(new String[0]);
  }

  /** Called by the background engine when the handler finished. */
  public static void backgroundActionsDone() {
    LiveUpdatesBackgroundRunner.finish();
  }

  private static List<String[]> takePendingActions(Context c) {
    SharedPreferences prefs = prefs(c);
    org.json.JSONArray pending = readArray(prefs, PREF_PENDING_ACTIONS);
    prefs.edit().remove(PREF_PENDING_ACTIONS).apply();
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
    synchronized (actionLock) {
      attachedEngines++;
    }
  }

  static void engineDetached() {
    synchronized (actionLock) {
      attachedEngines = Math.max(0, attachedEngines - 1);
      if (attachedEngines == 0) {
        // The listeners belong to isolates that are gone: queue from now on.
        actionListener = null;
        routeListener = null;
        eventListener = null;
      }
    }
  }

  /** At most this many dismissed ids are remembered (oldest are dropped). */
  private static final int MAX_DISMISSED = 200;

  /** Records that the user swiped the update away (see DismissReceiver). */
  static void markDismissed(Context c, String id) {
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
    // When notifications are blocked nothing is ever shown; posting is a
    // harmless no-op then, matching start().
    if (!isShown(id) && manager(c).areNotificationsEnabled()) {
      throw new IllegalStateException("Unknown live update " + id);
    }
    post(id, new JSONObject(json));
  }

  private static boolean isShown(String id) {
    return java.util.Arrays.asList(activeIds()).contains(id);
  }

  /** Removes the live update {@code id}, optionally showing final content for a while. */
  public static void end(@NonNull String id, @Nullable String json, double dismissAfterSeconds)
      throws JSONException {
    Context c = requireContext();
    synchronized (recentlyPosted) {
      recentlyPosted.remove(id);
      recentlyEnded.put(id, SystemClock.uptimeMillis());
    }
    emit("ended", id);
    synchronized (keyedIds) {
      keyedIds.remove(id);
    }
    clearDismissed(c, id);
    if (json != null && dismissAfterSeconds != 0) {
      JSONObject content = new JSONObject(json);
      Notification.Builder builder = builder(c, content).setOngoing(false).setAutoCancel(true);
      if (dismissAfterSeconds > 0 && Build.VERSION.SDK_INT >= 26)
        builder.setTimeoutAfter((long) (dismissAfterSeconds * 1000));
      requestPromotedOngoing(builder, false);
      manager(c).notify(TAG_PREFIX + id, NOTIFICATION_ID, builder.build());
    } else {
      manager(c).cancel(TAG_PREFIX + id, NOTIFICATION_ID);
    }
  }

  /** Directory where Dart stores images referenced by {@code "image"}. */
  @Nullable
  public static String imageDirectory() {
    Context c = context;
    return c == null ? null : imageDir(c).getPath();
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
        if ((n.getNotification().flags & Notification.FLAG_ONGOING_EVENT) != 0) {
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
        clearDismissed(requireContext(), id);
        post(id, new JSONObject(content), true);
        return true;
      case "update":
        if (content == null) return false;
        // Do not bring back an update that ended or that the user dismissed.
        if (!isDismissed(requireContext(), id) && isShown(id)) {
          post(id, new JSONObject(content), true);
        }
        return true;
      case "end":
        end(id, content, data.optDouble("live_updates_dismiss_after", 0));
        return true;
      default:
        return false;
    }
  }

  /**
   * Calls {@code listener} with lifecycle events: {@code started} (new live
   * update, local or remote), {@code ended} (ended by the app or a payload)
   * and {@code dismissed} (swiped away by the user).
   */
  public static void observeEvents(@NonNull EventListener listener) {
    eventListener = listener;
  }

  /** Removes every live update of this app. */
  public static void endAll() throws JSONException {
    for (String id : activeIds()) end(id, null, 0);
  }

  static void emit(String event, String id) {
    if (event.equals("ended") || event.equals("dismissed")) {
      synchronized (known) {
        known.remove(id);
      }
    }
    EventListener listener = eventListener;
    if (listener != null) listener.onEvent(event + ":" + id);
  }

  /** Calls {@code listener} with every tap route, including one that launched the app. */
  public static void observeTaps(@NonNull RouteListener listener) {
    routeListener = listener;
    List<String> pending = new ArrayList<>(pendingRoutes);
    pendingRoutes.clear();
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
    // Open-app presses: the app is coming to the foreground, so its onAction
    // listener handles them (no background engine).
    if (actionId != null && updateId != null) emitAction(c, updateId, actionId, null, false);
    if (route == null) return;
    RouteListener listener = routeListener;
    if (listener != null) {
      listener.onRoute(route);
    } else {
      pendingRoutes.add(route);
    }
  }

  private static void post(String id, JSONObject content) {
    post(id, content, false, false);
  }

  private static void post(String id, JSONObject content, boolean remote) {
    post(id, content, remote, remote);
  }

  /** {@code keyed}: the id is a key (startOrUpdate, remote payloads). */
  private static void post(String id, JSONObject content, boolean remote, boolean keyed) {
    Context c = requireContext();
    // Survives process restarts: a notification already shown is not new.
    boolean wasShown = isShown(id);
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
    Notification.Builder b = builder(c, content, remote);
    if (content.optBoolean("androidAlert", false) && !mayAlert(id)) b.setOnlyAlertOnce(true);
    b.setDeleteIntent(LiveUpdatesDismissReceiver.intent(c, id));
    // update() keeps the marker of the shown notification.
    if (keyed || keyForId(id) != null) {
      android.os.Bundle extras = new android.os.Bundle();
      extras.putBoolean(EXTRA_KEYED, true);
      b.addExtras(extras);
    }
    addActions(c, b, id, content);
    manager(c).notify(TAG_PREFIX + id, NOTIFICATION_ID, b.build());
  }

  private static final String DEFAULT_CHANNEL = "live_updates";

  private static Notification.Builder builder(Context c, JSONObject content) {
    return builder(c, content, false);
  }

  /**
   * Remote payloads may only use the default channel or channels that already
   * exist, so a server cannot create arbitrary channels on the device.
   */
  private static Notification.Builder builder(Context c, JSONObject content, boolean remote) {
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
        .setOnlyAlertOnce(!content.optBoolean("androidAlert", false))
        .setSmallIcon(smallIcon(c, optString(content, "iconName")));
    String body = optString(content, "body");
    if (body != null) {
      b.setContentText(
          LiveUpdatesApi37.styledText(
              body, LiveUpdatesApi37.semanticStyle(optString(content, "bodySemanticStyle"))));
    }
    // Steps, journey and (where MetricStyle is not used) metrics as text: the
    // body line when there is no body, else the sub text.
    String mode = androidMode(content);
    boolean metricStyle =
        LiveUpdatesApi37.available()
            && !"classic".equals(mode)
            && content.optJSONArray("metrics") != null
            && content.optJSONArray("metrics").length() > 0;
    String detail = detailText(content, !metricStyle);
    if (detail != null) {
      if (body == null) b.setContentText(detail);
      else b.setSubText(detail);
    }
    String image = optString(content, "image");
    if (image != null && !image.contains("/")) {
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
    if (countdown || isTime(timerStart)) {
      b.setWhen((long) ((countdown ? timerEnd : timerStart) * 1000))
          .setShowWhen(true)
          .setUsesChronometer(true)
          .setChronometerCountDown(countdown);
    }
    long timeout = content.optLong("timeoutAfterMillis", 0);
    if (timeout > 0 && Build.VERSION.SDK_INT >= 26) {
      // Not shorter than a minute, so a payload cannot make an update vanish at once.
      b.setTimeoutAfter(Math.max(timeout, MIN_TIMEOUT_MS));
    }

    String route = optString(content, "route");
    PendingIntent tap = tapIntent(c, route);
    if (tap != null) b.setContentIntent(tap);

    boolean hasProgress = content.has("progress") && !content.isNull("progress");
    int progress = hasProgress ? (int) Math.round(content.optDouble("progress") * 100) : 0;
    JSONObject steps = content.optJSONObject("steps");
    int stepCount = steps == null ? 0 : stepLabels(steps).size();
    int currentStep =
        stepCount == 0 ? 0 : Math.max(0, Math.min(steps.optInt("current", 0), stepCount - 1));
    if (Build.VERSION.SDK_INT >= 36 && !"classic".equals(mode)) {
      requestPromotedOngoing(b, "liveUpdate".equals(mode));
      String chip = optString(content, "shortCriticalText");
      if (chip != null) b.setShortCriticalText(chip);
      boolean metrics =
          LiveUpdatesApi37.setMetricStyle(
              b, content.optJSONArray("metrics"), content.optInt("criticalMetric", -1));
      if (!metrics && (hasProgress || stepCount >= 2)) {
        double fraction =
            hasProgress
                ? content.optDouble("progress")
                : (double) currentStep / (stepCount - 1);
        b.setStyle(progressStyle(c, content, fraction));
      }
    } else if (hasProgress) {
      b.setProgress(100, progress, false);
    } else if (stepCount >= 2) {
      b.setProgress(stepCount - 1, currentStep, false);
    }
    return b;
  }

  private static List<String> stepLabels(JSONObject steps) {
    List<String> labels = new ArrayList<>();
    org.json.JSONArray a = steps.optJSONArray("labels");
    for (int i = 0; a != null && i < a.length() && labels.size() < MAX_PROGRESS_PARTS; i++) {
      labels.add(a.optString(i));
    }
    return labels;
  }

  private static final int MAX_DETAIL_TEXT = 80;

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
    if (journey != null && journey.has("from") && journey.has("to")) {
      parts.add(clip(journey.optString("from")) + " → " + clip(journey.optString("to")));
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
    return String.join(" · ", parts);
  }

  private static String clip(String text) {
    return text.length() <= MAX_DETAIL_TEXT ? text : text.substring(0, MAX_DETAIL_TEXT);
  }

  /**
   * {@code liveUpdate} (default), {@code ongoing} or {@code classic}. Payloads
   * from before {@code androidMode} existed may send {@code requestPromotion:
   * false}, which means {@code ongoing}.
   */
  private static String androidMode(JSONObject content) {
    String mode = optString(content, "androidMode");
    if ("ongoing".equals(mode) || "classic".equals(mode)) return mode;
    if (mode == null && !content.optBoolean("requestPromotion", true)) return "ongoing";
    return "liveUpdate";
  }

  /** At most one requested alert per update in this interval (remote payloads included). */
  private static final long MIN_ALERT_INTERVAL_MS = 10_000;

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
    if (total == 0 && stepCount >= 2 && content.optJSONArray("progressPoints") == null) {
      // One segment between each pair of stages and a point at each stage
      // after the first (the system ignores a point at the start).
      total = stepCount - 1;
      for (int i = 0; i < total; i++) style.addProgressSegment(new Notification.ProgressStyle.Segment(1));
      for (int i = 1; i < stepCount; i++) style.addProgressPoint(new Notification.ProgressStyle.Point(i));
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
    String tracker = optString(content, "progressTrackerIcon");
    Icon trackerIcon = tracker == null ? null : drawable(c, tracker);
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
      String iconName = optString(a, "androidIcon");
      Notification.Action.Builder action =
          new Notification.Action.Builder(smallIcon(c, iconName), a.optString("title"), pi);
      if (a.optBoolean("requiresUnlock", false) && Build.VERSION.SDK_INT >= 31) {
        action.setAuthenticationRequired(true);
      }
      b.addAction(action.build());
    }
  }

  /**
   * Same as {@code Notification.Builder#setRequestPromotedOngoing}, which is
   * not in the API 36 stubs; the extra is honored from Android 16 on.
   */
  private static void requestPromotedOngoing(Notification.Builder b, boolean value) {
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
  static Uri intentUri(String kind, String a, String b) {
    return new Uri.Builder()
        .scheme("liveupdates")
        .authority(kind)
        .appendQueryParameter("a", a)
        .appendQueryParameter("b", b)
        .build();
  }

  private static Icon smallIcon(Context c, @Nullable String name) {
    Icon icon = name == null ? null : drawable(c, name);
    return icon != null ? icon : Icon.createWithResource(c, c.getApplicationInfo().icon);
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
