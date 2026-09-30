package family.kinwall.nativemodule

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.app.StatusBarManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/** Quick Settings tiles (the Android twin of the iOS Controls): each opens the app on its link,
 * which src/App.tsx routes. Add them from the Quick Settings editor, or the app can offer one
 * (Tiles.request, Android 13 and later). */
abstract class KinwallTile(private val link: String) : TileService() {
  override fun onStartListening() {
    qsTile?.apply { state = Tile.STATE_INACTIVE; updateTile() } // an action, not a switch
  }

  @SuppressLint("StartActivityAndCollapseDeprecated")
  override fun onClick() {
    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(link)).setPackage(packageName).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    val open = {
      if (Build.VERSION.SDK_INT >= 34) startActivityAndCollapse(PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE))
      else @Suppress("DEPRECATION") startActivityAndCollapse(intent)
    }
    if (isLocked) unlockAndRun { open() } else open()
  }
}

class GroceriesTile : KinwallTile("family.kinwall.app:/open?to=groceries")
class NightScreenTile : KinwallTile("family.kinwall.app:/open?to=night")

object Tiles {
  private val TILES = mapOf(
    "groceries" to Triple(GroceriesTile::class.java, R.string.kinwall_tile_groceries, R.drawable.kinwall_ic_add),
    "night" to Triple(NightScreenTile::class.java, R.string.kinwall_tile_night, R.drawable.kinwall_ic_night),
  )

  /** Android asks the person whether to add the tile. Its answer (StatusBarManager's
   * TILE_ADD_REQUEST_RESULT_*), or -1 before Android 13 or for an unknown tile. */
  fun request(c: Context, name: String, done: (Int) -> Unit) {
    val (cls, label, icon) = TILES[name] ?: return done(-1)
    if (Build.VERSION.SDK_INT < 33) return done(-1)
    val bar = c.getSystemService(StatusBarManager::class.java) ?: return done(-1)
    bar.requestAddTileService(ComponentName(c, cls), c.getString(label), Icon.createWithResource(c, icon), c.mainExecutor) { done(it) }
  }
}
