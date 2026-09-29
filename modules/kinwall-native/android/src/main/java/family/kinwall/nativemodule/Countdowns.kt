package family.kinwall.nativemodule

import android.annotation.SuppressLint
import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

/**
 * Android's Live Activities: a cooking timer, a shopping trip and the next leave-by or start-prep
 * time as ongoing notifications on their own channel, one of each kind at a time. The web app says
 * what to show (web/src/liveActivity.ts in the kinwall repo, through src/liveActivities.ts), in the
 * same JSON the iPhone gets; the words mirror targets/widgets/LiveActivities.swift.
 *
 * Each kind's last payload is saved, so an alarm (a timer that's up, a leave-by time that comes),
 * "Got it", or a restart can redraw it without the app. Countdowns tick on their own (a chronometer
 * counting down to `when`). On Android 16 they ask to be promoted to Live Updates, and the trip
 * shows its progress with ProgressStyle; older versions get a plain ongoing notification.
 *
 * Leave-by and prep-by times are also scheduled ahead with no push (src/leaveBy.ts decides which):
 * an exact alarm at each first warning posts the countdown even with the app closed.
 */
object Countdowns {
  const val CHANNEL = "countdowns"
  private val IDS = mapOf("cooking" to 7101, "shopping" to 7102, "leaveBy" to 7103)
  private const val PREFS = "family.kinwall.countdowns"
  private const val SCHEDULE = "schedule"
  private const val MIN = 60_000L
  /** A timer that rang, or a finished trip, stays this long (iOS ends a rung timer after 30 minutes too). */
  private const val DONE_FOR = 30 * MIN
  const val ACTION_ALARM = "family.kinwall.app.COUNTDOWN"
  const val ACTION_GOT_IT = "family.kinwall.app.GOT_IT"
  private const val LINK = "family.kinwall.app:/open?to="

  private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

  /** For the page's Notifications section: notifications allowed, and this channel not turned off. */
  fun enabled(c: Context): Boolean {
    val nm = NotificationManagerCompat.from(c)
    if (!nm.areNotificationsEnabled()) return false
    return Build.VERSION.SDK_INT < 26 || nm.getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE
  }

  private fun channel(c: Context) = NotificationManagerCompat.from(c).createNotificationChannel(
    NotificationChannelCompat.Builder(CHANNEL, NotificationManagerCompat.IMPORTANCE_DEFAULT)
      .setName("Timers and countdowns")
      .setDescription("Cooking timers, shopping trips, and when to leave or start prep")
      .build()
  )

  // ---- From the web app ----

  /** `colors`: the family's {bg, fg, accent} (src/appearance.ts activityColors), kept for later redraws. */
  fun set(c: Context, kind: String, json: String, colors: String?) {
    if (kind !in IDS) return
    var payload = json
    if (kind == "shopping") { // same trip: keep its size (the page sends what's left, not a total)
      val prev = prefs(c).getString(kind, null)?.let { runCatching { JSONObject(it) }.getOrNull() }
      val now = JSONObject(json)
      if (prev != null && prev.optString("listId") == now.optString("listId")) payload = now.put("total", prev.optInt("total")).toString()
    }
    val edit = prefs(c).edit().putString(kind, payload)
    if (colors != null) edit.putString("colors", colors)
    edit.apply()
    show(c, kind)
  }

  /** No kind: all of them, and the leave-by schedule (sign-out). */
  fun end(c: Context, kind: String?) {
    for (k in kind?.let { listOf(it) } ?: IDS.keys.toList()) {
      val id = IDS[k] ?: continue
      NotificationManagerCompat.from(c).cancel(id)
      cancelAlarm(c, kindUri(k))
      prefs(c).edit().remove(k).apply()
    }
    if (kind == null) schedule(c, "[]")
  }

  /** Redraws each saved one: those whose time passed while the app was closed go. */
  fun endStale(c: Context) { for (k in IDS.keys) if (prefs(c).contains(k)) show(c, k) }

  // ---- Leave-by alarms (src/leaveBy.ts) ----

