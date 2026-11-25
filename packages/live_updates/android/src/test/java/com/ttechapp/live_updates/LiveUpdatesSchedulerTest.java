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
import android.service.notification.StatusBarNotification;
import org.json.JSONArray;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;
import org.robolectric.shadows.ShadowAlarmManager;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 36)
public class LiveUpdatesSchedulerTest {
  private static final long MINUTE = 60_000;
  private final Application app = RuntimeEnvironment.getApplication();
  private NotificationManager manager;
  private AlarmManager alarms;

  @Before
  public void setUp() {
    app.getApplicationInfo().icon = android.R.drawable.ic_dialog_info;
    manager = (NotificationManager) app.getSystemService(Context.NOTIFICATION_SERVICE);
    alarms = (AlarmManager) app.getSystemService(Context.ALARM_SERVICE);
    ShadowAlarmManager.setCanScheduleExactAlarms(true);
    LiveUpdatesBridge.engineAttached(app);
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

  private ShadowAlarmManager.ScheduledAlarm onlyAlarm() {
    assertEquals(1, shadowOf(alarms).getScheduledAlarms().size());
    return shadowOf(alarms).peekNextScheduledAlarm();
  }

  /**
   * Delivers an alarm as the system would at its time: its broadcast to the receiver, once the
   * schedule is due (the stored time is moved to the past, as the clock cannot be).
   */
  private void fire(ShadowAlarmManager.ScheduledAlarm alarm) throws Exception {
    Intent intent = shadowOf(alarm.operation).getSavedIntent();
    makeDue(intent.getStringExtra(LiveUpdatesScheduler.EXTRA_KEY));
    new LiveUpdatesScheduleReceiver().onReceive(app, intent);
  }

  private void makeDue(String key) throws Exception {
    android.content.SharedPreferences prefs =
        app.getSharedPreferences("com.ttechapp.live_updates", Context.MODE_PRIVATE);
    org.json.JSONObject all = new org.json.JSONObject(prefs.getString("schedules", "{}"));
    if (!all.has(key)) return;
    all.getJSONObject(key).put("at", System.currentTimeMillis() - 1);
    prefs.edit().putString("schedules", all.toString()).commit();
  }

  private static String keys(String json) throws Exception {
    JSONArray a = new JSONArray(json);
    StringBuilder out = new StringBuilder();
    for (int i = 0; i < a.length(); i++) out.append(a.getJSONObject(i).getString("key")).append(' ');
    return out.toString().trim();
  }

  @Test
  public void aFutureScheduleSetsAnExactAlarmAndShowsNothingYet() throws Exception {
    long at = System.currentTimeMillis() + 5 * MINUTE;
    LiveUpdatesBridge.schedule("order", "{\"title\":\"Later\"}", at, true, 10 * MINUTE);
    ShadowAlarmManager.ScheduledAlarm alarm = onlyAlarm();
    assertEquals(AlarmManager.RTC_WAKEUP, alarm.type);
    assertEquals(at, alarm.getTriggerAtMs());
    assertTrue(alarm.isAllowWhileIdle());
    assertEquals(ShadowAlarmManager.WINDOW_EXACT, alarm.getWindowLengthMs());
    assertNull(shown("order"));
    assertEquals("order", keys(LiveUpdatesBridge.scheduledJson()));
    JSONArray list = new JSONArray(LiveUpdatesBridge.scheduledJson());
    assertEquals(at / 1000.0, list.getJSONObject(0).getDouble("at"), 0.001);
  }

  @Test
  public void theAlarmPostsTheContentWithTheKeyAndForgetsTheSchedule() throws Exception {
    LiveUpdatesBridge.schedule(
        "order", "{\"title\":\"Ready\"}", System.currentTimeMillis() + MINUTE, true, 0);
    ShadowAlarmManager.ScheduledAlarm alarm = onlyAlarm();
    // The process may have been started by the alarm: no engine attached.
    LiveUpdatesBridge.context = null;
    fire(alarm);
    Notification n = shown("order");
    assertNotNull(n);
    assertEquals("Ready", n.extras.getString(Notification.EXTRA_TITLE));
    assertEquals("order", LiveUpdatesBridge.keyForId("order"));
    assertEquals("[]", LiveUpdatesBridge.scheduledJson());
    // A second delivery of the same alarm does nothing.
    manager.cancelAll();
    fire(alarm);
    assertNull(shown("order"));
  }

  @Test
  public void whenTheTimeComesARunningUpdateWithTheKeyIsUpdated() throws Exception {
    LiveUpdatesBridge.startOrUpdate("order", "{\"title\":\"Now\"}");
    LiveUpdatesBridge.schedule(
        "order", "{\"title\":\"Later\"}", System.currentTimeMillis() + MINUTE, true, 0);
    assertEquals("Now", shown("order").extras.getString(Notification.EXTRA_TITLE));
    fire(onlyAlarm());
    assertEquals(1, manager.getActiveNotifications().length);
    assertEquals("Later", shown("order").extras.getString(Notification.EXTRA_TITLE));
  }

  @Test
  public void aTimeThatIsNotInTheFutureShowsItNow() throws Exception {
    LiveUpdatesBridge.schedule(
        "order", "{\"title\":\"Late\"}", System.currentTimeMillis() - MINUTE, true, 0);
    assertEquals("Late", shown("order").extras.getString(Notification.EXTRA_TITLE));
    assertTrue(shadowOf(alarms).getScheduledAlarms().isEmpty());
    assertEquals("[]", LiveUpdatesBridge.scheduledJson());
  }

  @Test
  public void withoutExactAlarmPermissionItUsesTheWindow() throws Exception {
    ShadowAlarmManager.setCanScheduleExactAlarms(false);
    assertFalse(LiveUpdatesBridge.canScheduleExactly());
    long at = System.currentTimeMillis() + 5 * MINUTE;
    LiveUpdatesBridge.schedule("order", "{\"title\":\"Later\"}", at, true, 15 * MINUTE);
    ShadowAlarmManager.ScheduledAlarm alarm = onlyAlarm();
    assertEquals(at, alarm.getTriggerAtMs());
    assertEquals(15 * MINUTE, alarm.getWindowLengthMs());
    assertFalse(alarm.isAllowWhileIdle());
  }

  @Test
  public void exactFalseUsesTheWindowEvenWhenAllowed() throws Exception {
    LiveUpdatesBridge.schedule(
        "order", "{\"title\":\"Later\"}", System.currentTimeMillis() + MINUTE, false, 2 * MINUTE);
    assertEquals(2 * MINUTE, onlyAlarm().getWindowLengthMs());
  }

  @Test
  public void schedulingTheSameKeyAgainReplacesTheAlarm() throws Exception {
    long later = System.currentTimeMillis() + 10 * MINUTE;
    LiveUpdatesBridge.schedule(
        "order", "{\"title\":\"A\"}", System.currentTimeMillis() + MINUTE, true, 0);
    LiveUpdatesBridge.schedule("order", "{\"title\":\"B\"}", later, true, 0);
    assertEquals(later, onlyAlarm().getTriggerAtMs());
    fire(onlyAlarm());
    assertEquals("B", shown("order").extras.getString(Notification.EXTRA_TITLE));
  }

  @Test
  public void keysHaveTheirOwnAlarms() throws Exception {
    long now = System.currentTimeMillis();
    LiveUpdatesBridge.schedule("a", "{\"title\":\"A\"}", now + MINUTE, true, 0);
    LiveUpdatesBridge.schedule("b", "{\"title\":\"B\"}", now + 2 * MINUTE, true, 0);
    assertEquals(2, shadowOf(alarms).getScheduledAlarms().size());
    LiveUpdatesBridge.cancelScheduled("a");
    assertEquals(now + 2 * MINUTE, onlyAlarm().getTriggerAtMs());
    assertEquals("b", keys(LiveUpdatesBridge.scheduledJson()));
  }

  @Test
  public void cancelRemovesTheAlarmAndTheSchedule() throws Exception {
    LiveUpdatesBridge.schedule(
        "order", "{\"title\":\"A\"}", System.currentTimeMillis() + MINUTE, true, 0);
    Intent saved = shadowOf(onlyAlarm().operation).getSavedIntent();
    LiveUpdatesBridge.cancelScheduled("order");
    assertTrue(shadowOf(alarms).getScheduledAlarms().isEmpty());
    assertEquals("[]", LiveUpdatesBridge.scheduledJson());
    // An alarm already on its way finds nothing to show.
    new LiveUpdatesScheduleReceiver().onReceive(app, saved);
    assertNull(shown("order"));
    LiveUpdatesBridge.cancelScheduled("unknown"); // No error.
  }

  @Test
  public void rescheduleMovesTheTimeAndKeepsOrReplacesTheContent() throws Exception {
    long now = System.currentTimeMillis();
    LiveUpdatesBridge.schedule("order", "{\"title\":\"A\"}", now + MINUTE, true, 0);
    LiveUpdatesBridge.reschedule("order", null, now + 3 * MINUTE);
    assertEquals(now + 3 * MINUTE, onlyAlarm().getTriggerAtMs());
    LiveUpdatesBridge.reschedule("order", "{\"title\":\"B\"}", now + 4 * MINUTE);
    assertEquals(now + 4 * MINUTE, onlyAlarm().getTriggerAtMs());
    fire(onlyAlarm());
    assertEquals("B", shown("order").extras.getString(Notification.EXTRA_TITLE));
  }

  @Test
  public void anAlarmBeforeTheStoredTimeSetsItAgain() throws Exception {
    long at = System.currentTimeMillis() + 10 * MINUTE;
    LiveUpdatesBridge.schedule("order", "{\"title\":\"A\"}", at, true, 0);
    // An alarm delivered long before the schedule's time (an outdated one).
    new LiveUpdatesScheduleReceiver()
        .onReceive(app, shadowOf(onlyAlarm().operation).getSavedIntent());
    assertNull(shown("order"));
    assertEquals(at, onlyAlarm().getTriggerAtMs());
  }

  @Test(expected = IllegalStateException.class)
  public void rescheduleWithoutAScheduleThrows() throws Exception {
    LiveUpdatesBridge.reschedule("order", null, System.currentTimeMillis() + MINUTE);
  }

  @Test
  public void endAllKeepsSchedules() throws Exception {
    LiveUpdatesBridge.schedule(
        "order", "{\"title\":\"A\"}", System.currentTimeMillis() + MINUTE, true, 0);
    LiveUpdatesBridge.endAll();
    assertEquals("order", keys(LiveUpdatesBridge.scheduledJson()));
    assertEquals(1, shadowOf(alarms).getScheduledAlarms().size());
  }

  @Test
  public void bootSetsTheAlarmsAgainAndShowsOverdueOnes() throws Exception {
    long now = System.currentTimeMillis();
    LiveUpdatesBridge.schedule("future", "{\"title\":\"F\"}", now + 5 * MINUTE, true, 0);
    LiveUpdatesBridge.schedule("overdue", "{\"title\":\"O\"}", now + MINUTE, true, 0);
    // A reboot drops every alarm; one schedule is overdue by now.
    ShadowAlarmManager.reset();
    ShadowAlarmManager.setCanScheduleExactAlarms(true);
    alarms = (AlarmManager) app.getSystemService(Context.ALARM_SERVICE);
    makeDue("overdue");
    LiveUpdatesBridge.context = null;

    new LiveUpdatesScheduleReceiver().onReceive(app, new Intent(Intent.ACTION_BOOT_COMPLETED));

    assertEquals("O", shown("overdue").extras.getString(Notification.EXTRA_TITLE));
    assertNull(shown("future"));
    assertEquals(now + 5 * MINUTE, onlyAlarm().getTriggerAtMs());
    assertEquals("future", keys(LiveUpdatesBridge.scheduledJson()));
  }

  @Test
  public void aGrantedExactAlarmPermissionSwitchesToExactAlarms() throws Exception {
    ShadowAlarmManager.setCanScheduleExactAlarms(false);
    long at = System.currentTimeMillis() + 5 * MINUTE;
    LiveUpdatesBridge.schedule("order", "{\"title\":\"A\"}", at, true, 10 * MINUTE);
    assertEquals(10 * MINUTE, onlyAlarm().getWindowLengthMs());
    ShadowAlarmManager.setCanScheduleExactAlarms(true);
    new LiveUpdatesScheduleReceiver()
        .onReceive(
            app, new Intent(AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED));
    assertEquals(ShadowAlarmManager.WINDOW_EXACT, onlyAlarm().getWindowLengthMs());
  }

  @Test
  public void otherBroadcastsAreIgnored() throws Exception {
    LiveUpdatesBridge.schedule(
        "order", "{\"title\":\"A\"}", System.currentTimeMillis() + MINUTE, true, 0);
    new LiveUpdatesScheduleReceiver().onReceive(app, new Intent("other"));
    // A fire intent without a key.
    new LiveUpdatesScheduleReceiver().onReceive(app, new Intent(LiveUpdatesScheduler.ACTION_FIRE));
    assertNull(shown("order"));
    assertEquals(1, shadowOf(alarms).getScheduledAlarms().size());
  }

  @Test(expected = org.json.JSONException.class)
  public void malformedContentIsRejectedWhenScheduling() throws Exception {
    LiveUpdatesBridge.schedule("order", "{", System.currentTimeMillis() + MINUTE, true, 0);
  }

  @Test
  public void openExactAlarmSettingsNeedsTheDeclaredPermission() {
    // The test app does not declare SCHEDULE_EXACT_ALARM.
    assertFalse(LiveUpdatesBridge.openExactAlarmSettings());
  }

  @Test
  public void canScheduleFollowsNotificationSupport() {
    shadowOf(manager).setNotificationsEnabled(true);
    assertTrue(LiveUpdatesBridge.canSchedule());
    shadowOf(manager).setNotificationsEnabled(false);
    assertFalse(LiveUpdatesBridge.canSchedule());
  }

  @Test
  @Config(sdk = 30)
  public void belowAndroid12AlarmsAreAlwaysExact() throws Exception {
    assertTrue(LiveUpdatesBridge.canScheduleExactly());
    assertFalse(LiveUpdatesBridge.openExactAlarmSettings());
    long at = System.currentTimeMillis() + MINUTE;
    LiveUpdatesBridge.schedule("order", "{\"title\":\"A\"}", at, true, 0);
    assertEquals(ShadowAlarmManager.WINDOW_EXACT, onlyAlarm().getWindowLengthMs());
    fire(onlyAlarm());
    assertNotNull(shown("order"));
  }

  @Test
  @Config(sdk = 24)
  public void worksOnTheMinimumSdk() throws Exception {
    LiveUpdatesBridge.schedule(
        "order", "{\"title\":\"A\"}", System.currentTimeMillis() + MINUTE, true, 0);
    fire(onlyAlarm());
    assertNotNull(shown("order"));
  }
}
