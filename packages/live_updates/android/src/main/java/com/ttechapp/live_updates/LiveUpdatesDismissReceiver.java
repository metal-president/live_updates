package com.ttechapp.live_updates;

import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import androidx.annotation.Keep;

/** Reports live updates the user swiped away. */
@Keep
public final class LiveUpdatesDismissReceiver extends BroadcastReceiver {
  private static final String EXTRA_ID = "com.ttechapp.live_updates.ID";
  private static final String EXTRA_DEADLINE = "com.ttechapp.live_updates.DEADLINE";
  /** Timeouts may fire a little early or late. */
  private static final long DEADLINE_SLACK_MS = 2_000;

  /** {@code deadline}: when the notification times out (epoch ms), or 0. */
  static PendingIntent intent(Context c, String id, long deadline) {
    Intent intent =
        new Intent(c, LiveUpdatesDismissReceiver.class)
            .setAction("com.ttechapp.live_updates.DISMISSED")
            .putExtra(EXTRA_ID, id)
            .putExtra(EXTRA_DEADLINE, deadline);
    intent.setData(LiveUpdatesBridge.intentUri("dismiss", id, ""));
    return PendingIntent.getBroadcast(
        c, 0, intent, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
  }

  @Override
  public void onReceive(Context context, Intent intent) {
    String id = intent.getStringExtra(EXTRA_ID);
    if (id == null) return;
    long deadline = intent.getLongExtra(EXTRA_DEADLINE, 0);
    if (deadline > 0 && System.currentTimeMillis() >= deadline - DEADLINE_SLACK_MS) {
      // Removed by AndroidLiveUpdateOptions.timeoutAfter, not by the user:
      // the key can be started again.
      LiveUpdatesBridge.timedOut(context.getApplicationContext(), id);
      return;
    }
    LiveUpdatesBridge.markDismissed(context.getApplicationContext(), id);
    LiveUpdatesBridge.emit("dismissed", id);
  }
}
