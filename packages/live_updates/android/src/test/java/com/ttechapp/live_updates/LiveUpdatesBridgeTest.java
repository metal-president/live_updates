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
    LiveUpdatesBridge.engineDetached(1);
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
    LiveUpdatesBridge.observeTaps(routes::add, 1);

    Intent forged = new Intent().putExtra(LiveUpdatesBridge.EXTRA_ROUTE, "/evil");
    LiveUpdatesBridge.handleIntent(forged);
    Intent wrongToken =
        new Intent()
            .putExtra(LiveUpdatesBridge.EXTRA_ROUTE, "/evil")
            .putExtra(LiveUpdatesBridge.EXTRA_TOKEN, "guess");
    LiveUpdatesBridge.handleIntent(wrongToken);
    assertTrue(routes.isEmpty());

    Intent launch = new Intent(tap);
    LiveUpdatesBridge.handleIntent(launch);
    assertEquals(Arrays.asList("/orders/1"), routes);
    // The internal data URI must not reach Flutter as a deep link.
    assertEquals(null, launch.getData());
  }

  @Test
  public void listenersOfADetachedEngineAreDropped() {
    List<String> got = new ArrayList<>();
    LiveUpdatesBridge.observeActions((update, action) -> got.add(update + ":" + action), 1);
    LiveUpdatesBridge.engineDetached(2); // another engine: still listening
    LiveUpdatesBridge.emitAction(app, "u1", "a");
    assertEquals(Arrays.asList("u1:a"), got);
    LiveUpdatesBridge.engineDetached(1);
    LiveUpdatesBridge.emitAction(app, "u1", "b");
    assertEquals(1, got.size());
    assertEquals(Arrays.asList("u1\nb"), Arrays.asList(LiveUpdatesBridge.takeQueuedActions()));
  }

  @Test
  public void unobservedPressesAreQueuedAgain() {
    List<String> got = new ArrayList<>();
    LiveUpdatesBridge.observeActions((update, action) -> got.add(update + ":" + action), 1);
    LiveUpdatesBridge.unobserveActions(1, new String[] {"u3\nlater"});
    LiveUpdatesBridge.emitAction(app, "u3", "next");
    assertTrue(got.isEmpty());
    assertEquals(
        Arrays.asList("u3\nlater", "u3\nnext"),
        Arrays.asList(LiveUpdatesBridge.takeQueuedActions()));
  }

  @Test
  public void remoteEndDoesNotBringBackADismissedUpdate() throws Exception {
    remote("start", "r5", "{\"title\":\"A\"}");
    manager.cancel(LiveUpdatesBridge.TAG_PREFIX + "r5", LiveUpdatesBridge.NOTIFICATION_ID);
    LiveUpdatesBridge.markDismissed(app, "r5");
    remote("end", "r5", "{\"title\":\"Delivered\",\"channelId\":\"promo\"}");
    assertEquals(null, shown("r5"));
    assertEquals(null, manager.getNotificationChannel("promo"));
  }

  @Test
  public void remoteEndKeepsFinalContentWithoutDismissTime() throws Exception {
    remote("start", "r6", "{\"title\":\"A\"}");
    remote("end", "r6", "{\"title\":\"Delivered\"}");
    assertEquals("Delivered", shown("r6").extras.getString(Notification.EXTRA_TITLE));
  }

  @Test
  public void timeoutIsNotADismissal() throws Exception {
    LiveUpdatesBridge.startOrUpdate("order-t", "{\"title\":\"A\",\"timeoutAfterMillis\":60000}");
    Intent delete = shadowOf(shown("order-t").deleteIntent).getSavedIntent();
    long deadline = delete.getLongExtra("com.ttechapp.live_updates.DEADLINE", 0);
    assertTrue(deadline > System.currentTimeMillis());
    // As if the system removed it at the deadline.
    manager.cancel(LiveUpdatesBridge.TAG_PREFIX + "order-t", LiveUpdatesBridge.NOTIFICATION_ID);
    delete.putExtra("com.ttechapp.live_updates.DEADLINE", System.currentTimeMillis());
    new LiveUpdatesDismissReceiver().onReceive(app, delete);
    LiveUpdatesBridge.startOrUpdate("order-t", "{\"title\":\"B\"}");
    assertEquals("B", shown("order-t").extras.getString(Notification.EXTRA_TITLE));
  }

  @Test
  public void swipeIsADismissal() throws Exception {
    LiveUpdatesBridge.startOrUpdate("order-s", "{\"title\":\"A\",\"timeoutAfterMillis\":600000}");
    Intent delete = shadowOf(shown("order-s").deleteIntent).getSavedIntent();
    manager.cancel(LiveUpdatesBridge.TAG_PREFIX + "order-s", LiveUpdatesBridge.NOTIFICATION_ID);
    new LiveUpdatesDismissReceiver().onReceive(app, delete);
    LiveUpdatesBridge.startOrUpdate("order-s", "{\"title\":\"B\"}");
    assertEquals(null, shown("order-s"));
  }

  @Test
  public void pressesAreQueuedUntilSomeoneListens() {
    LiveUpdatesBridge.emitAction(app, "u1", "cancel");
    LiveUpdatesBridge.emitAction(app, "u1", "details");
    List<String> got = new ArrayList<>();
    LiveUpdatesBridge.observeActions((update, action) -> got.add(update + ":" + action), 1);
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
    // A second alert within 10 seconds is muted.
    LiveUpdatesBridge.update(id, "{\"title\":\"C\",\"androidAlert\":true}");
    assertTrue((shown(id).flags & Notification.FLAG_ONLY_ALERT_ONCE) != 0);
  }

  @Test
  public void shortTimeoutsAndQualifiedIconNamesAreRejected() throws Exception {
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"A\",\"timeoutAfterMillis\":1,\"iconName\":\"android:drawable/ic_dialog_alert\"}");
    Notification n = shown(id);
    assertEquals(60_000, n.getTimeoutAfter());
    assertEquals(android.R.drawable.ic_dialog_info, n.getSmallIcon().getResId());
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

  @Test
  public void keysAreReportedForKeyedUpdatesOnly() throws Exception {
    String plain = LiveUpdatesBridge.start("{\"title\":\"A\"}");
    assertEquals(null, LiveUpdatesBridge.keyForId(plain));
    LiveUpdatesBridge.startOrUpdate("order-7", "{\"title\":\"B\"}");
    assertEquals("order-7", LiveUpdatesBridge.keyForId("order-7"));
    // update() keeps the key.
    LiveUpdatesBridge.update("order-7", "{\"title\":\"C\"}");
    assertEquals("order-7", LiveUpdatesBridge.keyForId("order-7"));
    remote("start", "remote-8", "{\"title\":\"D\"}");
    assertEquals("remote-8", LiveUpdatesBridge.keyForId("remote-8"));
    assertEquals(null, LiveUpdatesBridge.keyForId("missing"));
  }

  @Test
  public void classicModeUsesThePlainProgressBar() throws Exception {
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"A\",\"progress\":0.5,\"androidMode\":\"classic\","
                + "\"progressSegments\":[{\"length\":1}]}");
    Notification n = shown(id);
    assertEquals(null, n.extras.getString(Notification.EXTRA_TEMPLATE));
    assertEquals(100, n.extras.getInt(Notification.EXTRA_PROGRESS_MAX));
    assertEquals(50, n.extras.getInt(Notification.EXTRA_PROGRESS));
    assertFalse(n.extras.getBoolean("android.requestPromotedOngoing"));
  }

  @Test
  public void modesControlPromotion() throws Exception {
    String live = LiveUpdatesBridge.start("{\"title\":\"A\",\"progress\":0.5}");
    assertTrue(shown(live).extras.getBoolean("android.requestPromotedOngoing"));
    String ongoing =
        LiveUpdatesBridge.start("{\"title\":\"A\",\"progress\":0.5,\"androidMode\":\"ongoing\"}");
    assertFalse(shown(ongoing).extras.getBoolean("android.requestPromotedOngoing"));
    assertEquals(
        "android.app.Notification$ProgressStyle",
        shown(ongoing).extras.getString(Notification.EXTRA_TEMPLATE));
    // Payloads from before androidMode existed.
    String old =
        LiveUpdatesBridge.start("{\"title\":\"A\",\"progress\":0.5,\"requestPromotion\":false}");
    assertFalse(shown(old).extras.getBoolean("android.requestPromotedOngoing"));
  }

  @Test
  public void stepsBecomeSegmentsPointsAndText() throws Exception {
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"Order\",\"steps\":{\"labels\":[\"Placed\",\"Preparing\",\"On the way\",\"Delivered\"],\"current\":1}}");
    Notification n = shown(id);
    Notification.ProgressStyle style =
        (Notification.ProgressStyle) Notification.Builder.recoverBuilder(app, n).getStyle();
    assertEquals(3, style.getProgressSegments().size());
    assertEquals(3, style.getProgressPoints().size());
    assertEquals(300, style.getProgressMax());
    assertEquals(100, style.getProgress());
    assertEquals("2/4 Preparing", n.extras.getCharSequence(Notification.EXTRA_TEXT).toString());
  }

  @Test
  public void journeyAndMetricsAreShownAsText() throws Exception {
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"Trip\",\"body\":\"On time\",\"journey\":{\"from\":\"A\",\"to\":\"B\"},"
                + "\"metrics\":[{\"label\":\"Home\",\"type\":\"integer\",\"value\":2},"
                + "{\"label\":\"Dist\",\"type\":\"decimal\",\"value\":4.25,\"unit\":\"km\"},"
                + "{\"label\":\"ETA\",\"type\":\"timer\",\"value\":1}]}");
    Notification n = shown(id);
    assertEquals("On time", n.extras.getCharSequence(Notification.EXTRA_TEXT).toString());
    assertEquals(
        "A \u2192 B \u00b7 Home: 2 \u00b7 Dist: 4.2 km",
        n.extras.getCharSequence(Notification.EXTRA_SUB_TEXT).toString());
  }

  @Test
  public void explicitProgressKeepsItsResolutionWithSteps() throws Exception {
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"Order\",\"progress\":0.6,\"steps\":{\"labels\":[\"A\",\"B\",\"C\",\"D\"],\"current\":1}}");
    Notification.ProgressStyle style =
        (Notification.ProgressStyle)
            Notification.Builder.recoverBuilder(app, shown(id)).getStyle();
    assertEquals(180, style.getProgress());
  }

  @Test
  public void manyStepsAreShownAsTextOnly() throws Exception {
    StringBuilder labels = new StringBuilder();
    for (int i = 1; i <= 25; i++) labels.append(i > 1 ? "," : "").append("\"S").append(i).append('"');
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"Long\",\"steps\":{\"labels\":[" + labels + "],\"current\":22}}");
    Notification n = shown(id);
    Notification.ProgressStyle style =
        (Notification.ProgressStyle) Notification.Builder.recoverBuilder(app, n).getStyle();
    assertEquals(0, style.getProgressPoints().size());
    assertEquals("23/25 S23", n.extras.getCharSequence(Notification.EXTRA_TEXT).toString());
  }

  @Test
  public void journeyWithANullEndIsLeftOut() throws Exception {
    String id =
        LiveUpdatesBridge.start("{\"title\":\"Trip\",\"journey\":{\"from\":null,\"to\":\"B\"}}");
    assertEquals(null, shown(id).extras.getCharSequence(Notification.EXTRA_TEXT));
  }
}
