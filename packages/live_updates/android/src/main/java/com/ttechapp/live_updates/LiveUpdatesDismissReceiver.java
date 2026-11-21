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

  static PendingIntent intent(Context c, String id) {
    Intent intent =
        new Intent(c, LiveUpdatesDismissReceiver.class)
            .setAction("com.ttechapp.live_updates.DISMISSED")
            .putExtra(EXTRA_ID, id);
    intent.setData(LiveUpdatesBridge.intentUri("dismiss", id, ""));
    return PendingIntent.getBroadcast(
        c, 0, intent, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
  }

  @Override
  public void onReceive(Context context, Intent intent) {
    String id = intent.getStringExtra(EXTRA_ID);
    if (id == null) return;
    LiveUpdatesBridge.markDismissed(context.getApplicationContext(), id);
    LiveUpdatesBridge.emit("dismissed", id);
  }
}
