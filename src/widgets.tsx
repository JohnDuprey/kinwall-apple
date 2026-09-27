import { FlexWidget, TextWidget, registerWidgetTaskHandler, requestWidgetUpdate, type WidgetTaskHandlerProps } from 'react-native-android-widget'
import { type Board, board, nowAndNext } from './api'
import { widgetConnection } from './sharedKey'

// Android home-screen widget: Now & Next plus chores left, rendered from JavaScript in a headless
// task (react-native-android-widget), so it reuses the API client and the widgets' key. Tapping
// it opens the app on the calendar or chores through the same links the iOS widgets use.
const ACCENT = '#A5613F'
const time = (iso: string) => new Date(iso).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })

function Widget({ b, problem }: { b: Board | null; problem?: string }) {
  const { now, next } = b ? nowAndNext(b) : {}
  const remaining = b?.chores.reduce((n, c) => n + c.remaining, 0) ?? 0
  const total = b?.chores.reduce((n, c) => n + c.total, 0) ?? 0
  const row = (label: string, title: string, sub: string, to: string) => (
    <FlexWidget style={{ flexDirection: 'column', marginBottom: 6 }} clickAction="OPEN_URI" clickActionData={{ uri: `family.kinwall.app:/open?to=${to}` }}>
      <TextWidget text={label} style={{ fontSize: 10, fontWeight: '900', color: ACCENT }} />
      <TextWidget text={title} style={{ fontSize: 15, fontWeight: 'bold', color: '#1c1c1e' }} maxLines={2} />
      <TextWidget text={sub} style={{ fontSize: 12, color: '#6e6e73' }} />
    </FlexWidget>
  )
  return (
    <FlexWidget style={{ height: 'match_parent', width: 'match_parent', flexDirection: 'column', backgroundColor: '#ffffff', borderRadius: 16, padding: 14 }} clickAction="OPEN_APP">
      {problem ? <TextWidget text={problem} style={{ fontSize: 13, color: '#6e6e73' }} /> : null}
      {now ? row('NOW', now.title, `ends ${time(now.end)}`, 'calendar') : null}
      {next ? row('NEXT', next.title, next.leaveAt && Date.parse(next.leaveAt) > Date.now() ? `🚗 leave ${time(next.leaveAt)} · ${time(next.start)}` : time(next.start), 'calendar') : null}
      {b && !now && !next ? row('TODAY', 'Nothing more today', 'Enjoy the evening.', 'calendar') : null}
      {total > 0 ? row('CHORES', remaining === 0 ? 'Chores done 🎉' : `${remaining} of ${total} left`, 'Tap to tick them off', 'chores') : null}
    </FlexWidget>
  )
}

async function render() {
  const c = await widgetConnection()
  if (!c) return <Widget b={null} problem="Open Kinwall to sign in" />
  const b = await board(c, 1).catch(() => null)
  return b ? <Widget b={b} /> : <Widget b={null} problem="Can't reach Kinwall right now" />
}

export const reloadWidgets = () => { requestWidgetUpdate({ widgetName: 'Kinwall', renderWidget: render }).catch(() => {}) }

export function registerWidgets() {
  registerWidgetTaskHandler(async (props: WidgetTaskHandlerProps) => {
    if (props.widgetAction !== 'WIDGET_DELETED') props.renderWidget(await render())
  })
}
