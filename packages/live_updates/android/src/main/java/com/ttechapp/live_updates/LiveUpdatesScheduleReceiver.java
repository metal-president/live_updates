package com.ttechapp.live_updates;

import android.app.AlarmManager;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import androidx.annotation.Keep;

/**
 * Shows scheduled live updates and the ended content of live updates ({@code endAt}) when their
 * alarm fires, and sets the alarms again after events
 * that drop or affect them (reboot, app update, clock or time zone change, exact alarm permission
 * change).
 */
@Keep
public final class LiveUpdatesScheduleReceiver extends BroadcastReceiver {
  @Override
  public void onReceive(Context context, Intent intent) {
    String action = intent.getAction();
    if (action == null) return;
    Context c = context.getApplicationContext();
    switch (action) {
      case LiveUpdatesScheduler.ACTION_FIRE:
        {
          String key = intent.getStringExtra(LiveUpdatesScheduler.EXTRA_KEY);
          if (key != null) LiveUpdatesScheduler.fire(c, key);
          break;
        }
      case LiveUpdatesScheduler.ACTION_END:
        {
          String id = intent.getStringExtra(LiveUpdatesScheduler.EXTRA_KEY);
          if (id != null) LiveUpdatesScheduler.fireEnd(c, id);
          break;
        }
      case Intent.ACTION_BOOT_COMPLETED:
      case Intent.ACTION_MY_PACKAGE_REPLACED:
      case Intent.ACTION_TIME_CHANGED:
      case Intent.ACTION_TIMEZONE_CHANGED:
      case AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED:
        LiveUpdatesScheduler.restoreAll(c);
        break;
      default:
        break;
    }
  }
}
