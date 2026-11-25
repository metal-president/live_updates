package com.ttechapp.live_updates;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.robolectric.Shadows.shadowOf;

import android.app.AlarmManager;
import android.app.Application;
import android.app.Notification;
import android.app.NotificationManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.service.notification.StatusBarNotification;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import org.json.JSONObject;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;
import org.robolectric.shadows.ShadowAlarmManager;

/** LiveUpdateContent.endAt / endedContent and AndroidLiveUpdateOptions.maxDuration / removeAtEnd. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 36)
public class LiveUpdatesEndTest {
  private static final long MINUTE = 60_000;
  private static final long HOUR = 60 * MINUTE;
  /** Slack for times computed a few milliseconds apart. */
  private static final long SLACK = 5_000;

  private final Application app = RuntimeEnvironment.getApplication();
  private final List<String> events = new ArrayList<>();
  private NotificationManager manager;
  private AlarmManager alarms;

  @Before
  public void setUp() {
    app.getApplicationInfo().icon = android.R.drawable.ic_dialog_info;
    // A launcher activity, so tap intents can be built.
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
    alarms = (AlarmManager) app.getSystemService(Context.ALARM_SERVICE);
    ShadowAlarmManager.setCanScheduleExactAlarms(true);
    LiveUpdatesBridge.engineAttached(app);
    LiveUpdatesBridge.observeEvents(events::add, 1);
  }

  @After
  public void tearDown() {
    LiveUpdatesBridge.engineDetached(1);
    ShadowAlarmManager.reset();
  }

  private Notification shown(String id) {
    for (StatusBarNotification n : manager.getActiveNotifications()) {
      if ((LiveUpdatesBridge.TAG_PREFIX + id).equals(n.getTag())) return n.getNotification();
    }
    return null;
  }

  private static String seconds(long epochMillis) {
    return String.valueOf(epochMillis / 1000.0);
  }

  private static void assertAbout(long expected, long actual) {
    assertTrue("expected about " + expected + " but was " + actual,
        Math.abs(expected - actual) < SLACK);
  }

  private SharedPreferences prefs() {
    return app.getSharedPreferences("com.ttechapp.live_updates", Context.MODE_PRIVATE);
  }

  /** Moves the stored time of {@code key} in {@code pref} to the past, as the clock cannot be. */
  private void makeDue(String pref, String key, String field) throws Exception {
    JSONObject all = new JSONObject(prefs().getString(pref, "{}"));
    all.getJSONObject(key).put(field, System.currentTimeMillis() - 1);
    prefs().edit().putString(pref, all.toString()).commit();
  }

  private void fireEndAlarm() throws Exception {
    List<ShadowAlarmManager.ScheduledAlarm> list = shadowOf(alarms).getScheduledAlarms();
    assertEquals(1, list.size());
    Intent intent = shadowOf(list.get(0).operation).getSavedIntent();
    assertEquals(LiveUpdatesScheduler.ACTION_END, intent.getAction());
    makeDue("ends", intent.getStringExtra(LiveUpdatesScheduler.EXTRA_KEY), "at");
    new LiveUpdatesScheduleReceiver().onReceive(app, intent);
  }

  @Test
  public void liveUpdatesAreRemovedAfterEightHoursByDefault() throws Exception {
    LiveUpdatesBridge.startOrUpdate("order", "{\"title\":\"Order\"}");
    assertAbout(8 * HOUR, shown("order").getTimeoutAfter());
  }

  @Test
  public void aCountdownRemovesTheUpdateWhenItEnds() throws Exception {
    long eta = System.currentTimeMillis() + 20 * MINUTE;
    LiveUpdatesBridge.startOrUpdate("order", "{\"title\":\"Order\",\"timerEnd\":" + seconds(eta) + "}");
    Notification n = shown("order");
    assertAbout(20 * MINUTE, n.getTimeoutAfter());
    assertTrue(n.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER));
    // An earlier limit still wins.
    LiveUpdatesBridge.startOrUpdate(
        "short",
        "{\"title\":\"A\",\"timerEnd\":" + seconds(eta) + ",\"maxDurationMillis\":" + MINUTE + "}");
    assertAbout(MINUTE, shown("short").getTimeoutAfter());
  }

  @Test
  public void endedContentAtTheCountdownEndWinsOverTheRemoval() throws Exception {
    long eta = System.currentTimeMillis() + 20 * MINUTE;
    LiveUpdatesBridge.startOrUpdate(
        "order",
        "{\"title\":\"Order\",\"timerEnd\":" + seconds(eta) + ",\"endAt\":" + seconds(eta)
            + ",\"endedContent\":{\"title\":\"Delivered\"}}");
    // Removed 10 minutes after the countdown should the alarm never come.
    assertAbout(30 * MINUTE, shown("order").getTimeoutAfter());
    fireEndAlarm();
    assertEquals("Delivered", shown("order").extras.getString(Notification.EXTRA_TITLE));
  }

  @Test
  public void withoutExactAlarmsTheCountdownRemovalWins() throws Exception {
    ShadowAlarmManager.setCanScheduleExactAlarms(false);
    long eta = System.currentTimeMillis() + 20 * MINUTE;
    LiveUpdatesBridge.startOrUpdate(
        "order",
        "{\"title\":\"Order\",\"timerEnd\":" + seconds(eta) + ",\"endAt\":" + seconds(eta)
            + ",\"endedContent\":{\"title\":\"Delivered\"}}");
    // The ended content could come up to 10 minutes late.
    assertAbout(20 * MINUTE, shown("order").getTimeoutAfter());
  }

  @Test
  public void aRemoteCountdownCannotRemoveTheUpdateAtOnce() throws Exception {
    JSONObject data =
        new JSONObject()
            .put("live_updates_event", "start")
            .put("live_updates_id", "r")
            .put(
                "live_updates_content",
                "{\"title\":\"R\",\"timerEnd\":" + seconds(System.currentTimeMillis() + 50) + "}");
    assertTrue(LiveUpdatesBridge.handleRemotePayload(data.toString()));
    assertAbout(MINUTE, shown("r").getTimeoutAfter());
  }

  @Test
  public void removeAtCountdownEndFalseKeepsTheUpdate() throws Exception {
    long eta = System.currentTimeMillis() + 20 * MINUTE;
    LiveUpdatesBridge.startOrUpdate(
        "order",
        "{\"title\":\"Order\",\"timerEnd\":" + seconds(eta) + ",\"removeAtCountdownEnd\":false}");
    assertAbout(8 * HOUR, shown("order").getTimeoutAfter());
  }

  @Test
  public void aCountdownThatIsOverIsNotShown() throws Exception {
    long past = System.currentTimeMillis() - MINUTE;
    LiveUpdatesBridge.startOrUpdate("order", "{\"title\":\"Order\",\"timerEnd\":" + seconds(past) + "}");
    Notification n = shown("order");
    assertFalse(n.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER));
    // Not removed at once: only the timer is left out.
    assertAbout(8 * HOUR, n.getTimeoutAfter());
  }

  @Test
  public void stateOfReportsWhatTheSystemShows() throws Exception {
    assertNull(LiveUpdatesBridge.stateOf("st-order"));
    long endAt = System.currentTimeMillis() + 20 * MINUTE;
    LiveUpdatesBridge.startOrUpdate(
        "st-order", "{\"title\":\"Order\",\"endAt\":" + seconds(endAt) + "}");
    assertEquals("active", LiveUpdatesBridge.stateOf("st-order"));
    fireEndAlarm();
    assertEquals("stale", LiveUpdatesBridge.stateOf("st-order"));
    // After a process restart: from the endAt on the shown notification.
    LiveUpdatesBridge.forgetPostsInProcess("st-order");
    assertEquals("stale", LiveUpdatesBridge.stateOf("st-order"));
    LiveUpdatesBridge.end("st-order", null, -1);
    assertEquals("ended", LiveUpdatesBridge.stateOf("st-order"));
    LiveUpdatesBridge.end("st-order", null, 0);
    assertNull(LiveUpdatesBridge.stateOf("st-order"));
    // A dismissal is remembered until the app ends the update.
    LiveUpdatesBridge.startOrUpdate("d", "{\"title\":\"D\"}");
    manager.cancel(LiveUpdatesBridge.TAG_PREFIX + "d", LiveUpdatesBridge.NOTIFICATION_ID);
    LiveUpdatesBridge.markDismissed(app, "d");
    LiveUpdatesBridge.forgetPostsInProcess("d");
    assertEquals("dismissed", LiveUpdatesBridge.stateOf("d"));
  }

  @Test
  public void endedContentAtEndAtIsStale() throws Exception {
    long endAt = System.currentTimeMillis() + 20 * MINUTE;
    LiveUpdatesBridge.startOrUpdate(
        "order",
        "{\"title\":\"Order\",\"endAt\":" + seconds(endAt)
            + ",\"endedContent\":{\"title\":\"Delivered\"}}");
    fireEndAlarm();
    assertEquals("stale", LiveUpdatesBridge.stateOf("order"));
  }

  @Test
  public void maxDurationZeroMeansNoLimit() throws Exception {
    LiveUpdatesBridge.startOrUpdate("order", "{\"title\":\"Order\",\"maxDurationMillis\":0}");
    assertEquals(0, shown("order").getTimeoutAfter());
  }

  @Test
  public void maxDurationCountsFromTheStartNotFromUpdates() throws Exception {
    String json = "{\"title\":\"Order\",\"maxDurationMillis\":" + HOUR + "}";
    LiveUpdatesBridge.startOrUpdate("order", json);
    // The update started half an hour ago.
    JSONObject times = new JSONObject(prefs().getString("startTimes", "{}"));
    times.put("order", System.currentTimeMillis() - 30 * MINUTE);
    prefs().edit().putString("startTimes", times.toString()).commit();
    LiveUpdatesBridge.update("order", json);
    assertAbout(30 * MINUTE, shown("order").getTimeoutAfter());
  }

  @Test
  public void anUpdateAfterMaxDurationEndsIt() throws Exception {
    String json = "{\"title\":\"Order\",\"maxDurationMillis\":" + HOUR + "}";
    LiveUpdatesBridge.startOrUpdate("order", json);
    JSONObject times = new JSONObject(prefs().getString("startTimes", "{}"));
    times.put("order", System.currentTimeMillis() - 2 * HOUR);
    prefs().edit().putString("startTimes", times.toString()).commit();
    events.clear();
    LiveUpdatesBridge.update("order", json);
    assertNull(shown("order"));
    assertEquals(Arrays.asList("ended:order"), events);
  }

  @Test
  public void aNewUpdateWithTheKeyStartsAFreshDuration() throws Exception {
    String json = "{\"title\":\"Order\",\"maxDurationMillis\":" + HOUR + "}";
    LiveUpdatesBridge.startOrUpdate("order", json);
    JSONObject times = new JSONObject(prefs().getString("startTimes", "{}"));
    times.put("order", System.currentTimeMillis() - 50 * MINUTE);
    prefs().edit().putString("startTimes", times.toString()).commit();
    LiveUpdatesBridge.end("order", null, 0);
    LiveUpdatesBridge.startOrUpdate("order", json);
    assertAbout(HOUR, shown("order").getTimeoutAfter());
  }

  @Test
  public void removeAtEndRemovesItAtEndAt() throws Exception {
    long endAt = System.currentTimeMillis() + 20 * MINUTE;
    LiveUpdatesBridge.startOrUpdate(
        "order",
        "{\"title\":\"Order\",\"endAt\":" + seconds(endAt) + ",\"removeAtEnd\":true,"
            + "\"endedContent\":{\"title\":\"Delivered\"}}");
    assertAbout(20 * MINUTE, shown("order").getTimeoutAfter());
    // Removal wins over the ended content: no end alarm.
    assertTrue(shadowOf(alarms).getScheduledAlarms().isEmpty());
  }

  @Test
  public void theEarlierOfEndAtAndMaxDurationRemovesIt() throws Exception {
    long endAt = System.currentTimeMillis() + 3 * HOUR;
    LiveUpdatesBridge.startOrUpdate(
        "order",
        "{\"title\":\"Order\",\"endAt\":" + seconds(endAt) + ",\"removeAtEnd\":true,"
            + "\"maxDurationMillis\":" + HOUR + "}");
    assertAbout(HOUR, shown("order").getTimeoutAfter());
  }

  @Test
  public void endAtWithoutEndedContentOnlyMakesItStale() throws Exception {
    long endAt = System.currentTimeMillis() + 20 * MINUTE;
    LiveUpdatesBridge.startOrUpdate(
        "order", "{\"title\":\"Order\",\"progress\":0.5,\"endAt\":" + seconds(endAt) + "}");
    assertAbout(8 * HOUR, shown("order").getTimeoutAfter());
    events.clear();
    fireEndAlarm();
    Notification n = shown("order");
    assertEquals("Order", n.extras.getString(Notification.EXTRA_TITLE));
    assertTrue((n.flags & Notification.FLAG_ONGOING_EVENT) != 0);
    assertEquals(Arrays.asList("stale:order"), events);
    assertTrue(Arrays.asList(LiveUpdatesBridge.activeIds()).contains("order"));
  }

  @Test
  public void endedContentReplacesTheUpdateAtEndAt() throws Exception {
    long endAt = System.currentTimeMillis() + 20 * MINUTE;
    LiveUpdatesBridge.startOrUpdate(
        "order",
        "{\"title\":\"Order\",\"body\":\"On the way\",\"progress\":0.5,\"route\":\"/o\","
            + "\"colorArgb\":4278190335,\"maxDurationMillis\":" + HOUR + ","
            + "\"actions\":[{\"id\":\"x\",\"title\":\"X\"}],"
            + "\"endAt\":" + seconds(endAt) + ",\"endedContent\":{\"title\":\"Delivered\","
            + "\"body\":\"Enjoy\"}}");
    List<ShadowAlarmManager.ScheduledAlarm> list = shadowOf(alarms).getScheduledAlarms();
    assertEquals(1, list.size());
    assertEquals(endAt, list.get(0).getTriggerAtMs());
    assertEquals(ShadowAlarmManager.WINDOW_EXACT, list.get(0).getWindowLengthMs());
    events.clear();
    // The process may have been started by the alarm.
    LiveUpdatesBridge.context = null;

    fireEndAlarm();

    Notification n = shown("order");
    assertNotNull(n);
    assertEquals("Delivered", n.extras.getString(Notification.EXTRA_TITLE));
    assertEquals("Enjoy", n.extras.getCharSequence(Notification.EXTRA_TEXT).toString());
    assertEquals(0, n.flags & Notification.FLAG_ONGOING_EVENT);
    assertEquals(0, n.flags & Notification.FLAG_PROMOTED_ONGOING);
    assertEquals(0xFF0000FF, n.color);
    assertNotNull(n.contentIntent);
    assertNull(n.actions);
    assertEquals(0, n.extras.getInt(Notification.EXTRA_PROGRESS_MAX));
    // A tap does not remove it: the update keeps running.
    assertEquals(0, n.flags & Notification.FLAG_AUTO_CANCEL);
    // maxDuration still removes it when its time comes.
    assertAbout(HOUR, n.getTimeoutAfter());
    // Stale, as on iOS: still running and found by its key.
    assertEquals(Arrays.asList("stale:order"), events);
    assertTrue(Arrays.asList(LiveUpdatesBridge.activeIds()).contains("order"));
    assertEquals("order", LiveUpdatesBridge.idForKey("order"));
    assertEquals("order", LiveUpdatesBridge.keyForId("order"));
  }

  @Test
  public void anUpdateAfterTheEndMakesItActiveAgain() throws Exception {
    long endAt = System.currentTimeMillis() + 20 * MINUTE;
    LiveUpdatesBridge.startOrUpdate(
        "order",
        "{\"title\":\"Order\",\"endAt\":" + seconds(endAt)
            + ",\"endedContent\":{\"title\":\"Delivered\"}}");
    fireEndAlarm();
    events.clear();
    LiveUpdatesBridge.startOrUpdate("order", "{\"title\":\"Order again\"}");
    Notification n = shown("order");
    assertEquals("Order again", n.extras.getString(Notification.EXTRA_TITLE));
    assertTrue((n.flags & Notification.FLAG_ONGOING_EVENT) != 0);
    assertFalse(n.extras.getBoolean(LiveUpdatesBridge.EXTRA_STALE, false));
    assertEquals(Arrays.asList("active:order"), events);
  }

  @Test
  public void aStaleUpdateIsEndedByEndAndCanBeDismissed() throws Exception {
    long endAt = System.currentTimeMillis() + 20 * MINUTE;
    String json =
        "{\"title\":\"Order\",\"endAt\":" + seconds(endAt)
            + ",\"endedContent\":{\"title\":\"Delivered\"}}";
    LiveUpdatesBridge.startOrUpdate("a", json);
    fireEndAlarm();
    events.clear();
    LiveUpdatesBridge.end("a", null, 0);
    assertNull(shown("a"));
    assertEquals(Arrays.asList("ended:a"), events);
    // A swipe reports dismissed, as for any live update.
    LiveUpdatesBridge.startOrUpdate("b", json);
    fireEndAlarm();
    Notification n = shown("b");
    assertNotNull(n.deleteIntent);
    events.clear();
    new LiveUpdatesDismissReceiver()
        .onReceive(app, shadowOf(n.deleteIntent).getSavedIntent());
    assertEquals(Arrays.asList("dismissed:b"), events);
  }

  @Test
  public void anEndedContentWhoseTimeHasPassedIsShownAtOnce() throws Exception {
    long endAt = System.currentTimeMillis() - MINUTE;
    LiveUpdatesBridge.startOrUpdate(
        "late",
        "{\"title\":\"Order\",\"endAt\":" + seconds(endAt)
            + ",\"endedContent\":{\"title\":\"Delivered\"}}");
    Notification n = shown("late");
    assertEquals("Delivered", n.extras.getString(Notification.EXTRA_TITLE));
    assertEquals(0, n.flags & Notification.FLAG_ONGOING_EVENT);
    assertTrue(shadowOf(alarms).getScheduledAlarms().isEmpty());
    assertEquals(Arrays.asList("started:late", "stale:late"), events);
    assertTrue(Arrays.asList(LiveUpdatesBridge.activeIds()).contains("late"));
  }

  @Test
  public void removeAtEndInThePastDoesNotPost() throws Exception {
    long endAt = System.currentTimeMillis() - MINUTE;
    // An id no other test posted (recent posts are tracked across tests).
    LiveUpdatesBridge.startOrUpdate(
        "past", "{\"title\":\"Order\",\"endAt\":" + seconds(endAt) + ",\"removeAtEnd\":true}");
    assertNull(shown("past"));
    assertEquals(new ArrayList<String>(), events);
  }

  @Test
  public void updatesEndsAndEndAllCancelTheEndAlarm() throws Exception {
    long endAt = System.currentTimeMillis() + 20 * MINUTE;
    String withEnd =
        "{\"title\":\"Order\",\"endAt\":" + seconds(endAt)
            + ",\"endedContent\":{\"title\":\"Delivered\"}}";
    // Updated without endAt.
    LiveUpdatesBridge.startOrUpdate("a", withEnd);
    assertEquals(1, shadowOf(alarms).getScheduledAlarms().size());
    LiveUpdatesBridge.update("a", "{\"title\":\"Order\"}");
    assertTrue(shadowOf(alarms).getScheduledAlarms().isEmpty());
    // Updated with another endAt: one alarm, at the new time.
    LiveUpdatesBridge.update("a", withEnd);
    long later = endAt + 10 * MINUTE;
    LiveUpdatesBridge.update(
        "a",
        "{\"title\":\"Order\",\"endAt\":" + seconds(later)
            + ",\"endedContent\":{\"title\":\"Delivered\"}}");
    assertEquals(1, shadowOf(alarms).getScheduledAlarms().size());
    assertEquals(later, shadowOf(alarms).peekNextScheduledAlarm().getTriggerAtMs());
    // Ended.
    LiveUpdatesBridge.end("a", null, 0);
    assertTrue(shadowOf(alarms).getScheduledAlarms().isEmpty());
    // endAll.
    LiveUpdatesBridge.startOrUpdate("b", withEnd);
    LiveUpdatesBridge.endAll();
    assertTrue(shadowOf(alarms).getScheduledAlarms().isEmpty());
    assertEquals("{}", prefs().getString("ends", "{}"));
  }

  @Test
  public void anUpdateThatWasDismissedIsNotBroughtBackByItsEndAlarm() throws Exception {
    long endAt = System.currentTimeMillis() + 20 * MINUTE;
    LiveUpdatesBridge.startOrUpdate(
        "order",
        "{\"title\":\"Order\",\"endAt\":" + seconds(endAt)
            + ",\"endedContent\":{\"title\":\"Delivered\"}}");
    Intent alarm = shadowOf(shadowOf(alarms).peekNextScheduledAlarm().operation).getSavedIntent();
    // Swiped away by the user.
    manager.cancel(LiveUpdatesBridge.TAG_PREFIX + "order", LiveUpdatesBridge.NOTIFICATION_ID);
    LiveUpdatesBridge.markDismissed(app, "order");
    assertTrue(shadowOf(alarms).getScheduledAlarms().isEmpty());
    new LiveUpdatesScheduleReceiver().onReceive(app, alarm);
    assertNull(shown("order"));
  }

  @Test
  public void withoutExactAlarmsTheEndedContentUsesAWindow() throws Exception {
    ShadowAlarmManager.setCanScheduleExactAlarms(false);
    long endAt = System.currentTimeMillis() + 20 * MINUTE;
    LiveUpdatesBridge.startOrUpdate(
        "order",
        "{\"title\":\"Order\",\"endAt\":" + seconds(endAt)
            + ",\"endedContent\":{\"title\":\"Delivered\"}}");
    assertEquals(10 * MINUTE, shadowOf(alarms).peekNextScheduledAlarm().getWindowLengthMs());
  }

  @Test
  public void bootSetsEndAlarmsAgain() throws Exception {
    long endAt = System.currentTimeMillis() + 20 * MINUTE;
    LiveUpdatesBridge.startOrUpdate(
        "order",
        "{\"title\":\"Order\",\"endAt\":" + seconds(endAt)
            + ",\"endedContent\":{\"title\":\"Delivered\"}}");
    ShadowAlarmManager.reset();
    ShadowAlarmManager.setCanScheduleExactAlarms(true);
    new LiveUpdatesScheduleReceiver().onReceive(app, new Intent(Intent.ACTION_BOOT_COMPLETED));
    assertEquals(endAt, shadowOf(alarms).peekNextScheduledAlarm().getTriggerAtMs());
  }

  @Test
  public void remotePayloadsUseEndAtAndMaxDurationToo() throws Exception {
    long endAt = System.currentTimeMillis() + 20 * MINUTE;
    JSONObject data =
        new JSONObject()
            .put("live_updates_event", "start")
            .put("live_updates_id", "remote")
            .put(
                "live_updates_content",
                "{\"title\":\"Remote\",\"endAt\":" + seconds(endAt)
                    + ",\"endedContent\":{\"title\":\"Done\"}}");
    assertTrue(LiveUpdatesBridge.handleRemotePayload(data.toString()));
    assertAbout(8 * HOUR, shown("remote").getTimeoutAfter());
    fireEndAlarm();
    assertEquals("Done", shown("remote").extras.getString(Notification.EXTRA_TITLE));
  }

  @Test
  @Config(sdk = 24)
  public void endedContentWorksOnTheMinimumSdk() throws Exception {
    long endAt = System.currentTimeMillis() + 20 * MINUTE;
    LiveUpdatesBridge.startOrUpdate(
        "order",
        "{\"title\":\"Order\",\"endAt\":" + seconds(endAt)
            + ",\"endedContent\":{\"title\":\"Delivered\"}}");
    fireEndAlarm();
    assertEquals("Delivered", shown("order").extras.getString(Notification.EXTRA_TITLE));
  }

  @Test
  public void theEndedIconAndImageReplaceTheContentOnes() throws Exception {
    JSONObject content =
        new JSONObject(
            "{\"title\":\"Order\",\"icon\":{\"native\":\"ic_a\"},"
                + "\"androidSmallIcon\":{\"native\":\"ic_small\"},\"image\":\"lu_a.png\","
                + "\"progress\":0.5,\"channelId\":\"c\",\"maxDurationMillis\":0}");
    JSONObject withBoth =
        LiveUpdatesBridge.staleContent(
            content,
            new JSONObject(
                "{\"title\":\"Done\",\"icon\":{\"native\":\"ic_done\"},\"image\":\"lu_b.png\"}"));
    assertEquals("ic_done", withBoth.getJSONObject("icon").getString("native"));
    assertEquals("ic_small", withBoth.getJSONObject("androidSmallIcon").getString("native"));
    assertEquals("lu_b.png", withBoth.getString("image"));
    assertEquals("c", withBoth.getString("channelId"));
    assertEquals(0, withBoth.getLong("maxDurationMillis"));
    assertFalse(withBoth.has("progress"));
    JSONObject plain =
        LiveUpdatesBridge.staleContent(content, new JSONObject("{\"title\":\"Done\"}"));
    assertEquals("ic_a", plain.getJSONObject("icon").getString("native"));
    // No ended image: no image.
    assertFalse(plain.has("image"));
  }

  @Test
  public void aStaleUpdateThatTimedOutStartsFreshWithTheKey() throws Exception {
    long endAt = System.currentTimeMillis() + 20 * MINUTE;
    LiveUpdatesBridge.startOrUpdate(
        "fresh",
        "{\"title\":\"Order\",\"endAt\":" + seconds(endAt)
            + ",\"endedContent\":{\"title\":\"Delivered\"}}");
    fireEndAlarm();
    // maxDuration removed it (the system's timeout).
    manager.cancel(LiveUpdatesBridge.TAG_PREFIX + "fresh", LiveUpdatesBridge.NOTIFICATION_ID);
    LiveUpdatesBridge.timedOut(app, "fresh");
    android.os.SystemClock.sleep(3100); // Past the tracking of recent posts.
    events.clear();
    LiveUpdatesBridge.startOrUpdate("fresh", "{\"title\":\"Next order\"}");
    // A new update: started, not "active again".
    assertEquals(Arrays.asList("started:fresh"), events);
  }

  @Test
  public void malformedEndKeysInRemotePayloadsFailSafe() throws Exception {
    JSONObject data =
        new JSONObject()
            .put("live_updates_event", "start")
            .put("live_updates_id", "bad")
            .put(
                "live_updates_content",
                "{\"title\":\"Remote\",\"endAt\":\"soon\",\"endedContent\":\"done\","
                    + "\"maxDurationMillis\":\"long\",\"removeAtEnd\":\"yes\"}");
    assertTrue(LiveUpdatesBridge.handleRemotePayload(data.toString()));
    Notification n = shown("bad");
    assertNotNull(n);
    assertEquals("Remote", n.extras.getString(Notification.EXTRA_TITLE));
    // The default limit; no end alarm.
    assertAbout(8 * HOUR, n.getTimeoutAfter());
    assertTrue(shadowOf(alarms).getScheduledAlarms().isEmpty());
    // Ended content without a title is ignored too.
    data.put("live_updates_id", "bad2")
        .put(
            "live_updates_content",
            "{\"title\":\"Remote\",\"endAt\":" + seconds(System.currentTimeMillis() + MINUTE)
                + ",\"endedContent\":{\"body\":\"x\",\"icon\":3,\"image\":\"../x\"}}");
    assertTrue(LiveUpdatesBridge.handleRemotePayload(data.toString()));
    fireEndAlarm();
    assertEquals("Remote", shown("bad2").extras.getString(Notification.EXTRA_TITLE));
  }
}
