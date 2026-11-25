package com.ttechapp.live_updates;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.robolectric.Shadows.shadowOf;

import android.app.Application;
import android.app.Notification;
import android.app.NotificationManager;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.service.notification.StatusBarNotification;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;

/**
 * Android 7 to 15 (below the API 36 features): every post must fall back to a
 * regular ongoing notification without calling newer APIs.
 */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = {24, 26, 33, 35})
public class LiveUpdatesFallbackTest {
  private final Application app = RuntimeEnvironment.getApplication();
  private NotificationManager manager;

  @Before
  public void setUp() {
    app.getApplicationInfo().icon = android.R.drawable.ic_dialog_info;
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
  public void tearDown() throws Exception {
    LiveUpdatesBridge.endAll();
    LiveUpdatesBridge.engineDetached(1);
  }

  private Notification shown(String id) {
    for (StatusBarNotification n : manager.getActiveNotifications()) {
      if ((LiveUpdatesBridge.TAG_PREFIX + id).equals(n.getTag())) return n.getNotification();
    }
    return null;
  }

  @Test
  public void publicContentBecomesThePublicVersion() throws Exception {
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"Order #1234\",\"progress\":0.5,\"timerEnd\":1893456000,"
                + "\"journey\":{\"from\":\"A\",\"to\":\"B\"},"
                + "\"actions\":[{\"id\":\"call\",\"title\":\"Call\"}],"
                + "\"publicContent\":{\"title\":\"Delivery\",\"body\":\"On the way\"}}");
    Notification n = shown(id);
    assertEquals(Notification.VISIBILITY_PRIVATE, n.visibility);
    Notification p = n.publicVersion;
    assertNotNull(p);
    assertEquals("Delivery", p.extras.getString(Notification.EXTRA_TITLE));
    assertEquals("On the way", p.extras.getCharSequence(Notification.EXTRA_TEXT).toString());
    assertNull(p.actions);
    assertNull(p.extras.getCharSequence(Notification.EXTRA_BIG_TEXT));
    assertEquals(50, p.extras.getInt(Notification.EXTRA_PROGRESS));
    assertEquals(100, p.extras.getInt(Notification.EXTRA_PROGRESS_MAX));
    assertTrue(p.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER));
  }

  @Test
  public void secretVisibilityIsApplied() throws Exception {
    String id =
        LiveUpdatesBridge.start("{\"title\":\"Order\",\"androidLockScreenVisibility\":\"secret\"}");
    assertEquals(Notification.VISIBILITY_SECRET, shown(id).visibility);
  }

  @Test
  public void liveUpdateModeFallsBackToAnOngoingProgressBar() throws Exception {
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"Order\",\"body\":\"On the way\",\"progress\":0.5,"
                + "\"bodySemanticStyle\":\"safe\",\"shortCriticalText\":\"5 min\","
                + "\"progressSegments\":[{\"length\":1,\"semanticStyle\":\"info\"}],"
                + "\"progressPoints\":[{\"position\":0.5}],"
                + "\"metrics\":[{\"label\":\"ETA\",\"type\":\"integer\",\"value\":5}]}");
    Notification n = shown(id);
    assertNotNull(n);
    assertTrue((n.flags & Notification.FLAG_ONGOING_EVENT) != 0);
    assertEquals(100, n.extras.getInt(Notification.EXTRA_PROGRESS_MAX));
    assertEquals(50, n.extras.getInt(Notification.EXTRA_PROGRESS));
    assertFalse(n.extras.containsKey("android.requestPromotedOngoing"));
    assertEquals(
        "android.app.Notification$BigTextStyle",
        n.extras.getString(Notification.EXTRA_TEMPLATE));
    // Semantic styles are Android 17+: the body stays plain text.
    assertEquals("On the way", n.extras.getCharSequence(Notification.EXTRA_TEXT).toString());
    assertEquals(
        "On the way\nETA: 5", n.extras.getCharSequence(Notification.EXTRA_BIG_TEXT).toString());
    assertTrue(Arrays.asList(LiveUpdatesBridge.activeIds()).contains(id));
  }

  @Test
  public void stepsUseTheProgressBar() throws Exception {
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"Order\",\"steps\":{\"labels\":[\"Placed\",\"Preparing\",\"On the way\"],"
                + "\"current\":1}}");
    Notification n = shown(id);
    assertEquals(2, n.extras.getInt(Notification.EXTRA_PROGRESS_MAX));
    assertEquals(1, n.extras.getInt(Notification.EXTRA_PROGRESS));
    assertEquals("2/3 Preparing", n.extras.getCharSequence(Notification.EXTRA_TEXT).toString());
  }

  @Test
  public void promotionIsNeverAvailable() throws Exception {
    assertFalse(LiveUpdatesBridge.canPostPromotedNotifications());
    // Even with Notification.FLAG_PROMOTED_ONGOING set, which older versions
    // never do.
    Notification n =
        new Notification.Builder(app).setSmallIcon(android.R.drawable.ic_dialog_info).build();
    n.flags |= 0x00040000;
    manager.notify(LiveUpdatesBridge.TAG_PREFIX + "promoted", LiveUpdatesBridge.NOTIFICATION_ID, n);
    assertFalse(LiveUpdatesBridge.isPromoted("promoted"));
  }

  @Test
  public void channelsAreUsedFromAndroid8() throws Exception {
    String id =
        LiveUpdatesBridge.start("{\"title\":\"A\",\"channelId\":\"rides\",\"channelName\":\"Rides\"}");
    Notification n = shown(id);
    assertNotNull(n);
    if (Build.VERSION.SDK_INT >= 26) {
      assertEquals("rides", n.getChannelId());
      assertEquals("Rides", manager.getNotificationChannel("rides").getName().toString());
    }
  }

  @Test
  public void timeoutIsSetFromAndroid8() throws Exception {
    String id = LiveUpdatesBridge.start("{\"title\":\"A\",\"timeoutAfterMillis\":3600000}");
    Notification n = shown(id);
    assertNotNull(n);
    if (Build.VERSION.SDK_INT >= 26) assertEquals(3_600_000, n.getTimeoutAfter());
  }

  @Test
  public void endWithFinalContentKeepsARegularNotification() throws Exception {
    String id = LiveUpdatesBridge.start("{\"title\":\"A\",\"progress\":0.2}");
    LiveUpdatesBridge.end(id, "{\"title\":\"Delivered\"}", 300);
    Notification n = shown(id);
    assertNotNull(n);
    assertEquals("Delivered", n.extras.getString(Notification.EXTRA_TITLE));
    assertEquals(0, n.flags & Notification.FLAG_ONGOING_EVENT);
    assertFalse(n.extras.containsKey("android.requestPromotedOngoing"));
    if (Build.VERSION.SDK_INT >= 26) assertEquals(300_000, n.getTimeoutAfter());
    assertFalse(Arrays.asList(LiveUpdatesBridge.activeIds()).contains(id));
  }

  @Test
  public void buttonsAndTimersWork() throws Exception {
    long end = System.currentTimeMillis() + 600_000;
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"A\",\"timerEnd\":" + (end / 1000.0) + ","
                + "\"actions\":[{\"id\":\"cancel\",\"title\":\"Cancel\",\"requiresUnlock\":true},"
                + "{\"id\":\"track\",\"title\":\"Track\",\"opensApp\":true}]}");
    Notification n = shown(id);
    assertEquals(2, n.actions.length);
    assertEquals("Cancel", n.actions[0].title.toString());
    if (Build.VERSION.SDK_INT >= 31) assertTrue(n.actions[0].isAuthenticationRequired());
    assertTrue(n.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER));
    assertTrue(n.extras.getBoolean(Notification.EXTRA_CHRONOMETER_COUNT_DOWN));
  }

  @Test
  public void updatesAndRemotePayloadsWork() throws Exception {
    String id = LiveUpdatesBridge.start("{\"title\":\"A\"}");
    LiveUpdatesBridge.update(id, "{\"title\":\"B\",\"progress\":0.9}");
    assertEquals("B", shown(id).extras.getString(Notification.EXTRA_TITLE));
    assertTrue(
        LiveUpdatesBridge.handleRemotePayload(
            "{\"live_updates_event\":\"start\",\"live_updates_id\":\"r1\","
                + "\"live_updates_content\":\"{\\\"title\\\":\\\"Remote\\\"}\"}"));
    assertEquals("Remote", shown("r1").extras.getString(Notification.EXTRA_TITLE));
    LiveUpdatesBridge.endAll();
    assertNull(shown(id));
    assertNull(shown("r1"));
  }

  @Test
  public void permissionNeedsNoPromptBeforeAndroid13() {
    if (Build.VERSION.SDK_INT >= 33) return;
    List<Boolean> results = new ArrayList<>();
    LiveUpdatesBridge.requestPermission(results::add);
    assertEquals(Arrays.asList(true), results);
  }
}
