package family.kinwall.nativemodule

import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import org.json.JSONObject

/** Android's KinwallNative (modules/kinwall-native/index.ts): the keys (Keychain.kt) and the
 * countdowns (Countdowns.kt). Widgets render from JavaScript on Android and there's no Watch, so
 * those calls do nothing here; there's no push, so "activityToken" never fires. */
class KinwallNativeModule : Module() {
  private val context get() = requireNotNull(appContext.reactContext)

  override fun definition() = ModuleDefinition {
    Name("KinwallNative")
    Events("watchStateChanged", "activityToken")

    AsyncFunction("keychainGet") { service: String, _: Boolean -> Keychain.get(context, service) }
    AsyncFunction("keychainSet") { service: String, _: Boolean, value: String? -> Keychain.set(context, service, value) }
    Function("reloadWidgets") {}
    Function("watchAppInstalled") { false }
    Function("updateWatch") { _: Map<String, Any?> -> }

    AsyncFunction("activitySet") { kind: String, payload: String, colors: Map<String, String>? ->
      Countdowns.set(context, kind, payload, colors?.let { JSONObject(it as Map<*, *>).toString() })
    }
    AsyncFunction("activityEnd") { kind: String? -> Countdowns.end(context, kind) }
    AsyncFunction("activityEndStale") { Countdowns.endStale(context) }
    Function("activitiesEnabled") { Countdowns.enabled(context) }
    AsyncFunction("leaveBySchedule") { alarms: String -> Countdowns.schedule(context, alarms) }
  }
}
