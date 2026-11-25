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
    // Static state must not leak into the next test.
    LiveUpdatesBridge.engineDetached(1);
    LiveUpdatesBridge.engineDetached(2);
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
  public void visibilityIsPrivateWithoutPublicVersionByDefault() throws Exception {
    Notification n = shown(LiveUpdatesBridge.start("{\"title\":\"Order\"}"));
    assertEquals(Notification.VISIBILITY_PRIVATE, n.visibility);
    assertEquals(null, n.publicVersion);
  }

  @Test
  public void publicContentBecomesThePublicVersion() throws Exception {
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"Order #1234\",\"body\":\"Gate code 4321\",\"progress\":0.4,"
                + "\"timerEnd\":1893456000,\"colorArgb\":4278190335,\"channelId\":\"rides\","
                + "\"shortCriticalText\":\"4321\","
                + "\"metrics\":[{\"label\":\"ETA\",\"type\":\"integer\",\"value\":5}],"
                + "\"steps\":{\"labels\":[\"A\",\"B\"],\"current\":1},"
                + "\"journey\":{\"from\":\"A\",\"to\":\"B\"},"
                + "\"actions\":[{\"id\":\"call\",\"title\":\"Call\"}],"
                + "\"publicContent\":{\"title\":\"Delivery\",\"body\":\"On the way\","
                + "\"keepProgress\":true,\"keepTimer\":true}}");
    Notification n = shown(id);
    assertEquals(Notification.VISIBILITY_PRIVATE, n.visibility);
    assertEquals(1, n.actions.length);
    Notification p = n.publicVersion;
    assertNotNull(p);
    assertEquals("Delivery", p.extras.getString(Notification.EXTRA_TITLE));
    assertEquals("On the way", p.extras.getCharSequence(Notification.EXTRA_TEXT).toString());
    assertEquals(null, p.actions);
    assertEquals(null, p.extras.getCharSequence(Notification.EXTRA_SUB_TEXT));
    assertEquals("rides", p.getChannelId());
    assertEquals(0xFF0000FF, p.color);
    assertTrue((p.flags & Notification.FLAG_ONGOING_EVENT) != 0);
    assertEquals(1893456000000L, p.when);
    assertTrue(p.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER));
    // The progress is kept (ProgressStyle on Android 16), the stages are not.
    assertEquals(
        "android.app.Notification$ProgressStyle", p.extras.getString(Notification.EXTRA_TEMPLATE));
    Notification.ProgressStyle style =
        (Notification.ProgressStyle) Notification.Builder.recoverBuilder(app, p).getStyle();
    assertEquals(40, style.getProgress());
    assertEquals(100, style.getProgressMax());
    assertTrue(style.getProgressPoints().isEmpty());
    assertNotNull(p.contentIntent);
  }

  @Test
  public void publicContentCanDropProgressAndTimer() throws Exception {
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"Order\",\"progress\":0.4,\"timerStart\":1893456000,"
                + "\"whenEpochMillis\":1893456000000,\"showChronometer\":true,"
                + "\"publicContent\":{\"title\":\"Delivery\","
                + "\"keepProgress\":false,\"keepTimer\":false}}");
    Notification p = shown(id).publicVersion;
    assertEquals("Delivery", p.extras.getString(Notification.EXTRA_TITLE));
    assertEquals(null, p.extras.getCharSequence(Notification.EXTRA_TEXT));
    assertEquals(null, p.extras.getString(Notification.EXTRA_TEMPLATE));
    assertEquals(0, p.extras.getInt(Notification.EXTRA_PROGRESS_MAX));
    assertFalse(p.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER));
    // The system's post time, not the timer or `when` of the full content.
    assertTrue(p.when < 1893456000000L);
  }

  @Test
  public void keepFlagsThatAreNotBooleansDropProgressAndTimer() throws Exception {
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"Order\",\"progress\":0.4,\"timerStart\":1893456000,"
                + "\"showChronometer\":true,"
                + "\"publicContent\":{\"title\":\"Delivery\","
                + "\"keepProgress\":0,\"keepTimer\":\"false\"}}");
    Notification p = shown(id).publicVersion;
    assertEquals(0, p.extras.getInt(Notification.EXTRA_PROGRESS_MAX));
    assertFalse(p.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER));
  }

  @Test
  public void secretVisibilityHidesTheNotification() throws Exception {
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"Order\",\"androidLockScreenVisibility\":\"secret\","
                + "\"publicContent\":{\"title\":\"Delivery\"}}");
    Notification n = shown(id);
    assertEquals(Notification.VISIBILITY_SECRET, n.visibility);
    assertEquals(null, n.publicVersion);
  }

  @Test
  public void remotePayloadsUseThePublicContentKeys() throws Exception {
    remote(
        "start",
        "pub",
        "{\"title\":\"Order\",\"publicContent\":{\"title\":\"Delivery\"}}");
    assertEquals("Delivery", shown("pub").publicVersion.extras.getString(Notification.EXTRA_TITLE));
    remote("update", "pub", "{\"title\":\"Order\",\"androidLockScreenVisibility\":\"secret\"}");
    assertEquals(Notification.VISIBILITY_SECRET, shown("pub").visibility);
    // A publicContent without a title is ignored.
    remote("update", "pub", "{\"title\":\"Order\",\"publicContent\":{\"body\":\"x\"}}");
    assertEquals(Notification.VISIBILITY_PRIVATE, shown("pub").visibility);
    assertEquals(null, shown("pub").publicVersion);
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
    // The content shown last stays as an ended notification.
    assertEndedLook(shown("r1"), "Order");
    assertFalse(Arrays.asList(LiveUpdatesBridge.activeIds()).contains("r1"));
    // An update for an ended update does not bring it back.
    assertTrue(remote("update", "r1", "{\"title\":\"Again\"}"));
    assertEndedLook(shown("r1"), "Order");
  }

  private static final long HOUR = 60 * 60 * 1000L;

  private static void assertEndedLook(Notification n, String title) {
    assertNotNull(n);
    assertEquals(title, n.extras.getString(Notification.EXTRA_TITLE));
    assertFalse((n.flags & Notification.FLAG_ONGOING_EVENT) != 0);
    assertTrue((n.flags & Notification.FLAG_AUTO_CANCEL) != 0);
    assertFalse(n.extras.getBoolean("android.requestPromotedOngoing"));
    assertEquals(null, n.deleteIntent);
  }

  @Test
  public void endKeepsTheLastContentForFourHoursByDefault() throws Exception {
    String id =
        LiveUpdatesBridge.startOrUpdate(
            "order-k",
            "{\"title\":\"Order\",\"body\":\"On the way\",\"progress\":0.5,\"route\":\"/o\","
                + "\"actions\":[{\"id\":\"call\",\"title\":\"Call\"}],"
                + "\"publicContent\":{\"title\":\"Delivery\"}}");
    List<String> events = new ArrayList<>();
    LiveUpdatesBridge.observeEvents(events::add, 1);
    LiveUpdatesBridge.end(id, null, -1);
    Notification n = shown(id);
    assertEndedLook(n, "Order");
    assertEquals("On the way", n.extras.getCharSequence(Notification.EXTRA_TEXT).toString());
    assertEquals(null, n.actions);
    assertNotNull(n.contentIntent);
    assertEquals(4 * HOUR, n.getTimeoutAfter());
    assertEndedLook(n.publicVersion, "Delivery");
    assertEquals(null, LiveUpdatesBridge.keyForId(id));
    assertEquals(Arrays.asList("ended:" + id), events);
    assertFalse(Arrays.asList(LiveUpdatesBridge.activeIds()).contains(id));
    // The key starts a new update.
    LiveUpdatesBridge.startOrUpdate("order-k", "{\"title\":\"Again\"}");
    assertTrue((shown(id).flags & Notification.FLAG_ONGOING_EVENT) != 0);
  }

  @Test
  public void dismissAfterIsCappedAtFourHours() throws Exception {
    String a = LiveUpdatesBridge.start("{\"title\":\"A\"}");
    LiveUpdatesBridge.end(a, null, 60);
    assertEquals(60_000, shown(a).getTimeoutAfter());
    String b = LiveUpdatesBridge.start("{\"title\":\"B\"}");
    LiveUpdatesBridge.end(b, "{\"title\":\"Done\"}", 24 * 3600);
    assertEquals(4 * HOUR, shown(b).getTimeoutAfter());
    String c = LiveUpdatesBridge.start("{\"title\":\"C\"}");
    LiveUpdatesBridge.end(c, "{\"title\":\"Done\"}", -1);
    assertEquals(4 * HOUR, shown(c).getTimeoutAfter());
  }

  @Test
  public void dismissAfterZeroRemovesItAtOnce() throws Exception {
    String a = LiveUpdatesBridge.start("{\"title\":\"A\"}");
    LiveUpdatesBridge.end(a, null, 0);
    assertEquals(null, shown(a));
    String b = LiveUpdatesBridge.start("{\"title\":\"B\"}");
    LiveUpdatesBridge.end(b, "{\"title\":\"Done\"}", 0);
    assertEquals(null, shown(b));
    remote("start", "r9", "{\"title\":\"R\"}");
    JSONObject data =
        new JSONObject()
            .put("live_updates_event", "end")
            .put("live_updates_id", "r9")
            .put("live_updates_dismiss_after", 0);
    LiveUpdatesBridge.handleRemotePayload(data.toString());
    assertEquals(null, shown("r9"));
  }

  @Test
  public void endingAnEndedUpdateAgainLeavesItAsItIs() throws Exception {
    String a = LiveUpdatesBridge.start("{\"title\":\"A\"}");
    LiveUpdatesBridge.end(a, null, 60);
    LiveUpdatesBridge.end(a, null, -1);
    assertEquals(60_000, shown(a).getTimeoutAfter());
    remote("start", "r10", "{\"title\":\"R\"}");
    remote("end", "r10", null);
    remote("end", "r10", null);
    assertEndedLook(shown("r10"), "R");
    // Zero still removes it.
    LiveUpdatesBridge.end(a, null, 0);
    assertEquals(null, shown(a));
  }

  @Test
  public void theEndedLookDropsTimersAndButtonsButKeepsProgress() throws Exception {
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"Order\",\"progress\":0.5,\"timerEnd\":1893456000,"
                + "\"actions\":[{\"id\":\"call\",\"title\":\"Call\"}]}");
    LiveUpdatesBridge.end(id, null, -1);
    Notification n = shown(id);
    assertEndedLook(n, "Order");
    assertFalse(n.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER));
    assertEquals(null, n.actions);
  }

  @Test
  public void afterARestartTheShownNotificationIsKept() throws Exception {
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"Order\",\"body\":\"On the way\",\"timerEnd\":1893456000,"
                + "\"actions\":[{\"id\":\"call\",\"title\":\"Call\"}],"
                + "\"publicContent\":{\"title\":\"Delivery\"}}");
    LiveUpdatesBridge.forgetPostsInProcess(id);
    LiveUpdatesBridge.end(id, null, -1);
    Notification n = shown(id);
    assertEndedLook(n, "Order");
    assertEquals("On the way", n.extras.getCharSequence(Notification.EXTRA_TEXT).toString());
    assertFalse(n.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER));
    assertEquals(null, n.actions);
    assertEquals(4 * HOUR, n.getTimeoutAfter());
    assertEndedLook(n.publicVersion, "Delivery");
    assertEquals(null, LiveUpdatesBridge.keyForId(id));
  }

  @Test
  public void finalContentDropsRunningTimersAndTimeMetrics() throws Exception {
    String id = LiveUpdatesBridge.start("{\"title\":\"Order\"}");
    LiveUpdatesBridge.end(
        id,
        "{\"title\":\"Arrived\",\"timerEnd\":1893456000,\"criticalMetric\":1,"
            + "\"metrics\":[{\"label\":\"Stops\",\"type\":\"integer\",\"value\":3},"
            + "{\"label\":\"ETA\",\"type\":\"timer\",\"value\":1893456000000}]}",
        -1);
    assertFalse(shown(id).extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER));
    JSONObject ended =
        LiveUpdatesBridge.endedContent(
            new JSONObject(
                "{\"criticalMetric\":1,\"metrics\":[{\"type\":\"integer\",\"value\":3},"
                    + "{\"type\":\"stopwatch\",\"value\":1}]}"));
    assertEquals(1, ended.getJSONArray("metrics").length());
    assertFalse(ended.has("criticalMetric"));
    assertFalse(
        LiveUpdatesBridge.endedContent(
                new JSONObject("{\"metrics\":[{\"type\":\"timer\",\"value\":1}]}"))
            .has("metrics"));
  }

  @Test
  public void aNonFiniteDismissTimeUsesTheDefault() throws Exception {
    assertEquals(4 * HOUR, LiveUpdatesBridge.keepEndedMillis(Double.NaN));
    assertEquals(4 * HOUR, LiveUpdatesBridge.keepEndedMillis(Double.POSITIVE_INFINITY));
  }

  @Test
  public void aSecondEndRightAfterTheFirstKeepsTheFinalContent() throws Exception {
    String id = LiveUpdatesBridge.start("{\"title\":\"Order\"}");
    LiveUpdatesBridge.end(id, "{\"title\":\"Delivered\"}", 300);
    LiveUpdatesBridge.end(id, null, -1);
    Notification n = shown(id);
    assertEquals("Delivered", n.extras.getString(Notification.EXTRA_TITLE));
    assertEquals(300_000, n.getTimeoutAfter());
  }

  @Test
  public void endedIsReportedOnceAndFinalContentDoesNotBringBackAGoneUpdate() throws Exception {
    List<String> events = new ArrayList<>();
    LiveUpdatesBridge.observeEvents(events::add, 1);
    String id = LiveUpdatesBridge.start("{\"title\":\"Order\"}");
    LiveUpdatesBridge.end(id, null, 0);
    LiveUpdatesBridge.end(id, "{\"title\":\"Delivered\"}", -1);
    assertEquals(null, shown(id));
    assertEquals(Arrays.asList("started:" + id, "ended:" + id), events);
  }

  @Test
  public void finalContentReplacesAnEndedNotification() throws Exception {
    String id = LiveUpdatesBridge.start("{\"title\":\"Order\"}");
    LiveUpdatesBridge.end(id, null, -1);
    LiveUpdatesBridge.forgetPostsInProcess(id);
    // A later end with final content, after the moment of the first end.
    LiveUpdatesBridge.end(id, "{\"title\":\"Delivered\"}", 60);
    assertEquals("Delivered", shown(id).extras.getString(Notification.EXTRA_TITLE));
  }

  @Test
  public void anUnreadableRemoteDismissTimeUsesTheDefault() throws Exception {
    remote("start", "r11", "{\"title\":\"R\"}");
    JSONObject data =
        new JSONObject()
            .put("live_updates_event", "end")
            .put("live_updates_id", "r11")
            .put("live_updates_dismiss_after", "");
    LiveUpdatesBridge.handleRemotePayload(data.toString());
    assertEquals(4 * HOUR, shown("r11").getTimeoutAfter());
  }

  @Test
  public void endAfterATimeoutReportsNothingAndShowsNothing() throws Exception {
    List<String> events = new ArrayList<>();
    LiveUpdatesBridge.observeEvents(events::add, 1);
    String id = LiveUpdatesBridge.start("{\"title\":\"Order\",\"timeoutAfterMillis\":60000}");
    // The system removed it and the dismiss receiver reported the timeout.
    manager.cancel(LiveUpdatesBridge.TAG_PREFIX + id, LiveUpdatesBridge.NOTIFICATION_ID);
    LiveUpdatesBridge.timedOut(app, id);
    LiveUpdatesBridge.end(id, "{\"title\":\"Delivered\"}", -1);
    assertEquals(null, shown(id));
    assertEquals(Arrays.asList("started:" + id, "ended:" + id), events);
  }

  @Test
  public void endIsReportedForAKnownUpdateThatIsNotShown() throws Exception {
    List<String> events = new ArrayList<>();
    LiveUpdatesBridge.observeEvents(events::add, 1);
    String id = LiveUpdatesBridge.start("{\"title\":\"Order\"}");
    // Not listed (for example with notifications blocked), and not posted a
    // moment ago.
    manager.cancel(LiveUpdatesBridge.TAG_PREFIX + id, LiveUpdatesBridge.NOTIFICATION_ID);
    LiveUpdatesBridge.forgetPostsInProcess(id);
    LiveUpdatesBridge.end(id, null, -1);
    assertEquals(Arrays.asList("started:" + id, "ended:" + id), events);
    // The key starts (and is reported) again.
    LiveUpdatesBridge.startOrUpdate(id, "{\"title\":\"Again\"}");
    assertEquals("started:" + id, events.get(events.size() - 1));
  }

  @Test
  public void endAllAlsoRemovesEndedUpdates() throws Exception {
    String a = LiveUpdatesBridge.start("{\"title\":\"A\"}");
    String b = LiveUpdatesBridge.start("{\"title\":\"B\"}");
    LiveUpdatesBridge.end(a, null, -1);
    LiveUpdatesBridge.endAll();
    assertEquals(null, shown(a));
    assertEquals(null, shown(b));
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
    LiveUpdatesBridge.observeActions((update, action) -> got.add(update + ":" + action), 1, null);
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
    LiveUpdatesBridge.observeActions((update, action) -> got.add(update + ":" + action), 1, null);
    LiveUpdatesBridge.unobserveActions(1);
    LiveUpdatesBridge.requeueActions(new String[] {"u3\nlater"});
    LiveUpdatesBridge.emitAction(app, "u3", "next");
    assertTrue(got.isEmpty());
    assertEquals(
        Arrays.asList("u3\nlater", "u3\nnext"),
        Arrays.asList(LiveUpdatesBridge.takeQueuedActions()));
  }

  @Test
  public void aPerUpdateListenerLeavesOtherPressesQueued() {
    LiveUpdatesBridge.emitAction(app, "a", "queued");
    LiveUpdatesBridge.emitAction(app, "b", "queued");
    List<String> got = new ArrayList<>();
    LiveUpdatesBridge.observeActions(
        (update, action) -> got.add(update + ":" + action), 1, new String[] {"a"});
    LiveUpdatesBridge.emitAction(app, "a", "live");
    LiveUpdatesBridge.emitAction(app, "b", "live");
    assertEquals(Arrays.asList("a:queued", "a:live"), got);
    // B's presses stay in the persistent queue, for the background handler.
    assertEquals(
        Arrays.asList("b\nqueued", "b\nlive"),
        Arrays.asList(LiveUpdatesBridge.takeQueuedActions()));
  }

  @Test
  public void wideningTheFilterHandsOverQueuedPresses() {
    List<String> got = new ArrayList<>();
    LiveUpdatesBridge.observeActions(
        (update, action) -> got.add(update + ":" + action), 1, new String[] {"a"});
    LiveUpdatesBridge.emitAction(app, "b", "x");
    assertTrue(got.isEmpty());
    LiveUpdatesBridge.setActionFilter(1, null);
    assertEquals(Arrays.asList("b:x"), got);
    // Another engine cannot change this engine's filter.
    LiveUpdatesBridge.setActionFilter(2, new String[] {"a"});
    LiveUpdatesBridge.emitAction(app, "c", "y");
    assertEquals("c:y", got.get(1));
  }

  @Test
  public void backgroundHandlerDoesNotTakeWhatTheAppListensFor() {
    List<String> got = new ArrayList<>();
    LiveUpdatesBridge.emitAction(app, "b", "x");
    LiveUpdatesBridge.observeActions(
        (update, action) -> got.add(update + ":" + action), 1, new String[] {"a"});
    assertEquals(Arrays.asList("b\nx"), Arrays.asList(LiveUpdatesBridge.takeQueuedActions()));
    assertTrue(got.isEmpty());
  }

  @Test
  public void localEndDoesNotBringBackADismissedUpdate() throws Exception {
    String id = LiveUpdatesBridge.startOrUpdate("order-d", "{\"title\":\"A\"}");
    manager.cancel(LiveUpdatesBridge.TAG_PREFIX + id, LiveUpdatesBridge.NOTIFICATION_ID);
    LiveUpdatesBridge.markDismissed(app, id);
    LiveUpdatesBridge.end(id, "{\"title\":\"Delivered\"}", -1);
    assertEquals(null, shown(id));
  }

  @Test
  public void endedFinalContentHasAnEndedPublicVersion() throws Exception {
    String id = LiveUpdatesBridge.start("{\"title\":\"Order\"}");
    LiveUpdatesBridge.end(
        id, "{\"title\":\"Delivered\",\"publicContent\":{\"title\":\"Done\"}}", 30);
    Notification n = shown(id);
    assertFalse((n.flags & Notification.FLAG_ONGOING_EVENT) != 0);
    assertFalse(n.extras.getBoolean("android.requestPromotedOngoing"));
    Notification p = n.publicVersion;
    assertEquals("Done", p.extras.getString(Notification.EXTRA_TITLE));
    assertFalse((p.flags & Notification.FLAG_ONGOING_EVENT) != 0);
    assertTrue((p.flags & Notification.FLAG_AUTO_CANCEL) != 0);
    assertFalse(p.extras.getBoolean("android.requestPromotedOngoing"));
  }

  @Test
  public void theIosAlertOfARemotePayloadAlertsOnAndroidToo() throws Exception {
    JSONObject withAlert = new JSONObject("{\"title\":\"A\",\"alert\":{\"title\":\"t\",\"body\":\"b\"}}");
    assertTrue(LiveUpdatesBridge.wantsAlert(withAlert, true));
    // Local content says androidAlert itself (the iOS option alone does not alert).
    assertFalse(LiveUpdatesBridge.wantsAlert(withAlert, false));
    assertTrue(LiveUpdatesBridge.wantsAlert(new JSONObject("{\"androidAlert\":true}"), false));
    assertFalse(LiveUpdatesBridge.wantsAlert(new JSONObject("{\"alert\":true}"), true));
    // An explicit androidAlert wins.
    withAlert.put("androidAlert", false);
    assertFalse(LiveUpdatesBridge.wantsAlert(withAlert, true));
    // What stays after the end does not alert.
    assertFalse(LiveUpdatesBridge.endedContent(withAlert).has("alert"));
  }

  @Test
  public void startFailsWhenNotificationsAreOff() throws Exception {
    List<String> events = new ArrayList<>();
    LiveUpdatesBridge.observeEvents(events::add, 1);
    shadowOf(manager).setNotificationsEnabled(false);
    try {
      LiveUpdatesBridge.start("{\"title\":\"A\"}");
      org.junit.Assert.fail("start must fail");
    } catch (IllegalStateException expected) {
      // As iOS with Live Activities turned off.
    }
    try {
      LiveUpdatesBridge.startOrUpdate("off-key", "{\"title\":\"A\"}");
      org.junit.Assert.fail("startOrUpdate must fail");
    } catch (IllegalStateException expected) {
      // Same.
    }
    assertTrue(events.isEmpty());
    assertFalse(Arrays.asList(LiveUpdatesBridge.activeIds()).contains("off-key"));
    shadowOf(manager).setNotificationsEnabled(true);
  }

  @Test
  public void startOrUpdateOfAShownKeyDoesNotFailOnABlockedChannel() throws Exception {
    LiveUpdatesBridge.startOrUpdate("shown-key", "{\"title\":\"A\",\"channelId\":\"later-off\"}");
    manager.getNotificationChannel("later-off").setImportance(NotificationManager.IMPORTANCE_NONE);
    // As update(): the shown update is updated, not an error.
    LiveUpdatesBridge.startOrUpdate("shown-key", "{\"title\":\"B\",\"channelId\":\"later-off\"}");
  }

  @Test
  @Config(sdk = 36)
  public void startFailsWhenTheChannelGroupIsOff() throws Exception {
    android.app.NotificationChannelGroup group =
        new android.app.NotificationChannelGroup("g", "Group");
    // setBlocked is hidden from the SDK stubs.
    android.app.NotificationChannelGroup.class
        .getMethod("setBlocked", boolean.class)
        .invoke(group, true);
    manager.createNotificationChannelGroup(group);
    android.app.NotificationChannel channel =
        new android.app.NotificationChannel("grouped", "Grouped", NotificationManager.IMPORTANCE_DEFAULT);
    channel.setGroup("g");
    manager.createNotificationChannel(channel);
    try {
      LiveUpdatesBridge.start("{\"title\":\"A\",\"channelId\":\"grouped\"}");
      org.junit.Assert.fail("start must fail");
    } catch (IllegalStateException expected) {
      // The user turned that channel's group off.
    }
  }

  @Test
  public void startFailsOnABlockedChannel() throws Exception {
    manager.createNotificationChannel(
        new android.app.NotificationChannel(
            "off", "Off", NotificationManager.IMPORTANCE_NONE));
    try {
      LiveUpdatesBridge.start("{\"title\":\"A\",\"channelId\":\"off\"}");
      org.junit.Assert.fail("start must fail");
    } catch (IllegalStateException expected) {
      // The user turned that channel off.
    }
  }

  @Test
  public void updateToABlockedChannelDoesNotThrow() throws Exception {
    // The user turned the channel off: the system never lists the posts.
    manager.createNotificationChannel(
        new android.app.NotificationChannel(
            "off", "Off", NotificationManager.IMPORTANCE_NONE));
    LiveUpdatesBridge.update("never-listed", "{\"title\":\"A\",\"channelId\":\"off\"}");
  }

  @Test
  public void intentsFromRecentsAreNotDeliveredAgain() throws Exception {
    String id = LiveUpdatesBridge.start("{\"title\":\"A\",\"route\":\"/orders/2\"}");
    Intent tap = new Intent(shadowOf(shown(id).contentIntent).getSavedIntent());
    tap.addFlags(Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY);
    List<String> routes = new ArrayList<>();
    LiveUpdatesBridge.observeTaps(routes::add, 1);
    LiveUpdatesBridge.handleIntent(tap);
    assertTrue(routes.isEmpty());
  }

  @Test
  public void everyWaitingPermissionRequestCompletes() {
    shadowOf(app).denyPermissions(android.Manifest.permission.POST_NOTIFICATIONS);
    LiveUpdatesBridge.activity =
        org.robolectric.Robolectric.buildActivity(android.app.Activity.class).setup().get();
    List<Boolean> results = new ArrayList<>();
    LiveUpdatesBridge.requestPermission(results::add);
    LiveUpdatesBridge.requestPermission(results::add);
    assertTrue(results.isEmpty());
    // The activity goes away without a result: both callers still complete.
    LiveUpdatesBridge.permissionPromptGone();
    assertEquals(Arrays.asList(false, false), results);
    LiveUpdatesBridge.activity = null;
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
  public void remoteEndKeepsFinalContentForFourHoursWithoutDismissTime() throws Exception {
    remote("start", "r6", "{\"title\":\"A\"}");
    remote("end", "r6", "{\"title\":\"Delivered\"}");
    assertEquals("Delivered", shown("r6").extras.getString(Notification.EXTRA_TITLE));
    assertEquals(4 * HOUR, shown("r6").getTimeoutAfter());
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
    LiveUpdatesBridge.observeActions((update, action) -> got.add(update + ":" + action), 1, null);
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
            "{\"title\":\"A\",\"timeoutAfterMillis\":1,"
                + "\"icon\":{\"native\":\"android:drawable/ic_dialog_alert\"}}");
    Notification n = shown(id);
    assertEquals(60_000, n.getTimeoutAfter());
    assertEquals(android.R.drawable.ic_dialog_info, n.getSmallIcon().getResId());
  }

  @Test
  public void iconsThatCannotBeShownUseTheDefault() throws Exception {
    for (String icon :
        new String[] {
          "{\"native\":\"no_such_drawable\"}",
          "{\"symbol\":\"shippingbox\"}",
          "{\"asset\":\"assets/missing.png\"}",
          "{\"asset\":\"../secret.png\"}",
          "{}",
          "\"ic_plain_string\""
        }) {
      String id = LiveUpdatesBridge.start("{\"title\":\"A\",\"icon\":" + icon + "}");
      assertEquals(icon, android.R.drawable.ic_dialog_info, shown(id).getSmallIcon().getResId());
    }
  }

  @Test
  public void androidSmallIconWinsAndFailsToTheDefaultNotToIcon() throws Exception {
    android.os.Bundle meta = new android.os.Bundle();
    meta.putInt(LiveUpdatesBridge.DEFAULT_ICON_META, android.R.drawable.ic_menu_add);
    shadowOf(app.getPackageManager())
        .getInternalMutablePackageInfo(app.getPackageName())
        .applicationInfo
        .metaData = meta;
    // No icon at all: the manifest default.
    String id = LiveUpdatesBridge.start("{\"title\":\"A\"}");
    assertEquals(android.R.drawable.ic_menu_add, shown(id).getSmallIcon().getResId());
    // A missing androidSmallIcon does not fall back to icon.
    id =
        LiveUpdatesBridge.start(
            "{\"title\":\"A\",\"icon\":{\"native\":\"x\"},\"androidSmallIcon\":{\"symbol\":\"y\"}}");
    assertEquals(android.R.drawable.ic_menu_add, shown(id).getSmallIcon().getResId());
    // A 0.1.x string value is not an icon object: the default, not icon.
    id =
        LiveUpdatesBridge.start(
            "{\"title\":\"A\",\"icon\":{\"native\":\"ic_dialog_info\"},\"androidSmallIcon\":\"ic_x\"}");
    assertEquals(android.R.drawable.ic_menu_add, shown(id).getSmallIcon().getResId());
  }

  @Test
  public void defaultIconMetaDataThatIsNotADrawableFallsBackToTheAppIcon() throws Exception {
    android.os.Bundle meta = new android.os.Bundle();
    // A string resource, not a drawable.
    meta.putInt(LiveUpdatesBridge.DEFAULT_ICON_META, android.R.string.ok);
    shadowOf(app.getPackageManager())
        .getInternalMutablePackageInfo(app.getPackageName())
        .applicationInfo
        .metaData = meta;
    String id = LiveUpdatesBridge.start("{\"title\":\"A\"}");
    assertEquals(android.R.drawable.ic_dialog_info, shown(id).getSmallIcon().getResId());

    // A plain value instead of android:resource, and an id that does not exist.
    android.os.Bundle string = new android.os.Bundle();
    string.putString(LiveUpdatesBridge.DEFAULT_ICON_META, "ic_stat");
    android.os.Bundle missing = new android.os.Bundle();
    missing.putInt(LiveUpdatesBridge.DEFAULT_ICON_META, 0x7f7f7f7f);
    for (android.os.Bundle bad : new android.os.Bundle[] {string, missing}) {
      shadowOf(app.getPackageManager())
          .getInternalMutablePackageInfo(app.getPackageName())
          .applicationInfo
          .metaData = bad;
      LiveUpdatesBridge.engineAttached(app); // Reads the meta-data again.
      id = LiveUpdatesBridge.start("{\"title\":\"B\"}");
      assertEquals(android.R.drawable.ic_dialog_info, shown(id).getSmallIcon().getResId());
    }
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

  @Test
  public void tapsAndEventsReachEveryEngineUntilItDetaches() throws Exception {
    List<String> app1 = new ArrayList<>();
    List<String> bg = new ArrayList<>();
    LiveUpdatesBridge.observeTaps(app1::add, 1);
    LiveUpdatesBridge.observeTaps(bg::add, 2); // a background engine
    List<String> events1 = new ArrayList<>();
    LiveUpdatesBridge.observeEvents(events1::add, 1);
    LiveUpdatesBridge.observeEvents(e -> {}, 2);
    LiveUpdatesBridge.engineDetached(2);

    String id = LiveUpdatesBridge.start("{\"title\":\"A\",\"route\":\"/r\"}");
    LiveUpdatesBridge.handleIntent(new Intent(shadowOf(shown(id).contentIntent).getSavedIntent()));
    // The app's engine still gets them after the background engine left.
    assertEquals(Arrays.asList("/r"), app1);
    assertTrue(bg.isEmpty());
    assertEquals(Arrays.asList("started:" + id), events1);
  }

  @Test
  public void pendingTapsGoToTheNextListenerOnce() throws Exception {
    String id = LiveUpdatesBridge.start("{\"title\":\"A\",\"route\":\"/later\"}");
    LiveUpdatesBridge.handleIntent(new Intent(shadowOf(shown(id).contentIntent).getSavedIntent()));
    List<String> first = new ArrayList<>();
    List<String> second = new ArrayList<>();
    LiveUpdatesBridge.observeTaps(first::add, 1);
    LiveUpdatesBridge.observeTaps(second::add, 2);
    assertEquals(Arrays.asList("/later"), first);
    assertTrue(second.isEmpty());
  }

  @Test
  public void openAppPressGoesToTheListener() throws Exception {
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"A\",\"actions\":[{\"id\":\"track\",\"title\":\"Track\",\"opensApp\":true}]}");
    Intent press = shadowOf(shown(id).actions[0].actionIntent).getSavedIntent();
    List<String> got = new ArrayList<>();
    LiveUpdatesBridge.observeActions((u, a) -> got.add(u + ":" + a), 1, null);
    LiveUpdatesBridge.handleIntent(new Intent(press));
    assertEquals(Arrays.asList(id + ":track"), got);
    // Taken: nothing is left for the background handler after the grace time.
    org.robolectric.shadows.ShadowLooper.idleMainLooper(6, java.util.concurrent.TimeUnit.SECONDS);
    assertEquals(0, LiveUpdatesBridge.takeQueuedActions().length);
  }

  @Test
  public void openAppPressWithoutListenerStaysForTheBackgroundHandler() throws Exception {
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"A\",\"actions\":[{\"id\":\"track\",\"title\":\"Track\",\"opensApp\":true}]}");
    Intent press = shadowOf(shown(id).actions[0].actionIntent).getSavedIntent();
    LiveUpdatesBridge.handleIntent(new Intent(press));
    org.robolectric.shadows.ShadowLooper.idleMainLooper(6, java.util.concurrent.TimeUnit.SECONDS);
    assertEquals(
        Arrays.asList(id + "\ntrack"), Arrays.asList(LiveUpdatesBridge.takeQueuedActions()));
  }

  @Test
  public void forgedOpenAppPressesAreIgnored() {
    List<String> got = new ArrayList<>();
    LiveUpdatesBridge.observeActions((u, a) -> got.add(u + ":" + a), 1, null);
    LiveUpdatesBridge.handleIntent(
        new Intent()
            .putExtra(LiveUpdatesBridge.EXTRA_TOKEN, "guess")
            .putExtra("com.ttechapp.live_updates.ACTION_ID", "cancel")
            .putExtra("com.ttechapp.live_updates.UPDATE_ID", "u1"));
    assertTrue(got.isEmpty());
  }

  @Test
  public void requeuedPressesKeepTheirOrder() {
    LiveUpdatesBridge.emitAction(app, "u", "second");
    LiveUpdatesBridge.requeueActions(new String[] {"u\nfirst"});
    assertEquals(
        Arrays.asList("u\nfirst", "u\nsecond"),
        Arrays.asList(LiveUpdatesBridge.takeQueuedActions()));
  }

  @Test
  public void eachTakeIsCounted() {
    int before = LiveUpdatesBridge.takeCount;
    LiveUpdatesBridge.takeQueuedActions();
    LiveUpdatesBridge.takeQueuedActions();
    assertEquals(before + 2, LiveUpdatesBridge.takeCount);
  }

  @Test
  public void regularNotificationsShowTheDetailAsASecondLine() throws Exception {
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"Order\",\"body\":\"On the way\",\"progress\":0.5,"
                + "\"androidMode\":\"classic\",\"journey\":{\"from\":\"Shop\",\"to\":\"Home\"}}");
    Notification n = shown(id);
    // Not in the header, where it would be cut off.
    assertEquals(null, n.extras.getCharSequence(Notification.EXTRA_SUB_TEXT));
    assertEquals("On the way", n.extras.getCharSequence(Notification.EXTRA_TEXT).toString());
    assertEquals(
        "On the way\nShop \u2192 Home",
        n.extras.getCharSequence(Notification.EXTRA_BIG_TEXT).toString());
    assertEquals(50, n.extras.getInt(Notification.EXTRA_PROGRESS));
  }

  @Test
  public void liveUpdatesWithoutProgressKeepTheSubText() throws Exception {
    // Android 16+ (not classic): unchanged, the detail stays the sub text.
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"Trip\",\"body\":\"On time\",\"journey\":{\"from\":\"A\",\"to\":\"B\"}}");
    Notification n = shown(id);
    assertEquals("A \u2192 B", n.extras.getCharSequence(Notification.EXTRA_SUB_TEXT).toString());
    assertEquals(null, n.extras.getCharSequence(Notification.EXTRA_BIG_TEXT));
  }

  /** Shows {@code id} as the system would after deciding on promotion. */
  private void showWithFlags(String id, int flags) {
    Notification n =
        new Notification.Builder(app, "live_updates")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("Order")
            .build();
    n.flags |= flags;
    manager.notify(LiveUpdatesBridge.TAG_PREFIX + id, LiveUpdatesBridge.NOTIFICATION_ID, n);
  }

  @Test
  public void isPromotedReadsThePromotedFlag() {
    showWithFlags("promoted", Notification.FLAG_ONGOING_EVENT | Notification.FLAG_PROMOTED_ONGOING);
    assertTrue(LiveUpdatesBridge.isPromoted("promoted"));
  }

  @Test
  public void isPromotedIsFalseWithoutTheFlag() throws Exception {
    showWithFlags("demoted", Notification.FLAG_ONGOING_EVENT);
    assertFalse(LiveUpdatesBridge.isPromoted("demoted"));
    // Requesting promotion is not being promoted.
    assertFalse(LiveUpdatesBridge.isPromoted(LiveUpdatesBridge.start("{\"title\":\"Order\"}")));
  }

  @Test
  public void isPromotedIsFalseRightAfterEnd() throws Exception {
    showWithFlags("ended", Notification.FLAG_ONGOING_EVENT | Notification.FLAG_PROMOTED_ONGOING);
    LiveUpdatesBridge.end("ended", null, 0);
    // The system may still list the notification for a moment.
    showWithFlags("ended", Notification.FLAG_ONGOING_EVENT | Notification.FLAG_PROMOTED_ONGOING);
    assertFalse(LiveUpdatesBridge.isPromoted("ended"));
  }

  @Test
  public void isPromotedIsFalseForAnUnknownId() {
    showWithFlags("other", Notification.FLAG_PROMOTED_ONGOING);
    assertFalse(LiveUpdatesBridge.isPromoted("missing"));
  }

  @Test
  public void remotePayloadsWithoutTitleAreWarnedAbout() throws Exception {
    org.robolectric.shadows.ShadowLog.clear();
    assertTrue(remote("start", "untitled", "{}"));
    // Android promotes a title of only spaces.
    assertTrue(remote("start", "spaces", "{\"title\":\"  \"}"));
    assertTrue(remote("start", "titled", "{\"title\":\"Order\"}"));
    assertTrue(remote("start", "plain", "{\"title\":\"\",\"androidMode\":\"ongoing\"}"));
    long warnings =
        org.robolectric.shadows.ShadowLog.getLogsForTag("live_updates").stream()
            .filter(l -> l.msg.startsWith("title is empty"))
            .count();
    assertEquals(1, warnings);
    // Still posted.
    assertNotNull(shown("untitled"));
  }
}
