package com.ttechapp.live_updates;

import android.app.Notification;
import android.os.Build;
import android.text.SpannableString;
import android.text.Spanned;
import android.util.Log;
import androidx.annotation.Nullable;
import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.time.Duration;
import java.time.Instant;
import org.json.JSONArray;
import org.json.JSONObject;

/**
 * Android 17 (API 37) notification features: {@code MetricStyle} and semantic
 * colors.
 *
 * <p>Called through reflection so the plugin keeps compiling against the
 * same SDK as Flutter apps by default. Every method returns {@code false} or
 * its input unchanged when the API is missing, and the caller falls back to
 * the Android 16 layout.
 */
final class LiveUpdatesApi37 {
  private static final String TAG = "LiveUpdates";

  // Notification.SEMANTIC_STYLE_* and Metric.TimeDifference.FORMAT_CHRONOMETER.
  private static final int SEMANTIC_INFO = 1;
  private static final int SEMANTIC_SAFE = 2;
  private static final int SEMANTIC_CAUTION = 3;
  private static final int SEMANTIC_DANGER = 4;
  private static final int FORMAT_CHRONOMETER = 2;

  private LiveUpdatesApi37() {}

  static boolean available() {
    return Build.VERSION.SDK_INT >= 37;
  }

  /** {@code SEMANTIC_STYLE_*} for a Dart {@code LiveUpdateSemanticStyle} name, or 0. */
  static int semanticStyle(@Nullable String name) {
    if (name == null) return 0;
    switch (name) {
      case "info":
        return SEMANTIC_INFO;
      case "safe":
        return SEMANTIC_SAFE;
      case "caution":
        return SEMANTIC_CAUTION;
      case "danger":
        return SEMANTIC_DANGER;
      default:
        return 0;
    }
  }

  /** {@code text} with a semantic style annotation over its whole length. */
  static CharSequence styledText(String text, int style) {
    if (!available() || style == 0 || text.isEmpty()) return text;
    try {
      Object span =
          Notification.class
              .getMethod("createSemanticStyleAnnotation", int.class)
              .invoke(null, style);
      SpannableString styled = new SpannableString(text);
      styled.setSpan(span, 0, text.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
      return styled;
    } catch (ReflectiveOperationException | RuntimeException e) {
      Log.w(TAG, "Semantic style unavailable", e);
      return text;
    }
  }

  /** Sets the semantic style of a progress segment. */
  static void styleSegment(Notification.ProgressStyle.Segment segment, int style) {
    if (!available() || style == 0) return;
    try {
      segment.getClass().getMethod("setSemanticStyle", int.class).invoke(segment, style);
    } catch (ReflectiveOperationException | RuntimeException e) {
      Log.w(TAG, "Semantic style unavailable", e);
    }
  }

  /**
   * Sets a {@code MetricStyle} built from {@code metrics} (the JSON written
   * by the Dart {@code AndroidMetric}). Returns false when nothing was set.
   */
  static boolean setMetricStyle(
      Notification.Builder b, @Nullable JSONArray metrics, int criticalIndex) {
    if (!available() || metrics == null || metrics.length() == 0) return false;
    try {
      Class<?> valueClass = Class.forName("android.app.Notification$Metric$MetricValue");
      Class<?> metricClass = Class.forName("android.app.Notification$Metric");
      Class<?> styleClass = Class.forName("android.app.Notification$MetricStyle");
      Constructor<?> metricCtor =
          metricClass.getConstructor(valueClass, CharSequence.class, int.class);
      Object style = styleClass.getConstructor().newInstance();
      Method add = styleClass.getMethod("addMetric", metricClass);
      int count = 0;
      for (int i = 0; i < metrics.length(); i++) {
        JSONObject m = metrics.optJSONObject(i);
        Object value = m == null ? null : metricValue(m);
        if (value == null) continue;
        add.invoke(
            style,
            metricCtor.newInstance(
                value, m.optString("label"), semanticStyle(LiveUpdatesBridge.optString(m, "semanticStyle"))));
        count++;
      }
      if (count == 0) return false;
      if (criticalIndex >= 0 && criticalIndex < count) {
        styleClass.getMethod("setCriticalMetric", int.class).invoke(style, criticalIndex);
      }
      b.setStyle((Notification.Style) style);
      return true;
    } catch (ReflectiveOperationException | RuntimeException e) {
      Log.w(TAG, "MetricStyle unavailable", e);
      return false;
    }
  }

  @Nullable
  private static Object metricValue(JSONObject m) throws ReflectiveOperationException {
    String unit = LiveUpdatesBridge.optString(m, "unit");
    String type = m.optString("type");
    switch (type) {
      case "integer":
        return Class.forName("android.app.Notification$Metric$FixedInt")
            .getConstructor(int.class, CharSequence.class)
            .newInstance(m.optInt("value"), unit);
      case "decimal":
        {
          int digits = Math.max(0, Math.min(m.optInt("fractionDigits", 1), 6));
          return Class.forName("android.app.Notification$Metric$FixedFloat")
              .getConstructor(float.class, CharSequence.class, int.class, int.class)
              .newInstance((float) m.optDouble("value"), unit, 0, digits);
        }
      case "text":
        return Class.forName("android.app.Notification$Metric$FixedText")
            .getConstructor(CharSequence.class, CharSequence.class)
            .newInstance(m.optString("value"), unit);
      case "timer":
      case "stopwatch":
        {
          Class<?> c = Class.forName("android.app.Notification$Metric$TimeDifference");
          String factory = type.equals("timer") ? "forTimer" : "forStopwatch";
          return c.getMethod(factory, Instant.class, int.class)
              .invoke(null, Instant.ofEpochMilli(m.optLong("value")), FORMAT_CHRONOMETER);
        }
      case "pausedTimer":
      case "pausedStopwatch":
        {
          Class<?> c = Class.forName("android.app.Notification$Metric$TimeDifference");
          String factory = type.equals("pausedTimer") ? "forPausedTimer" : "forPausedStopwatch";
          return c.getMethod(factory, Duration.class, int.class)
              .invoke(null, Duration.ofMillis(Math.max(0, m.optLong("value"))), FORMAT_CHRONOMETER);
        }
      default:
        return null;
    }
  }
}
