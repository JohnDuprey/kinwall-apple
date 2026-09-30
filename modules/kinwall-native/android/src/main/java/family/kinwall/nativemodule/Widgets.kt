package family.kinwall.nativemodule

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent

/** Redraws the app's home-screen widgets (src/widgets.tsx renders them in JavaScript): the same
 * update broadcast Android sends on its own schedule, to each of the app's widget providers. */
object Widgets {
  fun reload(c: Context) {
    val manager = AppWidgetManager.getInstance(c) ?: return
    for (provider in manager.getInstalledProvidersForPackage(c.packageName, null)) {
      val ids = manager.getAppWidgetIds(provider.provider).takeIf { it.isNotEmpty() } ?: continue
      c.sendBroadcast(Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE).setComponent(provider.provider).putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids))
    }
  }
}
