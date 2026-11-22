package com.ttechapp.live_updates

import android.content.Intent
import android.content.pm.PackageManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry

/**
 * Registration entry point required by Flutter.
 *
 * All functionality is exposed to Dart through JNIgen-generated bindings to
 * [LiveUpdatesBridge], not through platform channels. The plugin only provides
 * the context, the activity, tap intents and permission results.
 */
class LiveUpdatesPlugin :
    FlutterPlugin,
    ActivityAware,
    PluginRegistry.NewIntentListener,
    PluginRegistry.RequestPermissionsResultListener {
    private var binding: ActivityPluginBinding? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        LiveUpdatesBridge.engineAttached(binding.applicationContext)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        LiveUpdatesBridge.engineDetached(binding.engineId)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        this.binding = binding
        LiveUpdatesBridge.activity = binding.activity
        binding.addOnNewIntentListener(this)
        binding.addRequestPermissionsResultListener(this)
        LiveUpdatesBridge.handleIntent(binding.activity.intent)
    }

    override fun onDetachedFromActivity() {
        detach()
        // The activity is gone: a prompt that was showing gets no result.
        LiveUpdatesBridge.permissionPromptGone()
    }

    private fun detach() {
        binding?.removeOnNewIntentListener(this)
        binding?.removeRequestPermissionsResultListener(this)
        binding = null
        LiveUpdatesBridge.activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    // The prompt survives a configuration change; its result still arrives.
    override fun onDetachedFromActivityForConfigChanges() = detach()

    override fun onNewIntent(intent: Intent): Boolean {
        LiveUpdatesBridge.handleIntent(intent)
        return false
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != LiveUpdatesBridge.PERMISSION_REQUEST_CODE) return false
        LiveUpdatesBridge.permissionResult(
            grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED,
        )
        return true
    }
}
