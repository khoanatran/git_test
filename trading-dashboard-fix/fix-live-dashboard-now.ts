/**
 * One-shot fix: drop archived May–July trades from Live Dashboard data/.
 * Run from Trading_DashBoard root:
 *   npx --yes tsx scripts/fix-live-dashboard-now.ts
 * Then push so GitHub stops re-syncing 336 trades:
 *   git add data/ && git commit -m "Fix live dashboard: keep July 29+ trades only" && git push
 */
import fs from 'fs/promises'
import path from 'path'

const DATA_DIR = path.join(process.cwd(), 'data')
const LIVE_FROM = process.argv[2] ?? '2026-07-29'
const DATE_KEY = /^(\d{4}-\d{2}-\d{2})/

function dayFromTrade(t: Record<string, unknown>): string {
  for (const key of ['exitTime', 'timestamp', 'entryTime']) {
    const v = t[key]
    if (typeof v === 'string') {
      const m = v.match(DATE_KEY)
      if (m) return m[1]
    }
  }
  return '9999-99-99'
}

function dayFromKey(key: string): string | null {
  const m = key.match(/(\d{4}-\d{2}-\d{2})/)
  return m ? m[1] : null
}

function onOrAfter(day: string | null): boolean {
  if (!day) return true
  return day >= LIVE_FROM
}

async function readJson<T>(name: string, fallback: T): Promise<T> {
  try {
    return JSON.parse(await fs.readFile(path.join(DATA_DIR, name), 'utf-8')) as T
  } catch {
    return fallback
  }
}

async function writeJson(name: string, value: unknown): Promise<void> {
  await fs.mkdir(DATA_DIR, { recursive: true })
  await fs.writeFile(path.join(DATA_DIR, name), `${JSON.stringify(value, null, 2)}\n`, 'utf-8')
}

async function main() {
  const snap = await readJson<{ version?: number; trades: Record<string, unknown>[]; updatedAt?: string }>(
    'trades-snapshot.json',
    { trades: [] }
  )
  const before = snap.trades.length
  const liveTrades = snap.trades.filter(t => onOrAfter(dayFromTrade(t)))
  snap.trades = liveTrades
  snap.updatedAt = new Date().toISOString()
  await writeJson('trades-snapshot.json', snap)

  const session = await readJson<Record<string, unknown>>('live-session.json', {})
  session.liveFromDate = LIVE_FROM
  await writeJson('live-session.json', session)

  const flags = await readJson<{ _v?: number; days?: Record<string, boolean>; trades?: Record<string, boolean> }>(
    'flags.json',
    { _v: 1, days: {}, trades: {} }
  )
  flags.days = Object.fromEntries(Object.entries(flags.days ?? {}).filter(([d]) => onOrAfter(d)))
  flags.trades = Object.fromEntries(
    Object.entries(flags.trades ?? {}).filter(([k]) => onOrAfter(dayFromKey(k)))
  )
  await writeJson('flags.json', flags)

  const tags = await readJson<Record<string, string[]>>('trade-tags.json', {})
  const liveTags = Object.fromEntries(Object.entries(tags).filter(([k]) => onOrAfter(dayFromKey(k))))
  await writeJson('trade-tags.json', liveTags)

  console.log(`Live Dashboard fix complete.`)
  console.log(`  liveFromDate: ${LIVE_FROM}`)
  console.log(`  trades: ${before} -> ${liveTrades.length}`)
  console.log(`  removed: ${before - liveTrades.length} archived-period trade(s)`)
  if (before === liveTrades.length) {
    console.log(`  (snapshot already matched live window — check browser cache / GitHub sync)`)
  }
  console.log(`\nNext: commit and push so auto-sync stops restoring 336 trades:`)
  console.log(`  git add data/ && git commit -m "Fix live dashboard: keep July 29+ trades only" && git push`)
}

main().catch(err => {
  console.error(err)
  process.exit(1)
})
