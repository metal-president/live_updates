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
  private static final int MAX_METRICS = 3;
  private static final int MAX_TEXT = 64;

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
      warn("Semantic style unavailable", e);
      return text;
    }
  }

  /** Sets the semantic style of a progress segment. */
  static void styleSegment(Notification.ProgressStyle.Segment segment, int style) {
    if (!available() || style == 0) return;
    try {
      segment.getClass().getMethod("setSemanticStyle", int.class).invoke(segment, style);
    } catch (ReflectiveOperationException | RuntimeException e) {
      warn("Semantic style unavailable", e);
    }
  }

  /** Sets the semantic style of a progress point. */
  static void stylePoint(Notification.ProgressStyle.Point point, int style) {
    if (!available() || style == 0) return;
    try {
      point.getClass().getMethod("setSemanticStyle", int.class).invoke(point, style);
    } catch (ReflectiveOperationException | RuntimeException e) {
      warn("Semantic style unavailable", e);
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
      int critical = -1;
      // The system shows at most three; ignore the rest of a remote payload.
      for (int i = 0; i < metrics.length() && count < MAX_METRICS; i++) {
        JSONObject m = metrics.optJSONObject(i);
        if (m == null) continue;
        // A bad entry (rejected by the platform) is skipped, not the whole style.
        try {
          Object value = metricValue(m);
          if (value == null) continue;
          add.invoke(
              style,
              metricCtor.newInstance(
                  value,
                  clip(m.optString("label")),
                  semanticStyle(LiveUpdatesBridge.optString(m, "semanticStyle"))));
        } catch (java.lang.reflect.InvocationTargetException e) {
          warn("Metric rejected", e);
          continue;
        }
        if (i == criticalIndex) critical = count;
        count++;
      }
      if (count == 0) return false;
      if (critical >= 0) {
        styleClass.getMethod("setCriticalMetric", int.class).invoke(style, critical);
      }
      b.setStyle((Notification.Style) style);
      return true;
    } catch (ReflectiveOperationException | RuntimeException e) {
      warn("MetricStyle unavailable", e);
      return false;
    }
  }

  @Nullable
  private static Object metricValue(JSONObject m) throws ReflectiveOperationException {
    String unit = clip(LiveUpdatesBridge.optString(m, "unit"));
    String type = m.optString("type");
    // Remote payloads may carry anything: numbers must be JSON numbers.
    Object raw = m.opt("value");
    boolean number = raw instanceof Number;
    switch (type) {
      case "integer":
        if (!number) return null;
        long whole =
            Math.max(Integer.MIN_VALUE, Math.min(Integer.MAX_VALUE, ((Number) raw).longValue()));
        return Class.forName("android.app.Notification$Metric$FixedInt")
            .getConstructor(int.class, CharSequence.class)
            .newInstance((int) whole, unit);
      case "decimal":
        {
          int digits = Math.max(0, Math.min(m.optInt("fractionDigits", 1), 6));
          if (!number) return null;
          float value = ((Number) raw).floatValue();
          if (Float.isNaN(value) || Float.isInfinite(value)) return null;
          return Class.forName("android.app.Notification$Metric$FixedFloat")
              .getConstructor(float.class, CharSequence.class, int.class, int.class)
              .newInstance(value, unit, 0, digits);
        }
      case "text":
        return Class.forName("android.app.Notification$Metric$FixedText")
            .getConstructor(CharSequence.class, CharSequence.class)
            .newInstance(clip(m.optString("value")), unit);
      case "timer":
      case "stopwatch":
        {
          if (!number) return null;
          Class<?> c = Class.forName("android.app.Notification$Metric$TimeDifference");
          String factory = type.equals("timer") ? "forTimer" : "forStopwatch";
          return c.getMethod(factory, Instant.class, int.class)
              .invoke(null, Instant.ofEpochMilli(m.optLong("value")), FORMAT_CHRONOMETER);
        }
      case "pausedTimer":
      case "pausedStopwatch":
        {
          if (!number) return null;
          Class<?> c = Class.forName("android.app.Notification$Metric$TimeDifference");
          String factory = type.equals("pausedTimer") ? "forPausedTimer" : "forPausedStopwatch";
          return c.getMethod(factory, Duration.class, int.class)
              .invoke(null, Duration.ofMillis(Math.max(0, m.optLong("value"))), FORMAT_CHRONOMETER);
        }
      default:
        return null;
    }
  }

  @Nullable
  private static String clip(@Nullable String text) {
    if (text == null || text.length() <= MAX_TEXT) return text;
    int end = Character.isHighSurrogate(text.charAt(MAX_TEXT - 1)) ? MAX_TEXT - 1 : MAX_TEXT;
    return text.substring(0, end);
  }

  private static boolean warned;

  /** Logs the first failure only, so a missing API does not log on every post. */
  private static void warn(String message, Throwable e) {
    if (warned) return;
    warned = true;
    Log.w(TAG, message, e);
  }
}
