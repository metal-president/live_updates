package com.ttechapp.live_updates;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;
import static org.robolectric.Shadows.shadowOf;

import android.app.Application;
import android.app.Notification;
import android.app.NotificationManager;
import android.content.Context;
import android.content.Intent;
import android.service.notification.StatusBarNotification;
import org.robolectric.RuntimeEnvironment;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import org.json.JSONObject;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 36)
public class LiveUpdatesBridgeTest {
  private final Application app = RuntimeEnvironment.getApplication();
  private NotificationManager manager;

  @Before
  public void setUp() {
    app.getApplicationInfo().icon = android.R.drawable.ic_dialog_info;
    // A launcher activity, so tap and open-app intents can be built.
    android.content.pm.ResolveInfo info = new android.content.pm.ResolveInfo();
    info.activityInfo = new android.content.pm.ActivityInfo();
    info.activityInfo.packageName = app.getPackageName();
    info.activityInfo.name = "MainActivity";
    shadowOf(app.getPackageManager())
        .addResolveInfoForIntent(
            new Intent(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_LAUNCHER)
                .setPackage(app.getPackageName()),
            info);
    manager = (NotificationManager) app.getSystemService(Context.NOTIFICATION_SERVICE);
    LiveUpdatesBridge.engineAttached(app);
  }

  @After
  public void tearDown() {
    LiveUpdatesBridge.engineDetached();
  }

  private static boolean remote(String event, String id, String content) throws Exception {
    JSONObject data =
        new JSONObject().put("live_updates_event", event).put("live_updates_id", id);
    if (content != null) data.put("live_updates_content", content);
    return LiveUpdatesBridge.handleRemotePayload(data.toString());
  }

  private Notification shown(String id) {
    for (StatusBarNotification n : manager.getActiveNotifications()) {
      if ((LiveUpdatesBridge.TAG_PREFIX + id).equals(n.getTag())) return n.getNotification();
    }
    return null;
  }

  @Test
  public void remotePayloadStartsUpdatesAndEnds() throws Exception {
    assertTrue(remote("start", "r1", "{\"title\":\"Order\",\"progress\":0.1}"));
    Notification n = shown("r1");
    assertNotNull(n);
    assertEquals("Order", n.extras.getString(Notification.EXTRA_TITLE));
    assertTrue(Arrays.asList(LiveUpdatesBridge.activeIds()).contains("r1"));

    assertTrue(remote("update", "r1", "{\"title\":\"Order\",\"body\":\"On the way\"}"));
    assertEquals("On the way", shown("r1").extras.getCharSequence(Notification.EXTRA_TEXT).toString());

    assertTrue(remote("end", "r1", null));
    assertEquals(null, shown("r1"));
    // An update for an ended update does not bring it back.
    assertTrue(remote("update", "r1", "{\"title\":\"Again\"}"));
    assertEquals(null, shown("r1"));
  }

  @Test
  public void dismissedUpdatesStayDismissedUntilRestarted() throws Exception {
    remote("start", "r2", "{\"title\":\"A\"}");
    manager.cancel(LiveUpdatesBridge.TAG_PREFIX + "r2", LiveUpdatesBridge.NOTIFICATION_ID);
    LiveUpdatesBridge.markDismissed(app, "r2");
    remote("update", "r2", "{\"title\":\"B\"}");
    assertEquals(null, shown("r2"));
    remote("start", "r2", "{\"title\":\"C\"}");
    assertEquals("C", shown("r2").extras.getString(Notification.EXTRA_TITLE));
  }

  @Test
  public void notLiveUpdatesPayloadsAreIgnored() throws Exception {
    assertFalse(LiveUpdatesBridge.handleRemotePayload("{\"other\":\"x\"}"));
    assertFalse(remote("start", "r3", null));
    assertFalse(remote("explode", "r3", "{\"title\":\"x\"}"));
  }

  @Test
  public void remotePayloadsCannotCreateChannels() throws Exception {
    remote("start", "r4", "{\"title\":\"A\",\"channelId\":\"evil\",\"channelName\":\"Evil\"}");
    assertEquals("live_updates", shown("r4").getChannelId());
    assertEquals(null, manager.getNotificationChannel("evil"));
  }

  @Test
  public void localStartCreatesRequestedChannel() throws Exception {
    String id =
        LiveUpdatesBridge.start("{\"title\":\"A\",\"channelId\":\"rides\",\"channelName\":\"Rides\"}");
    assertEquals("rides", shown(id).getChannelId());
    assertEquals("Rides", manager.getNotificationChannel("rides").getName().toString());
  }

  @Test
  public void startOrUpdateReusesTheKey() throws Exception {
    String a = LiveUpdatesBridge.startOrUpdate("order-9", "{\"title\":\"A\"}");
    String b = LiveUpdatesBridge.startOrUpdate("order-9", "{\"title\":\"B\"}");
    assertEquals(a, b);
    assertEquals("B", shown(a).extras.getString(Notification.EXTRA_TITLE));
  }

