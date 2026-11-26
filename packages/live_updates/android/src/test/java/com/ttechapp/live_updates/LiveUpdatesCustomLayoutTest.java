package com.ttechapp.live_updates;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertSame;
import static org.junit.Assert.assertTrue;
import static org.robolectric.Shadows.shadowOf;

import android.app.Application;
import android.app.Notification;
import android.app.NotificationManager;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.service.notification.StatusBarNotification;
import android.view.View;
import android.widget.Chronometer;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.ProgressBar;
import android.widget.RemoteViews;
import android.widget.TextView;
import java.io.File;
import java.io.FileOutputStream;
import org.json.JSONObject;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;
import org.robolectric.shadows.ShadowLog;

/** AndroidLiveUpdateOptions.customLayout (src/test/res/layout/live_update_test*.xml). */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 36)
public class LiveUpdatesCustomLayoutTest {
  private static final String LAYOUT = "\"androidLayout\":\"live_update_test\"";
  private static final String DECORATED = "android.app.Notification$DecoratedCustomViewStyle";

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
    LiveUpdatesCustomLayout.reset();
  }

  @After
  public void tearDown() {
    LiveUpdatesBridge.engineDetached(1);
  }

  private Notification shown(String id) {
    for (StatusBarNotification n : manager.getActiveNotifications()) {
      if ((LiveUpdatesBridge.TAG_PREFIX + id).equals(n.getTag())) return n.getNotification();
    }
    return null;
  }

  private View inflate(RemoteViews views) {
    return views.apply(app, new FrameLayout(app));
  }

  private int id(String name) {
    return app.getResources().getIdentifier(name, "id", app.getPackageName());
  }

  private <T extends View> T view(View root, String name) {
    T v = root.findViewById(id(name));
    assertNotNull(name, v);
    return v;
  }

  private String text(View root, String name) {
    return ((TextView) view(root, name)).getText().toString();
  }

  private int visibility(View root, String name) {
    return view(root, name).getVisibility();
  }

  /** A PNG in the image directory, as Dart stores it. */
  private String storeImage(String name) throws Exception {
    File dir = LiveUpdatesBridge.imageDirectory(app);
    dir.mkdirs();
    Bitmap bitmap = Bitmap.createBitmap(8, 8, Bitmap.Config.ARGB_8888);
    try (FileOutputStream out = new FileOutputStream(new File(dir, name))) {
      bitmap.compress(Bitmap.CompressFormat.PNG, 100, out);
    }
    return name;
  }

  @Test
  public void customLayoutUsesTheDecoratedStyleWithoutPromotion() throws Exception {
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"Order\",\"progress\":0.5,\"shortCriticalText\":\"5 min\","
                + "\"steps\":{\"labels\":[\"a\",\"b\"],\"current\":1},"
                + LAYOUT
                + "}");
    Notification n = shown(id);
    assertEquals(DECORATED, n.extras.getString(Notification.EXTRA_TEMPLATE));
    assertNotNull(n.contentView);
    // No expanded layout: the collapsed one there too.
    assertNotNull(n.bigContentView);
    assertFalse(n.extras.getBoolean("android.requestPromotedOngoing"));
    assertFalse(LiveUpdatesBridge.isPromoted(id));
    // Still ongoing, with the title for accessibility and other devices.
    assertTrue((n.flags & Notification.FLAG_ONGOING_EVENT) != 0);
    assertEquals("Order", n.extras.getCharSequence(Notification.EXTRA_TITLE).toString());
    // Steps are not turned into the sub text.
    assertNull(n.extras.getCharSequence(Notification.EXTRA_SUB_TEXT));
    assertNull(n.getShortCriticalText());
  }

  @Test
  public void everyModeUsesTheCustomLayout() throws Exception {
    for (String mode : new String[] {"ongoing", "classic"}) {
      String id =
          LiveUpdatesBridge.start(
              "{\"title\":\"Order\",\"androidMode\":\"" + mode + "\"," + LAYOUT + "}");
      Notification n = shown(id);
      assertEquals(mode, DECORATED, n.extras.getString(Notification.EXTRA_TEMPLATE));
      assertNotNull(mode, n.contentView);
    }
  }

  @Test
  public void liveUpdateModeLogsOnceThatItIsNotPromoted() throws Exception {
    ShadowLog.clear();
    String json = "{\"title\":\"Order\"," + LAYOUT + "}";
    String id = LiveUpdatesBridge.start(json);
    LiveUpdatesBridge.update(id, json);
    long warnings =
        ShadowLog.getLogsForTag("live_updates").stream()
            .filter(l -> l.msg.contains("never promoted"))
            .count();
    assertEquals(1, warnings);
    // The empty-title warning is not for custom layouts.
    ShadowLog.clear();
    LiveUpdatesBridge.handleRemotePayload(
        new JSONObject()
            .put("live_updates_event", "start")
            .put("live_updates_id", "untitled")
            .put("live_updates_content", "{\"title\":\"\"," + LAYOUT + "}")
            .toString());
    assertFalse(
        ShadowLog.getLogsForTag("live_updates").stream()
            .anyMatch(l -> l.msg.contains("title is empty")));
  }

  @Test
  public void everyViewIsBound() throws Exception {
    long end = System.currentTimeMillis() + 10 * 60_000;
    String image = storeImage("lu_test_main.png");
    String map = storeImage("lu_test_map.png");
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"Order\",\"body\":\"On the way\",\"progress\":0.25,"
                + "\"timerEnd\":"
                + (end / 1000.0)
                + ",\"image\":\""
                + image
                + "\",\"extra\":{\"status\":\"Near you\",\"Bad-Key\":\"x\",\"eta\":\"5 min\"},"
                + "\"extraImages\":{\"map\":\""
                + map
                + "\"},"
                + LAYOUT
                + "}");
    View root = inflate(shown(id).contentView);
    assertEquals("Order", text(root, "live_update_title"));
    assertEquals("On the way", text(root, "live_update_body"));
    assertEquals(View.VISIBLE, visibility(root, "live_update_body"));
    ProgressBar progress = view(root, "live_update_progress");
    assertEquals(View.VISIBLE, progress.getVisibility());
    assertEquals(LiveUpdatesCustomLayout.PROGRESS_MAX, progress.getMax());
    assertEquals(250, progress.getProgress());
    Chronometer timer = view(root, "live_update_timer");
    assertEquals(View.VISIBLE, timer.getVisibility());
    assertTrue(timer.isCountDown());
    // The base is in the elapsed realtime clock: about ten minutes ahead.
    long left = timer.getBase() - android.os.SystemClock.elapsedRealtime();
    assertTrue("left " + left, Math.abs(left - 10 * 60_000) < 5_000);
    ImageView picture = view(root, "live_update_image");
    assertEquals(View.VISIBLE, picture.getVisibility());
    assertNotNull(picture.getDrawable());
    assertEquals("Near you", text(root, "live_update_extra_status"));
    assertEquals(View.VISIBLE, visibility(root, "live_update_extra_status"));
    ImageView mapView = view(root, "live_update_extra_image_map");
    assertEquals(View.VISIBLE, mapView.getVisibility());
    assertNotNull(mapView.getDrawable());
  }

  @Test
  public void missingValuesHideTheirViews() throws Exception {
    String id = LiveUpdatesBridge.start("{\"title\":\"Order\",\"body\":\"\"," + LAYOUT + "}");
    View root = inflate(shown(id).contentView);
    assertEquals(View.GONE, visibility(root, "live_update_body"));
    assertEquals(View.GONE, visibility(root, "live_update_progress"));
    assertEquals(View.GONE, visibility(root, "live_update_timer"));
    assertEquals(View.GONE, visibility(root, "live_update_image"));
    // Views of extra values keep what the layout says.
    assertEquals(View.GONE, visibility(root, "live_update_extra_status"));
    assertEquals(View.GONE, visibility(root, "live_update_extra_image_map"));
  }

  @Test
  public void aStopwatchCountsUpAndAMissingPictureIsHidden() throws Exception {
    long start = System.currentTimeMillis() - 60_000;
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"Run\",\"timerStart\":"
                + (start / 1000.0)
                + ",\"image\":\"lu_none.png\",\"extraImages\":{\"map\":\"../x.png\"},"
                + LAYOUT
                + "}");
    View root = inflate(shown(id).contentView);
    Chronometer timer = view(root, "live_update_timer");
    assertEquals(View.VISIBLE, timer.getVisibility());
    assertFalse(timer.isCountDown());
    assertEquals(View.GONE, visibility(root, "live_update_image"));
    assertEquals(View.GONE, visibility(root, "live_update_extra_image_map"));
  }

  @Test
  public void aCountdownThatIsOverIsHidden() throws Exception {
    double over = (System.currentTimeMillis() - 1000) / 1000.0;
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"Order\",\"timerEnd\":"
                + over
                + ",\"removeAtCountdownEnd\":false,"
                + LAYOUT
                + "}");
    View root = inflate(shown(id).contentView);
    assertEquals(View.GONE, visibility(root, "live_update_timer"));
  }

  @Test
  public void theExpandedLayoutIsUsedWhenExpanded() throws Exception {
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"Order\",\"extra\":{\"eta\":\"5 min\"},"
                + LAYOUT
                + ",\"androidExpandedLayout\":\"live_update_test_expanded\"}");
    Notification n = shown(id);
    View big = inflate(n.bigContentView);
    assertEquals("Order", text(big, "live_update_title"));
    assertEquals("5 min", text(big, "live_update_extra_eta"));
    assertEquals(View.VISIBLE, visibility(big, "live_update_extra_eta"));
    // The collapsed layout has no such view.
    View small = inflate(n.contentView);
    assertNull(small.findViewById(id("live_update_extra_eta")));
  }

  @Test
  public void aMissingLayoutFallsBackToTheSystemTemplate() throws Exception {
    ShadowLog.clear();
    String json = "{\"title\":\"Order\",\"progress\":0.5,\"androidLayout\":\"no_such_layout\"}";
    String id = LiveUpdatesBridge.start(json);
    LiveUpdatesBridge.update(id, json);
    Notification n = shown(id);
    assertNull(n.contentView);
    assertEquals(
        "android.app.Notification$ProgressStyle", n.extras.getString(Notification.EXTRA_TEMPLATE));
    assertTrue(n.extras.getBoolean("android.requestPromotedOngoing"));
    long warnings =
        ShadowLog.getLogsForTag("live_updates").stream()
            .filter(l -> l.msg.contains("no_such_layout"))
            .count();
    assertEquals(1, warnings);
    // Not a resource name (getIdentifier would accept "pkg:type/name").
    String other =
        LiveUpdatesBridge.start(
            "{\"title\":\"Order\",\"androidLayout\":\"android:layout/simple_list_item_1\"}");
    assertNull(shown(other).contentView);
  }

  @Test
  public void aMissingExpandedLayoutUsesTheCollapsedOne() throws Exception {
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"Order\"," + LAYOUT + ",\"androidExpandedLayout\":\"nope\"}");
    Notification n = shown(id);
    assertNotNull(n.bigContentView);
    assertEquals("Order", text(inflate(n.bigContentView), "live_update_title"));
  }

  @Test
  public void finalContentRebindsTheLayoutWithoutProgressAndTimer() throws Exception {
    long end = System.currentTimeMillis() + 10 * 60_000;
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"Order\",\"progress\":0.5,\"timerEnd\":"
                + (end / 1000.0)
                + ","
                + LAYOUT
                + "}");
    LiveUpdatesBridge.end(
        id, "{\"title\":\"Delivered\",\"body\":\"At the door\",\"progress\":1," + LAYOUT + "}", -1);
    Notification n = shown(id);
    assertEquals(DECORATED, n.extras.getString(Notification.EXTRA_TEMPLATE));
    assertFalse((n.flags & Notification.FLAG_ONGOING_EVENT) != 0);
    View root = inflate(n.contentView);
    assertEquals("Delivered", text(root, "live_update_title"));
    assertEquals("At the door", text(root, "live_update_body"));
    assertEquals(View.GONE, visibility(root, "live_update_progress"));
    assertEquals(View.GONE, visibility(root, "live_update_timer"));
  }

  @Test
  public void endWithoutFinalContentKeepsTheLayout() throws Exception {
    String id = LiveUpdatesBridge.start("{\"title\":\"Order\",\"progress\":0.5," + LAYOUT + "}");
    LiveUpdatesBridge.end(id, null, -1);
    View root = inflate(shown(id).contentView);
    assertEquals("Order", text(root, "live_update_title"));
    assertEquals(View.GONE, visibility(root, "live_update_progress"));
  }

  @Test
  public void afterARestartTheEndedLookHidesProgressAndTimer() throws Exception {
    long end = System.currentTimeMillis() + 10 * 60_000;
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"Order\",\"progress\":0.5,\"timerEnd\":"
                + (end / 1000.0)
                + ","
                + LAYOUT
                + "}");
    LiveUpdatesBridge.forgetPostsInProcess(id);
    LiveUpdatesBridge.end(id, null, -1);
    Notification n = shown(id);
    assertFalse((n.flags & Notification.FLAG_ONGOING_EVENT) != 0);
    View root = inflate(n.contentView);
    assertEquals("Order", text(root, "live_update_title"));
    assertEquals(View.GONE, visibility(root, "live_update_progress"));
    assertEquals(View.GONE, visibility(root, "live_update_timer"));
  }

  @Test
  public void staleContentRebindsTheLayout() throws Exception {
    String image = storeImage("lu_test_done.png");
    double past = (System.currentTimeMillis() - 1000) / 1000.0;
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"Order\",\"progress\":0.5,\"endAt\":"
                + past
                + ",\"endedContent\":{\"title\":\"Delivered\",\"image\":\""
                + image
                + "\"},"
                + LAYOUT
                + "}");
    Notification n = shown(id);
    assertEquals(DECORATED, n.extras.getString(Notification.EXTRA_TEMPLATE));
    View root = inflate(n.contentView);
    assertEquals("Delivered", text(root, "live_update_title"));
    assertEquals(View.GONE, visibility(root, "live_update_body"));
    assertEquals(View.GONE, visibility(root, "live_update_progress"));
    assertEquals(View.VISIBLE, visibility(root, "live_update_image"));
  }

  @Test
  public void thePublicVersionKeepsTheSystemTemplate() throws Exception {
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"Order\",\"publicContent\":{\"title\":\"Delivery\"}," + LAYOUT + "}");
    Notification n = shown(id);
    assertNotNull(n.contentView);
    assertNotNull(n.publicVersion);
    assertNull(n.publicVersion.contentView);
    assertEquals(
        "Delivery", n.publicVersion.extras.getCharSequence(Notification.EXTRA_TITLE).toString());
  }

  @Test
  public void remotePayloadsUseTheLayout() throws Exception {
    LiveUpdatesBridge.handleRemotePayload(
        new JSONObject()
            .put("live_updates_event", "start")
            .put("live_updates_id", "order-1")
            .put(
                "live_updates_content",
                "{\"title\":\"Order\",\"extra\":{\"status\":\"Packed\"}," + LAYOUT + "}")
            .toString());
    View root = inflate(shown("order-1").contentView);
    assertEquals("Packed", text(root, "live_update_extra_status"));
  }

  @Test
  public void bothLayoutsShareOneDecodedPicture() throws Exception {
    String image = storeImage("lu_test_shared.png");
    JSONObject content =
        new JSONObject(
            "{\"title\":\"Order\",\"image\":\""
                + image
                + "\","
                + LAYOUT
                + ",\"androidExpandedLayout\":\"live_update_test_expanded\"}");
    RemoteViews[] views = LiveUpdatesCustomLayout.views(app, content, false, false);
    assertNotNull(views);
    assertEquals(2, views.length);
    // Same layout for both without an expanded one: one RemoteViews.
    RemoteViews[] same =
        LiveUpdatesCustomLayout.views(
            app, new JSONObject("{\"title\":\"Order\"," + LAYOUT + "}"), false, false);
    assertSame(same[0], same[1]);
  }

  @Test
  public void anExtraKeyNamingAnImageViewIsNotBound() throws Exception {
    // live_update_extra_image_map is an ImageView: text there would make the
    // system reject the notification.
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"Order\",\"extra\":{\"image_map\":\"x\"}," + LAYOUT + "}");
    View root = inflate(shown(id).contentView);
    assertEquals(View.GONE, visibility(root, "live_update_extra_image_map"));
  }

  @Test
  public void remotePayloadsOnlyUseLayoutsWithThePrefix() throws Exception {
    LiveUpdatesBridge.handleRemotePayload(
        new JSONObject()
            .put("live_updates_event", "start")
            .put("live_updates_id", "order-2")
            .put(
                "live_updates_content",
                "{\"title\":\"Order\",\"androidMode\":\"ongoing\","
                    + "\"androidLayout\":\"test_other_layout\"}")
            .toString());
    assertNull(shown("order-2").contentView);
    // A local post may use it.
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"Order\",\"androidLayout\":\"test_other_layout\"}");
    assertNotNull(shown(id).contentView);
  }

  @Test
  public void theTimerIsNotRepeatedInTheHeader() throws Exception {
    long end = System.currentTimeMillis() + 10 * 60_000;
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"Order\",\"timerEnd\":" + (end / 1000.0) + "," + LAYOUT + "}");
    Notification n = shown(id);
    assertFalse(n.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER));
    assertEquals(View.VISIBLE, visibility(inflate(n.contentView), "live_update_timer"));
  }

  @Test
  public void largePicturesAreScaledDown() throws Exception {
    File dir = LiveUpdatesBridge.imageDirectory(app);
    dir.mkdirs();
    Bitmap big = Bitmap.createBitmap(2048, 1024, Bitmap.Config.ARGB_8888);
    try (FileOutputStream out = new FileOutputStream(new File(dir, "lu_test_big.png"))) {
      big.compress(Bitmap.CompressFormat.PNG, 100, out);
    }
    String id =
        LiveUpdatesBridge.start(
            "{\"title\":\"Order\",\"image\":\"lu_test_big.png\"," + LAYOUT + "}");
    ImageView picture = view(inflate(shown(id).contentView), "live_update_image");
    assertTrue(picture.getDrawable().getIntrinsicWidth() <= 512);
  }

  @Test
  @Config(sdk = 33)
  public void olderVersionsUseTheLayoutToo() throws Exception {
    String id = LiveUpdatesBridge.start("{\"title\":\"Order\",\"progress\":0.5," + LAYOUT + "}");
    Notification n = shown(id);
    assertEquals(DECORATED, n.extras.getString(Notification.EXTRA_TEMPLATE));
    assertEquals(0, n.extras.getInt(Notification.EXTRA_PROGRESS_MAX));
    ProgressBar progress = view(inflate(n.contentView), "live_update_progress");
    assertEquals(500, progress.getProgress());
  }
}
