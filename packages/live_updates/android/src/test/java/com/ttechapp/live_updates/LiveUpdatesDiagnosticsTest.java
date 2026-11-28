package com.ttechapp.live_updates;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.robolectric.Shadows.shadowOf;

import android.app.Application;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.Context;
import android.os.Bundle;
import org.json.JSONObject;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 36)
public class LiveUpdatesDiagnosticsTest {
  private final Application app = RuntimeEnvironment.getApplication();

  private NotificationManager manager() {
    return (NotificationManager) app.getSystemService(Context.NOTIFICATION_SERVICE);
  }

  @Before
  public void setUp() {
    app.getApplicationInfo().icon = android.R.drawable.ic_dialog_info;
    LiveUpdatesBridge.engineAttached(app);
  }

  @After
  public void tearDown() {
    LiveUpdatesBridge.engineDetached(1);
    app.getApplicationInfo().metaData = null;
  }

  @Test
  public void reportsTheSetup() throws Exception {
    JSONObject facts = new JSONObject(LiveUpdatesBridge.diagnosticsJson("live_updates"));
    assertTrue(facts.getBoolean("attached"));
    assertEquals(36, facts.getInt("sdk"));
    assertTrue(facts.getBoolean("notificationsEnabled"));
    assertTrue(facts.has("postNotificationsGranted"));
    // Not created before the first live update.
    assertFalse(facts.getJSONObject("channel").getBoolean("exists"));
    // The plugin's manifest declares it; the test app merges it.
    assertTrue(facts.has("promotedDeclared"));
    assertTrue(facts.has("canPostPromoted"));
    assertTrue(facts.has("exactAlarmDeclared"));
    assertTrue(facts.has("canScheduleExactly"));
    assertEquals("unset", facts.getString("defaultIcon"));
  }

  @Test
  public void reportsTurnedOffNotificationsAndChannels() throws Exception {
    shadowOf(manager()).setNotificationsEnabled(false);
    manager()
        .createNotificationChannel(
            new NotificationChannel("orders", "Orders", NotificationManager.IMPORTANCE_NONE));
    JSONObject facts = new JSONObject(LiveUpdatesBridge.diagnosticsJson("orders"));
    assertFalse(facts.getBoolean("notificationsEnabled"));
    JSONObject channel = facts.getJSONObject("channel");
    assertTrue(channel.getBoolean("exists"));
    assertEquals(NotificationManager.IMPORTANCE_NONE, channel.getInt("importance"));
    assertFalse(channel.getBoolean("groupBlocked"));
  }

  @Test
  public void reportsTheDefaultIconMetaData() throws Exception {
    Bundle meta = new Bundle();
    meta.putInt(LiveUpdatesBridge.DEFAULT_ICON_META, android.R.drawable.ic_dialog_alert);
    app.getApplicationInfo().metaData = meta;
    assertEquals("valid", LiveUpdatesBridge.defaultIconState(app));
    // A string resource cannot be a small icon.
    meta.putInt(LiveUpdatesBridge.DEFAULT_ICON_META, android.R.string.ok);
    assertEquals("invalid", LiveUpdatesBridge.defaultIconState(app));
  }

  @Test
  @Config(sdk = 24)
  public void olderVersionsHaveNoChannelOrPermission() throws Exception {
    JSONObject facts = new JSONObject(LiveUpdatesBridge.diagnosticsJson("live_updates"));
    assertEquals(24, facts.getInt("sdk"));
    assertFalse(facts.has("channel"));
    assertFalse(facts.has("postNotificationsGranted"));
    assertFalse(facts.getBoolean("canPostPromoted"));
    assertTrue(facts.getBoolean("canScheduleExactly"));
  }

  @Test
  public void reportsWhenNotAttached() throws Exception {
    LiveUpdatesBridge.engineDetached(1);
    LiveUpdatesBridge.context = null;
    JSONObject facts = new JSONObject(LiveUpdatesBridge.diagnosticsJson("live_updates"));
    assertFalse(facts.getBoolean("attached"));
    assertFalse(facts.has("notificationsEnabled"));
  }
}