  /** Replaces the scheduled leave-by warnings with these: [{activity, eventId, title, prep, warnAt, at, endsAt}]. */
  fun schedule(c: Context, json: String) {
    val old = JSONArray(prefs(c).getString(SCHEDULE, "[]"))
    for (i in 0 until old.length()) cancelAlarm(c, leaveByUri(old.getJSONObject(i)))
    prefs(c).edit().putString(SCHEDULE, json).apply()
    arm(c)
  }

  /** Sets the saved schedule's alarms (again after a restart), and shows one that's due now. */
  fun arm(c: Context) {
    val list = JSONArray(prefs(c).getString(SCHEDULE, "[]"))
    val now = System.currentTimeMillis()
    var dueShown = false
    for (i in 0 until list.length()) {
      val item = list.getJSONObject(i)
      if (item.getLong("endsAt") <= now) continue
      val warnAt = item.getLong("warnAt")
      if (warnAt > now) alarm(c, leaveByUri(item), warnAt, item.toString())
      else if (!dueShown) { dueShown = true; warn(c, item) } // soonest first
    }
  }

  /** A scheduled warning: shows it, unless the page is already showing this one (with its own words). */
  fun warn(c: Context, item: JSONObject) {
    val showing = prefs(c).getString("leaveBy", null)?.let { JSONObject(it) }
    if (showing?.optString("activity") == item.optString("activity") && showing.has("headline")) show(c, "leaveBy")
    else set(c, "leaveBy", item.toString(), null)
  }

  // ---- Drawing ----

  private class Look(
    val title: String, val text: String, val ongoing: Boolean,
    val countdownTo: Long? = null, val until: Long? = null,
    val next: Long? = null, val link: String? = null, val chip: String? = null,
    val publicTitle: String, val progress: Pair<Int, Int>? = null, val gotIt: Boolean = false,
  )