  @Test
  public void tapRoutesNeedTheIntentToken() throws Exception {
    String id = LiveUpdatesBridge.start("{\"title\":\"A\",\"route\":\"/orders/1\"}");
    Intent tap = shadowOf(shown(id).contentIntent).getSavedIntent();
    List<String> routes = new ArrayList<>();
    LiveUpdatesBridge.observeTaps(routes::add);

    Intent forged = new Intent().putExtra(LiveUpdatesBridge.EXTRA_ROUTE, "/evil");
    LiveUpdatesBridge.handleIntent(forged);
    Intent wrongToken =
        new Intent()
            .putExtra(LiveUpdatesBridge.EXTRA_ROUTE, "/evil")
            .putExtra(LiveUpdatesBridge.EXTRA_TOKEN, "guess");
    LiveUpdatesBridge.handleIntent(wrongToken);
    assertTrue(routes.isEmpty());

    LiveUpdatesBridge.handleIntent(new Intent(tap));
    assertEquals(Arrays.asList("/orders/1"), routes);
  }

  @Test
  public void pressesAreQueuedUntilSomeoneListens() {
    LiveUpdatesBridge.emitAction(app, "u1", "cancel");
    LiveUpdatesBridge.emitAction(app, "u1", "details");
    List<String> got = new ArrayList<>();
    LiveUpdatesBridge.observeActions((update, action) -> got.add(update + ":" + action));
    assertEquals(Arrays.asList("u1:cancel", "u1:details"), got);
    LiveUpdatesBridge.emitAction(app, "u2", "cancel");
    assertEquals("u2:cancel", got.get(2));
  }

  @Test
  public void actionButtonsAreAddedWithUnlockRequirement() throws Exception {
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"A\",\"actions\":[{\"id\":\"cancel\",\"title\":\"Cancel\","
                + "\"requiresUnlock\":true},{\"id\":\"track\",\"title\":\"Track\",\"opensApp\":true}]}");
    Notification.Action[] actions = shown(id).actions;
    assertEquals(2, actions.length);
    assertEquals("Cancel", actions[0].title.toString());
    assertTrue(actions[0].isAuthenticationRequired());
    assertFalse(actions[1].isAuthenticationRequired());
  }

  @Test
  public void progressUsesProgressStyleOnAndroid16() throws Exception {
    String id = LiveUpdatesBridge.start("{\"title\":\"A\",\"progress\":0.5,\"metrics\":[{\"label\":\"x\",\"type\":\"integer\",\"value\":1}]}");
    assertEquals(
        "android.app.Notification$ProgressStyle",
        shown(id).extras.getString(Notification.EXTRA_TEMPLATE));
  }

  @Test
  public void countdownTimerUsesTheChronometer() throws Exception {
    long end = System.currentTimeMillis() + 600_000;
    String id = LiveUpdatesBridge.start("{\"title\":\"A\",\"timerEnd\":" + (end / 1000.0) + "}");
    Notification n = shown(id);
    assertEquals(end, n.when, 1);
    assertTrue(n.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER));
    assertTrue(n.extras.getBoolean(Notification.EXTRA_CHRONOMETER_COUNT_DOWN));
  }

  @Test
  public void stopwatchCountsUp() throws Exception {
    long start = System.currentTimeMillis() - 60_000;
    String id = LiveUpdatesBridge.start("{\"title\":\"A\",\"timerStart\":" + (start / 1000.0) + "}");
    Notification n = shown(id);
    assertEquals(start, n.when, 1);
    assertTrue(n.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER));
    assertFalse(n.extras.getBoolean(Notification.EXTRA_CHRONOMETER_COUNT_DOWN));
  }

  @Test
  public void invalidTimersAreIgnored() throws Exception {
    String id = LiveUpdatesBridge.start("{\"title\":\"A\",\"timerEnd\":\"soon\"}");
    assertFalse(shown(id).extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER));
  }

  @Test
  public void timeoutAndAlert() throws Exception {
    String id =
        LiveUpdatesBridge.start("{\"title\":\"A\",\"timeoutAfterMillis\":3600000}");
    Notification n = shown(id);
    assertEquals(3_600_000, n.getTimeoutAfter());
    assertTrue((n.flags & Notification.FLAG_ONLY_ALERT_ONCE) != 0);
    LiveUpdatesBridge.update(id, "{\"title\":\"B\",\"androidAlert\":true}");
    assertEquals(0, shown(id).flags & Notification.FLAG_ONLY_ALERT_ONCE);
  }

  @Test
  public void progressSegmentsAndPoints() throws Exception {
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"A\",\"progress\":0.5,"
                + "\"progressSegments\":[{\"length\":1,\"colorArgb\":4294901760},{\"length\":3},\"bad\",{\"length\":-5}],"
                + "\"progressPoints\":[{\"position\":0.25},{\"position\":7},{\"position\":\"x\"}]}");
    Notification n = shown(id);
    Notification.ProgressStyle style =
        (Notification.ProgressStyle) Notification.Builder.recoverBuilder(app, n).getStyle();
    // Lengths 1 + 3 + 1 (the negative one is clamped to 1); "bad" is skipped.
    assertEquals(3, style.getProgressSegments().size());
    assertEquals(0xFFFF0000, style.getProgressSegments().get(0).getColor());
    assertEquals(5, style.getProgressMax());
    assertEquals(3, style.getProgress()); // round(0.5 * 5)
    assertEquals(2, style.getProgressPoints().size());
    assertEquals(1, style.getProgressPoints().get(0).getPosition()); // round(0.25 * 5)
    assertEquals(5, style.getProgressPoints().get(1).getPosition()); // clamped to the end
  }
}
