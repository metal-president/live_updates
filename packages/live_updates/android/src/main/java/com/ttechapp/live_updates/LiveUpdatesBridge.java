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
 * showChronometer, requestPromotion}. On Android 16+ progress uses {@link
 * Notification.ProgressStyle} and promotion to a Live Update is requested
 * (shown on builds that support promoted notifications, Android 16 QPR1 and
 * later); older versions get a regular ongoing notification with a progress
 * bar.
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
  private static final String PREF_DISMISSED = "dismissed";

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
    post(id, new JSONObject(json));
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
    if (!isDismissed(requireContext(), key)) post(key, new JSONObject(json));
    return key;
  }

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
    synchronized (actionLock) {
      ActionListener listener = actionListener;
      if (listener != null) {
        listener.onAction(updateId, actionId);
        return;
      }
      SharedPreferences prefs = prefs(c);
      org.json.JSONArray pending = readArray(prefs, PREF_PENDING_ACTIONS);
      pending.put(new org.json.JSONArray().put(updateId).put(actionId));
      prefs.edit().putString(PREF_PENDING_ACTIONS, pending.toString()).apply();
    }
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

  /** Records that the user swiped the update away (see DismissReceiver). */
  static void markDismissed(Context c, String id) {
    SharedPreferences prefs = prefs(c);
    Set<String> ids = new java.util.HashSet<>(prefs.getStringSet(PREF_DISMISSED, new java.util.HashSet<>()));
    ids.add(id);
    prefs.edit().putStringSet(PREF_DISMISSED, ids).apply();
  }

  private static void clearDismissed(Context c, String id) {
    SharedPreferences prefs = prefs(c);
    Set<String> stored = prefs.getStringSet(PREF_DISMISSED, null);
    if (stored == null || !stored.contains(id)) return;
    Set<String> ids = new java.util.HashSet<>(stored);
    ids.remove(id);
    prefs.edit().putStringSet(PREF_DISMISSED, ids).apply();
  }

  private static boolean isDismissed(Context c, String id) {
    Set<String> stored = prefs(c).getStringSet(PREF_DISMISSED, null);
    return stored != null && stored.contains(id);
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
        post(id, new JSONObject(content));
        return true;
      case "update":
        if (content == null) return false;
        // Do not bring back an update that ended or that the user dismissed.
        if (!isDismissed(requireContext(), id) && isShown(id)) {
          post(id, new JSONObject(content));
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
    if (intent == null) return;
    String actionId = intent.getStringExtra(EXTRA_ACTION_ID);
    String updateId = intent.getStringExtra(EXTRA_UPDATE_ID);
    if (actionId != null && updateId != null) {
      intent.removeExtra(EXTRA_ACTION_ID);
      intent.removeExtra(EXTRA_UPDATE_ID);
      Context c = context;
      if (c != null) emitAction(c, updateId, actionId);
    }
    String route = intent.getStringExtra(EXTRA_ROUTE);
    if (route == null) return;
    intent.removeExtra(EXTRA_ROUTE);
    RouteListener listener = routeListener;
    if (listener != null) {
      listener.onRoute(route);
    } else {
      pendingRoutes.add(route);
    }
  }

  private static void post(String id, JSONObject content) {
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
    if (isNew) emit("started", id);
    Notification.Builder b = builder(c, content);
    b.setDeleteIntent(LiveUpdatesDismissReceiver.intent(c, id));
    addActions(c, b, id, content);
    manager(c).notify(TAG_PREFIX + id, NOTIFICATION_ID, b.build());
  }

  private static Notification.Builder builder(Context c, JSONObject content) {
    Notification.Builder b;
    if (Build.VERSION.SDK_INT >= 26) {
      String channelId = content.optString("channelId", "live_updates");
      NotificationManager manager = manager(c);
      if (manager.getNotificationChannel(channelId) == null) {
        manager.createNotificationChannel(
            new NotificationChannel(
                channelId,
                content.optString("channelName", "Live updates"),
                NotificationManager.IMPORTANCE_DEFAULT));
      }
      b = new Notification.Builder(c, channelId);
    } else {
      b = new Notification.Builder(c);
    }
    b.setContentTitle(content.optString("title"))
        .setOngoing(true)
        .setOnlyAlertOnce(true)
        .setSmallIcon(smallIcon(c, optString(content, "iconName")));
    String body = optString(content, "body");
    if (body != null) b.setContentText(body);
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

    String route = optString(content, "route");
    PendingIntent tap = tapIntent(c, route);
    if (tap != null) b.setContentIntent(tap);

    boolean hasProgress = content.has("progress") && !content.isNull("progress");
    int progress = hasProgress ? (int) Math.round(content.optDouble("progress") * 100) : 0;
    if (Build.VERSION.SDK_INT >= 36) {
      requestPromotedOngoing(b, content.optBoolean("requestPromotion", true));
      String chip = optString(content, "shortCriticalText");
      if (chip != null) b.setShortCriticalText(chip);
      if (hasProgress) {
        b.setStyle(new Notification.ProgressStyle().setProgress(progress));
      }
    } else if (hasProgress) {
      b.setProgress(100, progress, false);
    }
    return b;
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
        launch.putExtra(EXTRA_UPDATE_ID, id).putExtra(EXTRA_ACTION_ID, actionId);
        launch.setData(intentUri("action", id, actionId));
        pi =
            PendingIntent.getActivity(
                c, 0, launch, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
      } else {
        pi = LiveUpdatesActionReceiver.intent(c, id, actionId);
      }
      String iconName = optString(a, "androidIcon");
      b.addAction(
          new Notification.Action.Builder(smallIcon(c, iconName), a.optString("title"), pi)
              .build());
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
      launch.putExtra(EXTRA_ROUTE, route);
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
    if (name != null) {
      int res = c.getResources().getIdentifier(name, "drawable", c.getPackageName());
      if (res == 0) res = c.getResources().getIdentifier(name, "mipmap", c.getPackageName());
      if (res != 0) return Icon.createWithResource(c, res);
    }
    return Icon.createWithResource(c, c.getApplicationInfo().icon);
  }

  @Nullable
  private static String optString(JSONObject o, String key) {
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
