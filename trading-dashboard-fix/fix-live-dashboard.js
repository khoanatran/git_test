#!/usr/bin/env node
/**
 * Remove archived pre-reset trades from the Live Dashboard data files.
 *
 * The Aug 29-30 auto-sync ran `git merge -X ours`, which auto-merged the
 * trades-snapshot.json array instead of conflicting, restoring 274 archived
 * April-July trades (62 -> 336). This filters them back out and pins
 * liveFromDate so later merges stay inside the live window.
 *
 * Usage:  node fix-live-dashboard.js [repoPath] [liveFromDate]
 */
const fs = require('fs')
const path = require('path')

const repoRoot = process.argv[2] || process.cwd()
const LIVE_FROM = process.argv[3] || '2026-07-29'
const dataDir = path.join(repoRoot, 'data')

const DATE_RE = /(\d{4}-\d{2}-\d{2})/

function readJson(name) {
  const file = path.join(dataDir, name)
  if (!fs.existsSync(file)) return null
  return JSON.parse(fs.readFileSync(file, 'utf8'))
}

function writeJson(name, value) {
  fs.writeFileSync(path.join(dataDir, name), `${JSON.stringify(value, null, 2)}\n`, 'utf8')
}

// Trade timestamps are plain ISO strings; take the first date-like field.
function tradeDay(trade) {
  for (const key of ['exitTime', 'timestamp', 'entryTime']) {
    const value = trade[key]
    if (typeof value === 'string') {
      const m = value.match(DATE_RE)
      if (m) return m[1]
    }
  }
  return null
}

// Unknown dates are kept: better to show an extra row than silently drop data.
function inLiveWindow(day) {
  return day === null || day >= LIVE_FROM
}

function filterKeyedByDate(record) {
  if (!record || typeof record !== 'object') return record
  const out = {}
  for (const [key, value] of Object.entries(record)) {
    const m = key.match(DATE_RE)
    if (inLiveWindow(m ? m[1] : null)) out[key] = value
  }
  return out
}

const snapshot = readJson('trades-snapshot.json')
if (!snapshot) {
  console.error(`No data/trades-snapshot.json under ${repoRoot}`)
  process.exit(1)
}

const allTrades = Array.isArray(snapshot) ? snapshot : snapshot.trades || []
const before = allTrades.length
const liveTrades = allTrades.filter(t => inLiveWindow(tradeDay(t)))
const after = liveTrades.length

if (Array.isArray(snapshot)) {
  writeJson('trades-snapshot.json', liveTrades)
} else {
  snapshot.trades = liveTrades
  snapshot.updatedAt = new Date().toISOString()
  writeJson('trades-snapshot.json', snapshot)
}
console.log(`trades-snapshot.json: ${before} -> ${after} trades (removed ${before - after})`)

const session = readJson('live-session.json')
if (session) {
  session.liveFromDate = LIVE_FROM
  writeJson('live-session.json', session)
  console.log(`live-session.json: liveFromDate = ${LIVE_FROM}`)
}

const flags = readJson('flags.json')
if (flags) {
  if (flags.days) flags.days = filterKeyedByDate(flags.days)
  if (flags.trades) flags.trades = filterKeyedByDate(flags.trades)
  writeJson('flags.json', flags)
  console.log('flags.json: archived entries removed')
}

const tags = readJson('trade-tags.json')
if (tags) {
  writeJson('trade-tags.json', filterKeyedByDate(tags))
  console.log('trade-tags.json: archived entries removed')
}

console.log(`\nDone. Live window starts ${LIVE_FROM}; ${after} trades remain.`)
if (before === after) {
  console.log('Nothing was removed - data already matched the live window.')
}
