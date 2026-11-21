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
import java.util.ArrayList;
import java.util.List;

/**
 * Runs the Dart background action handler in a headless engine when a button
 * is pressed while no Dart listener is attached (typically: app not running).
 */
final class LiveUpdatesBackgroundRunner {
  private static final String TAG = "live_updates";
  /** Broadcast receivers get about 10 s with goAsync(); stay below that. */
  private static final long TIMEOUT_MS = 9_000;

  @Nullable private static FlutterEngine engine;
  private static final List<BroadcastReceiver.PendingResult> pending = new ArrayList<>();
  private static final Handler main = new Handler(Looper.getMainLooper());
  private static final Runnable timeout = LiveUpdatesBackgroundRunner::finish;

  private LiveUpdatesBackgroundRunner() {}

  /** Starts the engine (once) on the main thread; [result] is finished when done. */
  static void run(Context context, long dispatcherHandle, @Nullable BroadcastReceiver.PendingResult result) {
    final Context app = context.getApplicationContext();
    main.post(
        () -> {
          if (result != null) pending.add(result);
          if (engine != null) return; // Already running: it drains the queue.
          // Start the deadline first: initialization can take a while.
          main.removeCallbacks(timeout);
          main.postDelayed(timeout, TIMEOUT_MS);
          try {
            // Loads the Flutter native library, needed for the callback lookup.
            FlutterLoader loader = FlutterInjector.instance().flutterLoader();
            loader.startInitialization(app);
            loader.ensureInitializationComplete(app, null);
            FlutterCallbackInformation info =
                FlutterCallbackInformation.lookupCallbackInformation(dispatcherHandle);
            if (info == null) {
              Log.w(TAG, "Background action handler is not available; was the app updated?");
              finish();
              return;
            }
            engine = new FlutterEngine(app);
            engine
                .getDartExecutor()
                .executeDartCallback(
                    new DartExecutor.DartCallback(app.getAssets(), loader.findAppBundlePath(), info));
          } catch (Throwable e) {
            Log.e(TAG, "Could not start the background action handler", e);
            finish();
          }
        });
  }

  /** Called from Dart when the handler finished, or on timeout. */
  static void finish() {
    main.post(
        () -> {
          main.removeCallbacks(timeout);
          FlutterEngine e = engine;
          engine = null;
          if (e != null) e.destroy();
          for (BroadcastReceiver.PendingResult r : pending) r.finish();
          pending.clear();
        });
  }
}
