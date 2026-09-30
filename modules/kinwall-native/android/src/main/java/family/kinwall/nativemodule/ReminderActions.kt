package family.kinwall.nativemodule

import android.content.Context
import android.content.Intent
import android.net.Uri
import expo.modules.notifications.notifications.model.NotificationContent
import expo.modules.notifications.notifications.model.NotificationRequest
import expo.modules.notifications.notifications.triggers.DateTrigger
import expo.modules.notifications.service.NotificationsService
import org.json.JSONObject

/**
 * The buttons on the app's reminders (src/reminders.ts sets them): Snooze on an event reminder,
 * Taken and Snooze on a medicine reminder, Done on the chore nudge. Android's side of
 * native/ios/NotificationActions.swift: they run here without opening the app, with the widgets'
 * own key, like the countdowns' Got it and Taken (Countdowns.kt). Open, and a tap, go to the page
 * (src/App.tsx) as before.
 *
 * expo-notifications sends every notification event to the app's highest-priority receiver for its
 * action (its own is -1), so this one (0, AndroidManifest.xml) gets them all and passes on the rest.
 * NotificationsService already runs each event on a worker thread inside goAsync, so the network
 * call can happen right here.
 *
 * A snooze is a copy of the reminder 10 minutes later (id "snz:…", which a refresh leaves be and
 * sign-out clears). If Taken or Done can't be saved (offline, signed out), the reminder comes
 * straight back saying so, so nothing is lost.
 */
class ReminderActions : NotificationsService() {
  override fun onReceiveNotificationResponse(context: Context, intent: Intent) {
    val response = getNotificationResponseFromBroadcastIntent(intent)
    val action = response.actionIdentifier
    if (action !in listOf("snooze", "taken", "done")) return super.onReceiveNotificationResponse(context, intent)
    val request = response.notification.notificationRequest
    val data = request.content.body ?: JSONObject()
    getPresentationDelegate(context).dismissNotifications(listOf(request.identifier))
    val saved = perform(context, action, data)
    when {
      action == "snooze" -> again(context, request, 10 * 60_000L, null)
      !saved -> again(context, request, 1_000L, "Didn't save. Try again, or open Kinwall.")
      else -> Widgets.reload(context)
    }
  }

  /** The server's side of the button; true when there's nothing to tell it. */
  private fun perform(c: Context, action: String, data: JSONObject): Boolean {
    val med = data.optString("medicationId")
    if (med.isNotEmpty()) return Countdowns.markDose(c, med, data.optString("date"), data.optString("time"), if (action == "taken") "taken" else "snooze")
    val chore = data.optString("choreId")
    if (action == "done" && chore.isNotEmpty()) return Countdowns.send(c, "POST", "api/chores/${Uri.encode(chore)}/complete", JSONObject().put("date", data.optString("date")))
    return true
  }

  private fun again(c: Context, r: NotificationRequest, inMs: Long, note: String?) {
    val old = r.content
    val content = NotificationContent.Builder()
      .setTitle(old.title)
      .setText(listOfNotNull(note, old.text).joinToString("\n"))
      .setBody(old.body)
      .setCategoryId(old.categoryId)
      .useDefaultSound()
      .build()
    val id = if (r.identifier.startsWith("snz:")) r.identifier else "snz:" + r.identifier
    getSchedulingDelegate(c).scheduleNotification(NotificationRequest(id, content, DateTrigger(r.trigger?.getNotificationChannel(), System.currentTimeMillis() + inMs)))
  }
}
