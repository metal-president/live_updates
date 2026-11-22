package com.ttechapp.live_updates;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import androidx.annotation.Nullable;
import io.flutter.FlutterInjector;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.embedding.engine.loader.FlutterLoader;
import io.flutter.view.FlutterCallbackInformation;

/**
 * Runs the Dart background action handler in a headless engine for presses
 * that no Dart listener of the app takes (all of them while the app is in the
 * background).
 */
final class LiveUpdatesBackgroundRunner {
  private static final String TAG = "live_updates";
  /** Broadcast receivers get about 10 s with goAsync(); stay below that. */
  private static final long TIMEOUT_MS = 9_000;

  @Nullable private static FlutterEngine engine;
  /** Receivers waiting for a run, with the take count that covers each press. */
  private static final RunWaiters<BroadcastReceiver.PendingResult> pending =
      new RunWaiters<>(BroadcastReceiver.PendingResult::finish);
  /** Runs started in a row for presses that arrived as a run finished. */
  private static int restarts;
  private static final int MAX_RESTARTS = 3;
  private static final Handler main = new Handler(Looper.getMainLooper());
  private static final Runnable timeout = LiveUpdatesBackgroundRunner::timedOut;

  private LiveUpdatesBackgroundRunner() {}

  @Nullable private static Context appContext;
  private static long dispatcher;

  /** Starts the engine (once) on the main thread; [result] is finished when done. */
  static void run(Context context, long dispatcherHandle, @Nullable BroadcastReceiver.PendingResult result) {
    final Context app = context.getApplicationContext();
    main.post(
        () -> {
          // The next take covers this press.
          if (result != null) pending.add(result, LiveUpdatesBridge.takeCount + 1);
          if (engine != null) return; // Already running: it drains the queue.
          appContext = app;
          dispatcher = dispatcherHandle;
          startEngine();
        });
  }

  /** On the main thread, with no engine running. */
  private static void startEngine() {
    Context app = appContext;
    if (app == null) return;
    // Start the deadline first: initialization can take a while.
    main.removeCallbacks(timeout);
    main.postDelayed(timeout, TIMEOUT_MS);
    try {
      // Loads the Flutter native library, needed for the callback lookup.
      FlutterLoader loader = FlutterInjector.instance().flutterLoader();
      loader.startInitialization(app);
      loader.ensureInitializationComplete(app, null);
      FlutterCallbackInformation info =
          FlutterCallbackInformation.lookupCallbackInformation(dispatcher);
      if (info == null) {
        Log.w(TAG, "Background action handler is not available; was the app updated?");
        stop(false);
        return;
      }
      engine = new FlutterEngine(app);
      engine
          .getDartExecutor()
          .executeDartCallback(
              new DartExecutor.DartCallback(app.getAssets(), loader.findAppBundlePath(), info));
    } catch (Throwable e) {
      Log.e(TAG, "Could not start the background action handler", e);
      stop(false);
    }
  }

  /** Called from Dart when the handler finished. */
  static void finish() {
    main.post(() -> stop(true));
  }

  private static void timedOut() {
    stop(false);
  }

  /**
   * Shuts the engine down and finishes the receivers whose presses were taken
   * (all of them after a timeout). A press queued after the handler took the
   * last one gets a new run, while its receiver keeps waiting, unless the run
   * timed out.
   */
  private static void stop(boolean mayRestart) {
    main.removeCallbacks(timeout);
    FlutterEngine e = engine;
    engine = null;
    if (e != null) e.destroy();
    boolean restart =
        mayRestart && restarts < MAX_RESTARTS && LiveUpdatesBridge.hasQueuedBackgroundActions();
    pending.finishCovered(restart ? LiveUpdatesBridge.takeCount : Integer.MAX_VALUE);
    if (restart) {
      restarts++;
      startEngine();
      if (engine != null) return;
    }
    restarts = 0;
    pending.finishAll();
  }
}
