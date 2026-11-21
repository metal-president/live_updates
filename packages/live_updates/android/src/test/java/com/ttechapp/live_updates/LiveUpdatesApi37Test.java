package com.ttechapp.live_updates;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertSame;
import static org.junit.Assert.assertTrue;

import android.app.Notification;
import android.content.Context;
import android.text.Spanned;
import org.robolectric.RuntimeEnvironment;
import java.util.List;
import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
public class LiveUpdatesApi37Test {
  private final Context context = RuntimeEnvironment.getApplication();

  private Notification.Builder builder() {
    return new Notification.Builder(context, "test")
        .setSmallIcon(android.R.drawable.ic_dialog_info)
        .setContentTitle("t");
  }

  private static JSONObject metric(String label, String type, Object value) throws Exception {
    return new JSONObject().put("label", label).put("type", type).put("value", value);
  }

  @Test
  public void semanticStyleNames() {
    assertEquals(1, LiveUpdatesApi37.semanticStyle("info"));
    assertEquals(2, LiveUpdatesApi37.semanticStyle("safe"));
    assertEquals(3, LiveUpdatesApi37.semanticStyle("caution"));
    assertEquals(4, LiveUpdatesApi37.semanticStyle("danger"));
    assertEquals(0, LiveUpdatesApi37.semanticStyle("purple"));
    assertEquals(0, LiveUpdatesApi37.semanticStyle(null));
  }

  @Test
  @Config(sdk = 36)
  public void ignoredBeforeAndroid17() throws Exception {
    JSONArray metrics = new JSONArray().put(metric("Steps", "integer", 3));
    assertFalse(LiveUpdatesApi37.setMetricStyle(builder(), metrics, 0));
    String text = "body";
    assertSame(text, LiveUpdatesApi37.styledText(text, 4));
  }

  @Test
  @Config(sdk = 37)
  public void styledTextHasAnnotation() {
    CharSequence styled = LiveUpdatesApi37.styledText("Nearby", 2);
    assertTrue(styled instanceof Spanned);
    Object[] spans = ((Spanned) styled).getSpans(0, styled.length(), Object.class);
    assertEquals(1, spans.length);
    assertSame("", LiveUpdatesApi37.styledText("", 2));
  }

  @Test
  @Config(sdk = 37)
  public void buildsMetricStyle() throws Exception {
    JSONArray metrics =
        new JSONArray()
            .put(metric("Bad", "integer", "12")) // not a number: skipped
            .put(metric("Steps", "integer", 1979L))
            .put(metric("Nan", "decimal", "NaN")) // skipped
            .put(metric("Distance", "decimal", 4.25).put("unit", "km").put("semanticStyle", "caution"))
            .put(metric("ETA", "timer", System.currentTimeMillis() + 600_000))
            .put(metric("Fourth", "text", "dropped")); // over the limit of three
    Notification.Builder b = builder();
    // Index 3 in the JSON is "Distance", the second metric that is kept.
    assertTrue(LiveUpdatesApi37.setMetricStyle(b, metrics, 3));
    Notification n = b.build();
    assertEquals(
        "android.app.Notification$MetricStyle",
        n.extras.getString(Notification.EXTRA_TEMPLATE));
    Object style = Notification.Builder.recoverBuilder(context, n).getStyle();
    List<?> kept = (List<?>) style.getClass().getMethod("getMetrics").invoke(style);
    assertEquals(3, kept.size());
    assertEquals("Steps", label(kept.get(0)));
    assertEquals("Distance", label(kept.get(1)));
    assertEquals("ETA", label(kept.get(2)));
    Object critical = style.getClass().getMethod("getCriticalMetric").invoke(style);
    assertEquals("Distance", label(critical));
    assertEquals(3, critical.getClass().getMethod("getSemanticStyle").invoke(critical));
  }

  @Test
  @Config(sdk = 37)
  public void clipsLongLabels() throws Exception {
    String longLabel = new String(new char[200]).replace('\0', 'x');
    Notification.Builder b = builder();
    assertTrue(
        LiveUpdatesApi37.setMetricStyle(
            b, new JSONArray().put(metric(longLabel, "text", longLabel)), -1));
    Object style = Notification.Builder.recoverBuilder(context, b.build()).getStyle();
    List<?> kept = (List<?>) style.getClass().getMethod("getMetrics").invoke(style);
    assertEquals(64, label(kept.get(0)).length());
  }

  @Test
  @Config(sdk = 37)
  public void noUsableMetricsFallsBack() throws Exception {
    JSONArray metrics = new JSONArray().put(metric("x", "unknown", 1)).put("not an object");
    assertFalse(LiveUpdatesApi37.setMetricStyle(builder(), metrics, 0));
  }

  private static String label(Object metric) throws Exception {
    return metric.getClass().getMethod("getLabel").invoke(metric).toString();
  }
}
