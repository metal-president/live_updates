package com.ttechapp.live_updates;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;
import static org.robolectric.Shadows.shadowOf;

import android.app.Application;
import android.app.NotificationManager;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.provider.Settings;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 36)
public class LiveUpdatesSettingsTest {
  private final Application app = RuntimeEnvironment.getApplication();

  @Before
  public void setUp() {
    app.getApplicationInfo().icon = android.R.drawable.ic_dialog_info;
    LiveUpdatesBridge.engineAttached(app);
  }

  @After
  public void tearDown() {
    LiveUpdatesBridge.engineDetached(1);
  }

  @Test
  public void openSettingsOpensTheAppNotificationSettings() {
    assertTrue(LiveUpdatesBridge.openSettings());
    Intent intent = shadowOf(app).getNextStartedActivity();
    assertNotNull(intent);
    assertEquals(Settings.ACTION_APP_NOTIFICATION_SETTINGS, intent.getAction());
    assertEquals(app.getPackageName(), intent.getStringExtra(Settings.EXTRA_APP_PACKAGE));
    // Without an activity, from the application context.
    assertTrue((intent.getFlags() & Intent.FLAG_ACTIVITY_NEW_TASK) != 0);
  }

  @Test
  @Config(sdk = 24)
  public void belowAndroid8OpenSettingsOpensTheAppDetails() {
    assertTrue(LiveUpdatesBridge.openSettings());
    Intent intent = shadowOf(app).getNextStartedActivity();
    assertNotNull(intent);
    assertEquals(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, intent.getAction());
    assertEquals(Uri.parse("package:" + app.getPackageName()), intent.getData());
  }

  @Test
  public void openSettingsIsFalseWithoutAMatchingScreen() {
    shadowOf(app).checkActivities(true);
    assertFalse(LiveUpdatesBridge.openSettings());
  }

  @Test
  public void turnedOffNotificationsAreReportedAsDisabled() throws Exception {
    NotificationManager manager =
        (NotificationManager) app.getSystemService(Context.NOTIFICATION_SERVICE);
    shadowOf(manager).setNotificationsEnabled(false);
    try {
      LiveUpdatesBridge.start("{\"title\":\"A\"}");
      fail("start must fail");
    } catch (IllegalStateException e) {
      assertEquals("disabled", LiveUpdatesBridge.failureReason(e));
      // The message Dart shows is unchanged.
      assertEquals(
          "java.lang.IllegalStateException: Notifications are turned off for this app",
          e.toString());
    } finally {
      shadowOf(manager).setNotificationsEnabled(true);
    }
  }

  @Test
  public void otherFailuresAreReportedAsOther() {
    try {
      LiveUpdatesBridge.update("no-such-id", "{\"title\":\"A\"}");
      fail("update must fail");
    } catch (Exception e) {
      assertEquals("other", LiveUpdatesBridge.failureReason(e));
    }
  }
}