  /** `alert`: its own alarm (a timer that's up, a leave-by time that came) sounds again; other redraws are quiet. */
  @SuppressLint("MissingPermission") // without POST_NOTIFICATIONS, notify() quietly does nothing
  fun show(c: Context, kind: String, alert: Boolean = false) {
    val json = prefs(c).getString(kind, null) ?: return
    val now = System.currentTimeMillis()
    val look = try { look(c, kind, JSONObject(json), now) } catch (e: Exception) { null } // a payload we can't read shows nothing
    if (look == null) { end(c, kind); return }
    look.next?.let { alarm(c, kindUri(kind), it, null) } ?: cancelAlarm(c, kindUri(kind))
    channel(c)
    val accent = colors(c)?.optString("accent")?.let { runCatching { Color.parseColor(it) }.getOrNull() } ?: Color.parseColor("#A5613F")
    val open = PendingIntent.getActivity(c, IDS.getValue(kind), openIntent(c, look.link), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    fun base(title: String) = NotificationCompat.Builder(c, CHANNEL)
      .setSmallIcon(R.drawable.kinwall_countdown)
      .setContentTitle(title)
      .setColor(accent)
      .setOngoing(look.ongoing)
      .apply {
        if (look.countdownTo != null) setUsesChronometer(true).setChronometerCountDown(true).setWhen(look.countdownTo).setShowWhen(true)
        else setShowWhen(false)
      }

    // The Lock Screen shows this instead when the phone hides sensitive content there.
    val public = base(look.publicTitle).build()
    val b = base(look.title)
      .setContentText(look.text)
      .setOnlyAlertOnce(!alert)
      .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
      .setPublicVersion(public)
      .setContentIntent(open)
      .setAutoCancel(!look.ongoing)
    look.until?.let { b.setTimeoutAfter(maxOf(1L, it - now)) }
    if (look.gotIt) {
      val got = PendingIntent.getBroadcast(c, 0, Intent(c, CountdownReceiver::class.java).setAction(ACTION_GOT_IT), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
      b.addAction(0, "Got it", got)
    }
    b.addAction(0, "Open", open)
    look.progress?.let { (done, total) ->
      if (Build.VERSION.SDK_INT >= 36) b.setStyle(NotificationCompat.ProgressStyle().addProgressSegment(NotificationCompat.ProgressStyle.Segment(total).setColor(accent)).setProgress(done))
      else b.setProgress(total, done, false)
    }
    if (Build.VERSION.SDK_INT >= 36 && look.ongoing) {
      b.setRequestPromotedOngoing(true)
      look.chip?.let { b.setShortCriticalText(it) }
    }
    try { NotificationManagerCompat.from(c).notify(IDS.getValue(kind), b.build()) } catch (e: SecurityException) {}
  }

  /** What each kind says now, or null when it's over. `next`: when it should redraw by itself. */
  private fun look(c: Context, kind: String, p: JSONObject, now: Long): Look? = when (kind) {
    "cooking" -> {
      val ends = time(p.get("endsAt"))
      val done = p.optBoolean("done") || now >= ends
      val more = p.optInt("more")
      if (done && now >= ends + DONE_FOR) null
      else Look(
        title = if (done) "Done: ${p.getString("timer")}" else p.getString("timer"),
        text = listOfNotNull(p.optString("step").ifEmpty { null }, if (more > 0) "+$more more" else null, p.optString("recipe").ifEmpty { null }).joinToString(" · "),
        ongoing = !done, countdownTo = if (done) null else ends, until = if (done) ends + DONE_FOR else null,
        next = if (done) null else ends, chip = if (done) "Done" else null,
        publicTitle = if (done) "Timer done" else "Kitchen timer",
      )
    }
    "shopping" -> {
      val left = p.getInt("left")
      // The trip's size: the most left we've seen of it.
      val total = maxOf(p.optInt("total"), left)
      if (total != p.optInt("total")) prefs(c).edit().putString(kind, p.put("total", total).toString()).apply()
      val next = p.optJSONObject("next")
      val store = p.getString("store")
      Look(
        title = if (left == 0) "All done at $store" else next?.optString("title")?.ifEmpty { null } ?: "$left left",
        text = listOfNotNull(store, "$left left", next?.optString("aisle")?.takeIf { it.isNotEmpty() && it != "null" }?.let { "next: $it" }).joinToString(" · "),
        ongoing = left > 0, until = if (left == 0) now + DONE_FOR else null,
        link = "lists/${p.getString("listId")}/shop", chip = "$left left",
        publicTitle = "Shopping trip", progress = if (total > 0) (total - left) to total else null, gotIt = next != null,
      )
    }
    "leaveBy" -> {
      val at = time(p.get("at"))
      val ends = time(p.get("endsAt"))
      val prep = p.optBoolean("prep")
      val title = p.getString("title")
      when {
        now >= ends -> null
        now < at -> Look(
          title = p.optString("headline").ifEmpty { "${if (prep) "Start prep" else "Leave"} by ${android.text.format.DateFormat.getTimeFormat(c).format(at)}" },
          text = "$title · ${if (prep) "start prep in" else "leave in"}",
          ongoing = true, countdownTo = at, until = ends, next = at, link = "calendar",
          publicTitle = if (prep) "Time to start prep soon" else "Time to leave soon",
        )
        else -> Look(
          title = p.optString("urgent").ifEmpty { if (prep) "Time to start prep" else "Time to leave" },
          text = title, ongoing = true, until = ends, link = "calendar", chip = "Now",
          publicTitle = if (prep) "Time to start prep" else "Time to leave",
        )
      }
    }
    else -> null
  }

  private fun colors(c: Context) = prefs(c).getString("colors", null)?.let { runCatching { JSONObject(it) }.getOrNull() }

  private fun openIntent(c: Context, to: String?): Intent =
    (if (to == null) c.packageManager.getLaunchIntentForPackage(c.packageName) ?: Intent() else Intent(Intent.ACTION_VIEW, Uri.parse(LINK + to)))
      .setPackage(c.packageName)
      .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)

  /** The web app sends ISO times ("2026-09-29T17:40:00.000Z") and ms; the schedule, ms. */
  private fun time(v: Any): Long = when (v) {
    is Number -> v.toLong()
    else -> SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSX", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") }.parse(v.toString())!!.time
  }

  // ---- Alarms ----

  private fun kindUri(kind: String) = Uri.parse("kinwall-countdown:$kind")
  private fun leaveByUri(item: JSONObject) = Uri.parse("kinwall-leaveby:" + Uri.encode(item.getString("activity")))

  private fun pending(c: Context, uri: Uri, item: String?, flags: Int) = PendingIntent.getBroadcast(
    c, 0, Intent(c, CountdownReceiver::class.java).setAction(ACTION_ALARM).setData(uri).apply { item?.let { putExtra("item", it) } },
    flags or PendingIntent.FLAG_IMMUTABLE,
  )

  /** Exact when allowed ("Alarms & reminders" in the app's settings); otherwise Android may run it
   * some minutes late (setAndAllowWhileIdle), which only delays the countdown's start. */
  private fun alarm(c: Context, uri: Uri, at: Long, item: String?) {
    val am = c.getSystemService(AlarmManager::class.java) ?: return
    val pi = pending(c, uri, item, PendingIntent.FLAG_UPDATE_CURRENT)
    try {
      if (Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms()) am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
      else am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
    } catch (e: SecurityException) {
      am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
    }
  }

  private fun cancelAlarm(c: Context, uri: Uri) {
    val pi = pending(c, uri, null, PendingIntent.FLAG_NO_CREATE) ?: return
    c.getSystemService(AlarmManager::class.java)?.cancel(pi)
    pi.cancel()
  }

  // ---- Got it ----

  /** Ticks the trip's next item with the widgets' own key (src/sharedKey.ts), then moves on to the
   * one after it that the page sent (up to five; the page sends a fresh list when it's next open).
   * The demo's sample list just moves on. Signed out or offline, nothing changes: Open is the way in. */
  fun gotIt(c: Context) {
    val p = JSONObject(prefs(c).getString("shopping", null) ?: return)
    val next = p.optJSONObject("next") ?: return
    val id = next.getString("id")
    val connection = Keychain.get(c, "family.kinwall.widgets")?.let { JSONObject(it) }
    if (connection != null) {
      val url = Uri.parse(connection.getString("baseURL")).buildUpon().appendEncodedPath("api/lists/${Uri.encode(p.getString("listId"))}/items/${Uri.encode(id)}").build().toString()
      val request = Request.Builder().url(url)
        .header("Authorization", "Bearer ${connection.getString("key")}")
        .patch("""{"done":true}""".toRequestBody("application/json".toMediaType()))
        .build()
      val ok = try { OkHttpClient.Builder().callTimeout(8, TimeUnit.SECONDS).build().newCall(request).execute().use { it.isSuccessful } } catch (e: Exception) { false }
      if (!ok) return
    } else if (Keychain.get(c, "family.kinwall.demo") == null) return
    val upcoming = p.optJSONArray("upcoming") ?: JSONArray()
    val rest = JSONArray()
    var after = false
    for (i in 0 until upcoming.length()) {
      val e = upcoming.getJSONObject(i)
      if (after) rest.put(e)
      if (e.optString("id") == id) after = true
    }
    p.put("left", maxOf(0, p.getInt("left") - 1)).put("upcoming", rest).put("next", if (rest.length() > 0) rest.getJSONObject(0) else JSONObject.NULL)
    prefs(c).edit().putString("shopping", p.toString()).apply()
    show(c, "shopping")
  }
}

/** Alarms (a countdown's next moment, a scheduled leave-by warning) and "Got it". */
class CountdownReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    when (intent.action) {
      Countdowns.ACTION_GOT_IT -> {
        val done = goAsync() // a network call: off the main thread, within the receiver's time
        thread { try { Countdowns.gotIt(context) } finally { done.finish() } }
      }
      Countdowns.ACTION_ALARM -> {
        val uri = intent.data ?: return
        if (uri.scheme == "kinwall-leaveby") intent.getStringExtra("item")?.let { Countdowns.warn(context, JSONObject(it)) }
        else uri.schemeSpecificPart?.let { Countdowns.show(context, it, alert = true) }
      }
    }
  }
}

/** Alarms don't survive a restart or an update: set them again, and redraw what was showing. */
class CountdownBootReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    Countdowns.arm(context)
    Countdowns.endStale(context)
  }
}
