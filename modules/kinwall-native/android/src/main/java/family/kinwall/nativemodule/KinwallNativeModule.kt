package family.kinwall.nativemodule

import android.view.View
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import org.json.JSONObject

/** Android's KinwallNative (modules/kinwall-native/index.ts): the keys (Keychain.kt), the
 * countdowns (Countdowns.kt) and the notification channels (Channels.kt). Widgets render from
 * JavaScript on Android (reloadWidgets asks Android to redraw them) and there's no Watch; there's
 * no push, so "activityToken" never fires. */
class KinwallNativeModule : Module() {
  private val context get() = requireNotNull(appContext.reactContext)

  override fun definition() = ModuleDefinition {
    Name("KinwallNative")
    Events("watchStateChanged", "activityToken")

    // Edge to edge (Android 15 and later) the window no longer shrinks for the keyboard
    // (adjustResize), so a field at the bottom of the page (shopping mode's Add an item) would sit
    // under it. The content makes room itself: the keyboard's height less the navigation bar the
    // screens already keep clear of. The insets pass on untouched.
    OnCreate {
      Channels.ensure(context)
      val activity = appContext.currentActivity ?: return@OnCreate
      activity.runOnUiThread {
        ViewCompat.setOnApplyWindowInsetsListener(activity.findViewById<View>(android.R.id.content)) { view, insets ->
          val keyboard = insets.getInsets(WindowInsetsCompat.Type.ime()).bottom
          val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars()).bottom
          view.setPadding(0, 0, 0, maxOf(0, keyboard - bars))
          insets
        }
      }
    }

    AsyncFunction("keychainGet") { service: String, _: Boolean -> Keychain.get(context, service) }
    AsyncFunction("keychainSet") { service: String, _: Boolean, value: String? -> Keychain.set(context, service, value) }
    Function("reloadWidgets") { Widgets.reload(context) }
    Function("watchAppInstalled") { false }
    Function("updateWatch") { _: Map<String, Any?> -> }

    AsyncFunction("activitySet") { kind: String, payload: String, colors: Map<String, String>? ->
      Countdowns.set(context, kind, payload, colors?.let { JSONObject(it as Map<*, *>).toString() })
    }
    AsyncFunction("activityEnd") { kind: String? -> Countdowns.end(context, kind) }
    AsyncFunction("activityEndStale") { Countdowns.endStale(context) }
    Function("activitiesEnabled") { Countdowns.enabled(context) }
    // Before src/reminders.ts schedules on them; and a channel's page in Android Settings (the web
    // app's "Let medicine through Do Not Disturb", through src/WebShell.tsx).
    AsyncFunction("ensureChannels") { Channels.ensure(context) }
    Function("openNotificationSettings") { channel: String? -> Channels.openSettings(context, channel) }
    AsyncFunction("leaveBySchedule") { alarms: String -> Countdowns.schedule(context, alarms) }
    // Edge to edge, the navigation bar is see-through: its buttons follow the page's colors, not
    // the system's light or dark mode (expo-status-bar only does the status bar).
    Function("navigationBar") { dark: Boolean ->
      val activity = appContext.currentActivity ?: return@Function
      activity.runOnUiThread { WindowInsetsControllerCompat(activity.window, activity.window.decorView).isAppearanceLightNavigationBars = !dark }
    }
  }
}
