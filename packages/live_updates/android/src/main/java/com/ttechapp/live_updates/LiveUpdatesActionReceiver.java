package com.ttechapp.live_updates;

import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import androidx.annotation.Keep;

/** Delivers notification button presses that do not open the app. */
@Keep
public final class LiveUpdatesActionReceiver extends BroadcastReceiver {
  static PendingIntent intent(Context c, String updateId, String actionId) {
    Intent intent =
        new Intent(c, LiveUpdatesActionReceiver.class)
            .setAction("com.ttechapp.live_updates.ACTION")
            .putExtra(LiveUpdatesBridge.EXTRA_UPDATE_ID, updateId)
            .putExtra(LiveUpdatesBridge.EXTRA_ACTION_ID, actionId)
            .setData(LiveUpdatesBridge.intentUri("action", updateId, actionId));
    return PendingIntent.getBroadcast(
        c, 0, intent, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
  }

  @Override
  public void onReceive(Context context, Intent intent) {
    String updateId = intent.getStringExtra(LiveUpdatesBridge.EXTRA_UPDATE_ID);
    String actionId = intent.getStringExtra(LiveUpdatesBridge.EXTRA_ACTION_ID);
    if (updateId != null && actionId != null) {
      LiveUpdatesBridge.emitAction(context.getApplicationContext(), updateId, actionId);
    }
  }
}
