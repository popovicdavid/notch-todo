// Variables used by Scriptable.
// These must be at the very top of the file. Do not edit.
// icon-color: red; icon-glyph: magic;
// NotchTodo for iPhone. Samme todo.md som notch-appen på Mac-en.
// Filen ligger i Scriptables egen iCloud-mappe (Scriptable/NotchTodo/todo.md), så widgeten trenger ikke filbokmerke.
// Widget: viser åpne oppgaver. Trykk på widgeten for å åpne appen (fire seksjoner, skriv rett inn, trykk på tekst for å redigere).

const fm = FileManager.iCloud()
const local = FileManager.local()
const PATH = fm.joinPath(fm.joinPath(fm.documentsDirectory(), "NotchTodo"), "todo.md")
const CACHE = local.joinPath(local.documentsDirectory(), "notchtodo-cache.md")

const NAMES = ["Viktig", "Frister", "Generelle", "Senere"]
// Senere er ting langt frem i tid. Den vises i appen, men ikke i widgeten.
const WIDGET_NAMES = ["Viktig", "Frister", "Generelle"]
const DATED = ["Frister", "Senere"]
const COLORS = { Viktig: "#FF9F0A", Frister: "#FF375F", Generelle: "#64D2FF", Senere: "#BF5AF2" }
const MONTHS = ["jan.", "feb.", "mar.", "apr.", "mai", "jun.", "jul.", "aug.", "sep.", "okt.", "nov.", "des."]

// ---------- Fil ----------
// Leser fra iCloud (laster ned ved behov). Siste vellykkede lesing lagres lokalt som reserve.
async function readTodo() {
  try {
    if (fm.fileExists(PATH)) {
      if (!fm.isFileDownloaded(PATH)) {
        await Promise.race([fm.downloadFileFromiCloud(PATH), new Promise(r => Timer.schedule(4000, false, r))])
      }
      const txt = fm.isFileDownloaded(PATH) ? fm.readString(PATH) : null
      if (txt != null) {
        try { local.writeString(CACHE, txt) } catch (e) {}
        return txt
      }
    }
  } catch (e) {}
  try { if (local.fileExists(CACHE)) return local.readString(CACHE) } catch (e) {}
  return null
}

let todoText = await readTodo()

// ---------- Fila ----------
// Samme regler som Mac-appen (Sources/Model/TodoFile.swift): seksjonsrekkefølgen, tittelen og notater i fila tas vare på,
// og hver endring legges oppå fila slik den er rett før lagring, så endringer fra Mac-en eller assistenten ikke overskrives.

function sectionOf(heading) {
  const n = heading.trim().toLowerCase()
  return n.startsWith("generell") ? "Generelle" : n.startsWith("frist") ? "Frister" : n.startsWith("senere") ? "Senere" : "Viktig"
}

function parseDoc(text) {
  const doc = { preamble: [], order: [], items: [], notes: {} }
  let sec = "Viktig"
  let inSec = false
  for (const l of (text || "").split(/\r?\n/)) {
    const t = l.trim()
    if (t.startsWith("## ")) {
      sec = sectionOf(t.slice(3))
      inSec = true
      if (!doc.order.includes(sec)) doc.order.push(sec)
    } else if (/^- \[[ xX]\] /.test(t)) {
      doc.items.push({ text: t.slice(6), done: t[3] !== " ", section: sec })
    } else if (t) {
      if (inSec) (doc.notes[sec] = doc.notes[sec] || []).push(t)
      else doc.preamble.push(t)
    }
  }
  if (!doc.preamble.length) doc.preamble = ["# Todo"]
  return doc
}

function serializeDoc(doc) {
  let out = doc.preamble.join("\n") + "\n"
  for (const s of doc.order.concat(NAMES.filter(n => !doc.order.includes(n)))) {
    out += `\n## ${s}\n\n`
    const list = ordered(doc.items, s)
    for (const i of list) out += `- [${i.done ? "x" : " "}] ${i.text}\n`
    const notes = doc.notes[s] || []
    if (notes.length) out += (list.length ? "\n" : "") + notes.join("\n") + "\n"
  }
  return out
}

function load() { return parseDoc(todoText).items }

// Datoen etter «frist»/«innen», ellers første dato i teksten. Samme regel som findDate() i Mac-appen:
// 2026-12-01 eller 1. des (eventuelt 1. des 2027). Uten år gjelder i år, eller neste år hvis datoen var for mer enn 30 dager siden.
// Gir { iso: "YYYY-MM-DD", text: teksten som ble funnet, marked: tas bort fra teksten i Frister og Senere } eller null.
function findDate(t) {
  const D = String.raw`(\d{4})-(\d{2})-(\d{2})|\b(\d{1,2})\.\s*(jan|feb|mar|apr|mai|jun|jul|aug|sep|okt|nov|des)[a-zæøå]*(?:\s+(\d{4}))?`
  const withWord = t.match(new RegExp(String.raw`(?:frist|innen)\s+(?:ca\.\s*)?(?:${D})`, "i"))
  const m = withWord || t.match(new RegExp(D, "i"))
  if (!m) return null
  const p = n => String(n).padStart(2, "0")
  if (m[1]) return { iso: `${m[1]}-${m[2]}-${m[3]}`, text: m[0], marked: !!withWord }
  const mo = ["jan", "feb", "mar", "apr", "mai", "jun", "jul", "aug", "sep", "okt", "nov", "des"].indexOf(m[5].toLowerCase())
  const now = new Date()
  let y = m[6] ? +m[6] : now.getFullYear()
  if (!m[6] && new Date(y, mo, +m[4]) < new Date(now.getFullYear(), now.getMonth(), now.getDate() - 30)) y++
  return { iso: `${y}-${p(mo + 1)}-${p(+m[4])}`, text: m[0], marked: true }
}

function dl(t) { return (findDate(t) || {}).iso || "9999" }

function ordered(items, sec) {
  const all = items.filter(i => i.section === sec)
  const open = all.filter(i => !i.done)
  if (DATED.includes(sec)) open.sort((a, b) => dl(a.text).localeCompare(dl(b.text)))
  return open.concat(all.filter(i => i.done))
}
const openIn = (items, sec) => ordered(items, sec).filter(i => !i.done)

// En endring peker på oppgaven med seksjon, tekst, status og n (hvilken av like oppgaver), ikke med plassen i lista.
// Da finnes den igjen selv om fila er endret et annet sted i mellomtiden.
function sameTask(a, b) { return a.section === b.section && a.text === b.text && a.done === b.done }

function refAt(items, i) {
  const it = items[i]
  return { section: it.section, text: it.text, done: it.done, n: items.slice(0, i).filter(o => sameTask(o, it)).length }
}

function locate(items, r) {
  if (!r) return -1
  const exact = []
  items.forEach((it, i) => { if (sameTask(it, r)) exact.push(i) })
  if (exact.length) return exact[Math.min(r.n, exact.length - 1)]
  let i = items.findIndex(it => it.section === r.section && it.text === r.text)
  if (i < 0) i = items.findIndex(it => it.text === r.text && it.done === r.done)
  if (i < 0) i = items.findIndex(it => it.text === r.text)
  return i
}

function insertIndex(items, before, sec) {
  const j = locate(items, before)
  return j >= 0 && items[j].section === sec ? j : items.length
}

function oneLine(t) { return String(t).replace(/\s*\n\s*/g, " ").trim() }

// Endringene: insert, setDone, edit, remove, move og batch. «before» er oppgaven den nye plassen er rett foran (null = nederst).
function applyOp(items, op) {
  if (op.op === "insert") {
    const text = oneLine(op.text)
    if (text) items.splice(insertIndex(items, op.before, op.section), 0, { text, done: !!op.done, section: op.section })
  } else if (op.op === "setDone") {
    const i = locate(items, op.ref)
    if (i < 0 || items[i].done === op.done) return
    const it = items.splice(i, 1)[0]
    it.done = op.done
    items.splice(insertIndex(items, op.before, it.section), 0, it)
  } else if (op.op === "edit") {
    const text = oneLine(op.text)
    const i = locate(items, op.ref)
    if (text && i >= 0) items[i].text = text
  } else if (op.op === "remove") {
    const i = locate(items, op.ref)
    if (i >= 0) items.splice(i, 1)
  } else if (op.op === "move") {
    const i = locate(items, op.ref)
    if (i < 0) return
    const it = items.splice(i, 1)[0]
    it.section = op.section
    items.splice(insertIndex(items, op.before, op.section), 0, it)
  } else if (op.op === "batch") {
    for (const o of op.ops) applyOp(items, o)
  }
}

// Leser fila på nytt rett før lagring og legger endringene oppå.
async function saveOps(ops) {
  const fresh = await readTodo()
  const doc = parseDoc(fresh != null && fresh.trim() ? fresh : todoText)
  for (const op of ops) applyOp(doc.items, op)
  const out = serializeDoc(doc)
  if (out !== fresh) {
    fm.writeString(PATH, out)
    try { local.writeString(CACHE, out) } catch (e) {}
  }
  todoText = out
}

// ---------- Visning ----------
// Fjerner markdown og (i Frister og Senere) «frist …» og korte datoer, som vises som en egen brikke.
function clean(t, sec) {
  let s = t.replace(/\[([^\]]+)\]\([^)]+\)/g, "$1").replace(/\*\*|__|`/g, "")
  const f = DATED.includes(sec) ? findDate(s) : null
  if (f && f.marked) {
    const i = s.indexOf(f.text)
    s = (s.slice(0, i).replace(/,?\s*$/, "") + " " + s.slice(i + f.text.length))
      .replace(/\(\s*\)/g, "").replace(/\(\s*,?\s*/g, "(").replace(/,?\s*\)/g, ")")
  }
  return s.replace(/\s{2,}/g, " ").trim()
}

function due(text) {
  const d = dl(text)
  if (d === "9999") return null
  const [y, m, dd] = d.split("-").map(Number)
  const now = new Date()
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  const days = Math.round((new Date(y, m - 1, dd) - today) / 86400000)
  let label
  if (days < 0) label = "forfalt"
  else if (days === 0) label = "i dag"
  else if (days === 1) label = "i morgen"
  else if (days <= 7) label = `om ${days} d`
  else label = `${dd}. ${MONTHS[m - 1]}` + (y !== today.getFullYear() ? ` ${y}` : "")
  return { label, urgent: days <= 3 }
}

const WHITE = Color.white()
const DIM = new Color("#FFFFFF", 0.45)
const FAINT = new Color("#FFFFFF", 0.1)

function header(parent, sec, n, size) {
  const h = parent.addStack()
  h.centerAlignContent()
  const name = h.addText(sec)
  name.font = Font.boldRoundedSystemFont(size + 1)
  name.textColor = new Color(COLORS[sec])
  h.addSpacer(5)
  const c = h.addText(`${n} igjen`)
  c.font = Font.mediumRoundedSystemFont(size - 2)
  c.textColor = DIM
}

function row(parent, item, sec, size) {
  const r = parent.addStack()
  r.centerAlignContent()
  const sym = SFSymbol.named("circle")
  sym.applyFont(Font.mediumSystemFont(size))
  const img = r.addImage(sym.image)
  img.imageSize = new Size(size, size)
  img.tintColor = new Color(COLORS[sec], 0.85)
  r.addSpacer(7)
  const t = r.addText(clean(item.text, sec))
  t.font = Font.systemFont(size)
  t.textColor = WHITE
  t.lineLimit = 1
  r.addSpacer()
  const d = DATED.includes(sec) ? due(item.text) : null
  if (d) {
    r.addSpacer(6)
    const chip = r.addStack()
    chip.setPadding(1, 6, 1, 6)
    chip.cornerRadius = 6
    chip.backgroundColor = new Color(COLORS[sec], d.urgent ? 0.32 : 0.15)
    const ct = chip.addText(d.label)
    ct.font = Font.semiboldRoundedSystemFont(size - 2)
    ct.textColor = new Color(d.urgent ? "#FF8FA3" : COLORS[sec])
    ct.lineLimit = 1
  }
}

// Fordeler et antall linjer på seksjonene: minst én til hver, så etter prioritet.
function allocate(counts, budget, caps) {
  const out = counts.map(c => Math.min(c, 1))
  let left = budget - out.reduce((a, b) => a + b, 0)
  for (const ignoreCaps of [false, true]) {
    for (let i = 0; i < counts.length && left > 0; i++) {
      const room = counts[i] - out[i]
      const add = Math.min(room, ignoreCaps ? room : Math.max(0, caps[i] - out[i]), left)
      out[i] += add
      left -= add
    }
  }
  return out
}

function mediumWidth() {
  const sw = Device.screenSize().width
  return sw >= 428 ? 364 : sw >= 414 ? 360 : sw >= 390 ? 338 : 329
}

function buildWidget(items, fam) {
  const w = new ListWidget()
  const g = new LinearGradient()
  g.colors = [new Color("#1C1C1E"), new Color("#000000")]
  g.locations = [0, 1]
  w.backgroundGradient = g
  w.setPadding(14, 15, 12, 15)
  w.url = URLScheme.forRunningScript()
  w.refreshAfterDate = new Date(Date.now() + 15 * 60 * 1000)

  if (todoText === null) {
    const e = w.addText("Fant ikke todo.md. Åpne Scriptable og kjør NotchTodo én gang.")
    e.font = Font.mediumRoundedSystemFont(12)
    e.textColor = DIM
    return w
  }

  const counts = WIDGET_NAMES.map(n => openIn(items, n).length)
  const total = counts.reduce((a, b) => a + b, 0)
  if (total === 0) {
    w.addSpacer()
    const t = w.addText("Alt gjort 🎉")
    t.font = Font.boldRoundedSystemFont(16)
    t.textColor = WHITE
    t.centerAlignText()
    w.addSpacer()
    return w
  }

  if (fam === "small") {
    const top = w.addStack()
    top.centerAlignContent()
    const tt = top.addText("Todo")
    tt.font = Font.boldRoundedSystemFont(15)
    tt.textColor = WHITE
    top.addSpacer()
    const tc = top.addText(String(total))
    tc.font = Font.boldRoundedSystemFont(15)
    tc.textColor = DIM
    w.addSpacer(8)
    const list = []
    for (const n of WIDGET_NAMES) for (const it of openIn(items, n)) list.push([it, n])
    for (const [it, n] of list.slice(0, 5)) {
      const r = w.addStack()
      r.centerAlignContent()
      const dot = r.addStack()
      dot.size = new Size(6, 6)
      dot.cornerRadius = 3
      dot.backgroundColor = new Color(COLORS[n])
      r.addSpacer(6)
      const t = r.addText(clean(it.text, n))
      t.font = Font.systemFont(11.5)
      t.textColor = WHITE
      t.lineLimit = 1
      w.addSpacer(5)
    }
    w.addSpacer()
    return w
  }

  if (fam === "medium") {
    // To kolonner som i notchet: Viktig og Frister (Generelle tar plassen hvis en av dem er tom).
    const shown = WIDGET_NAMES.filter(n => openIn(items, n).length > 0).slice(0, 2)
    const colW = shown.length === 2 ? (mediumWidth() - 30 - 21) / 2 : mediumWidth() - 30
    const cols = w.addStack()
    cols.topAlignContent()
    shown.forEach((n, i) => {
      if (i > 0) {
        cols.addSpacer(10)
        const div = cols.addStack()
        div.size = new Size(1, 118)
        div.backgroundColor = FAINT
        cols.addSpacer(10)
      }
      const col = cols.addStack()
      col.layoutVertically()
      col.size = new Size(colW, 0)
      const open = openIn(items, n)
      header(col, n, open.length, 12)
      col.addSpacer(6)
      for (const it of open.slice(0, 5)) {
        row(col, it, n, 12)
        col.addSpacer(4)
      }
    })
    w.addSpacer()
    return w
  }

  // Stor: de tre seksjonene under hverandre (Senere vises bare i appen).
  const top = w.addStack()
  top.centerAlignContent()
  const tt = top.addText("Todo")
  tt.font = Font.boldRoundedSystemFont(17)
  tt.textColor = WHITE
  top.addSpacer()
  const df = new DateFormatter()
  df.locale = "nb_NO"
  df.dateFormat = "EEEE d. MMM"
  const dt = top.addText(df.string(new Date()))
  dt.font = Font.mediumRoundedSystemFont(12)
  dt.textColor = DIM
  w.addSpacer(10)

  const active = counts.filter(c => c > 0).length
  const budget = Math.max(active, Math.floor((300 - 32 * active) / 21))
  const alloc = allocate(counts, budget, [4, 4, 3])
  WIDGET_NAMES.forEach((n, i) => {
    if (counts[i] === 0) return
    header(w, n, counts[i], 13)
    w.addSpacer(5)
    for (const it of openIn(items, n).slice(0, alloc[i])) {
      row(w, it, n, 13)
      w.addSpacer(5)
    }
    w.addSpacer(6)
  })
  w.addSpacer()
  return w
}

// ---------- App (trykk på widgeten) ----------
// En egen side i fullskjerm med samme farger som notchet. Hver endring sendes tilbake hit og lagres i todo.md.

const CSS = `
:root { color-scheme: dark; }
* { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
html, body { background: #000; }
body {
  margin: 0; color: #fff;
  font: 16px/1.35 -apple-system, system-ui, sans-serif;
  padding: calc(env(safe-area-inset-top) + 18px) 16px calc(env(safe-area-inset-bottom) + 60px);
  -webkit-user-select: none; user-select: none;
}
.top { display: flex; align-items: flex-end; justify-content: space-between; margin: 0 4px 18px; }
h1 { margin: 0; font: 700 34px ui-rounded, -apple-system, sans-serif; letter-spacing: -0.5px; }
.date { margin-top: 2px; color: rgba(255,255,255,.45); font: 500 14px ui-rounded, -apple-system, sans-serif; }
.date::first-letter { text-transform: uppercase; }
.pill { border: 0; border-radius: 999px; padding: 7px 13px; background: rgba(255,255,255,.1); color: rgba(255,255,255,.75);
  font: 500 13px ui-rounded, -apple-system, sans-serif; }
.pill[hidden] { display: none; }
.sec { background: linear-gradient(180deg, #17171a, #0e0e10); border: 1px solid rgba(255,255,255,.07);
  border-radius: 24px; padding: 16px 14px 12px; margin-bottom: 14px; }
.sh { display: flex; align-items: baseline; gap: 8px; margin: 0 4px 6px; }
.name { font: 700 19px ui-rounded, -apple-system, sans-serif; color: var(--c); }
.cnt { font: 500 12.5px ui-rounded, -apple-system, sans-serif; color: rgba(255,255,255,.45); }
ul { list-style: none; margin: 0; padding: 0; }
li { display: flex; align-items: flex-start; gap: 11px; padding: 10px 4px; border-top: 1px solid rgba(255,255,255,.055);
  transition: opacity .25s; }
li:first-child { border-top: 0; }
li.empty { color: rgba(255,255,255,.35); font-size: 14px; }
.chk { flex: none; width: 23px; height: 23px; margin-top: -1px; padding: 0; border-radius: 50%;
  border: 2px solid var(--c); background: transparent; opacity: .9; display: grid; place-items: center;
  transition: background .2s, border-color .2s, transform .15s; }
.chk:active { transform: scale(.85); }
li.done .chk { background: #30D158; border-color: #30D158; }
li.done .chk::after { content: ""; width: 6px; height: 11px; border: solid #000; border-width: 0 2.5px 2.5px 0;
  transform: translate(0, -1px) rotate(45deg); }
.txt { flex: 1; min-width: 0; font-size: 16px; overflow-wrap: anywhere; }
li.done .txt { color: rgba(255,255,255,.35); text-decoration: line-through; }
li.done { opacity: .8; }
.chip { flex: none; margin-top: 1px; padding: 3px 8px; border-radius: 8px; font: 600 12.5px ui-rounded, -apple-system, sans-serif;
  color: var(--c); background: color-mix(in srgb, var(--c) 16%, transparent); }
.chip.urgent { color: #FF8FA3; background: color-mix(in srgb, var(--c) 34%, transparent); }
.ed { flex: 1; min-width: 0; }
textarea.edit { width: 100%; resize: none; border: 0; outline: none; margin: -4px 0 0; padding: 4px 8px; border-radius: 10px;
  background: rgba(255,255,255,.1); color: #fff; font: 16px/1.35 -apple-system, system-ui, sans-serif; overflow: hidden;
  -webkit-user-select: text; user-select: text; }
.actions { display: flex; flex-wrap: wrap; gap: 7px; margin-top: 9px; }
.actions button { border: 0; border-radius: 999px; padding: 6px 11px; font: 600 12.5px ui-rounded, -apple-system, sans-serif;
  color: var(--c); background: color-mix(in srgb, var(--c) 16%, transparent); }
.actions .del { --c: #FF453A; }
.add { display: flex; gap: 8px; margin-top: 8px; }
.add input { min-width: 0; border: 0; outline: none; border-radius: 13px; padding: 12px 13px; color: #fff; font-size: 16px;
  background: rgba(255,255,255,.07); transition: box-shadow .2s, background .2s; -webkit-user-select: text; user-select: text; }
.add input[type=text] { flex: 1; }
.add input[type=date] { flex: none; width: 128px; color: rgba(255,255,255,.7); }
.add input:focus { background: rgba(255,255,255,.11); box-shadow: 0 0 0 1.5px var(--c); }
.add input::placeholder { color: rgba(255,255,255,.35); }
`

// Kjøres inne i siden. Bruker NAMES, COLORS, dl, due, clean, ordered og applyOp, som legges inn i siden fra dette scriptet.
function pageMain(DATA, DATE) {
  let items = DATA
  let editing = null
  let busy = false
  let queue = []

  // Scriptable spør jevnlig etter endringer med takeChanges() og legger dem oppå fila.
  window.takeChanges = () => {
    if (!queue.length) return ""
    const out = JSON.stringify(queue)
    queue = []
    return out
  }
  // Fila slik den er etter lagring, med endringer fra Mac-en. Vent hvis noe er på vei eller redigeres.
  window.sync = fresh => {
    if (queue.length || editing || busy) return false
    if (JSON.stringify(fresh) !== JSON.stringify(items)) {
      items = fresh
      renderAll()
    }
    return true
  }
  const act = op => { applyOp(items, op); queue.push(op) }
  const ref = it => refAt(items, items.indexOf(it))
  const esc = s => s.replace(/[&<>"]/g, ch => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[ch]))

  document.body.innerHTML = `
    <div class="top">
      <div><h1>Todo</h1><div class="date">${esc(DATE)}</div></div>
      <button class="pill" id="clear" hidden>Fjern ferdige</button>
    </div>
    ${NAMES.map(n => `
      <section class="sec" data-s="${n}" style="--c:${COLORS[n]}">
        <div class="sh"><span class="name">${n}</span><span class="cnt"></span></div>
        <ul></ul>
        <form class="add">
          <input type="text" placeholder="${DATED.includes(n) ? "Ny frist …" : "Ny oppgave …"}" enterkeyhint="done" autocomplete="off">
          ${DATED.includes(n) ? '<input type="date">' : ""}
        </form>
      </section>`).join("")}`

  function renderList(sec) {
    const el = document.querySelector(`[data-s="${sec}"]`)
    const list = ordered(items, sec)
    el.querySelector(".cnt").textContent = `${list.filter(i => !i.done).length} igjen`
    const ul = el.querySelector("ul")
    if (list.length === 0) { ul.innerHTML = '<li class="empty">Tomt 🎉</li>'; return }
    ul.innerHTML = list.map(it => {
      const k = items.indexOf(it)
      if (it === editing) {
        const moves = NAMES.filter(n => n !== sec)
          .map(n => `<button data-move="${n}" style="--c:${COLORS[n]}">→ ${n}</button>`).join("")
        return `<li data-k="${k}"><button class="chk"></button><div class="ed">
          <textarea class="edit" rows="1" enterkeyhint="done">${esc(it.text)}</textarea>
          <div class="actions">${moves}<button class="del">Slett</button></div></div></li>`
      }
      const d = DATED.includes(sec) && !it.done ? due(it.text) : null
      return `<li data-k="${k}" class="${it.done ? "done" : ""}"><button class="chk" aria-label="Kryss av"></button>
        <div class="txt">${esc(clean(it.text, sec))}</div>
        ${d ? `<span class="chip ${d.urgent ? "urgent" : ""}">${esc(d.label)}</span>` : ""}</li>`
    }).join("")
  }

  function renderAll() {
    NAMES.forEach(renderList)
    document.getElementById("clear").hidden = !items.some(i => i.done)
    const ta = document.querySelector("textarea.edit")
    if (ta) {
      autosize(ta)
      ta.focus()
      ta.setSelectionRange(ta.value.length, ta.value.length)
    }
  }

  function autosize(ta) { ta.style.height = "auto"; ta.style.height = ta.scrollHeight + "px" }

  // Tar med teksten fra redigeringsfeltet før en annen handling.
  function takeEditText() {
    const ta = document.querySelector("textarea.edit")
    if (!ta || !editing) return false
    const v = oneLine(ta.value)
    if (v && v !== editing.text) { act({ op: "edit", ref: ref(editing), text: v }); return true }
    return false
  }

  function commitEdit() {
    if (!editing) return
    takeEditText()
    editing = null
    renderAll()
  }

  document.addEventListener("click", e => {
    if (busy) return
    if (e.target.closest("#clear")) {
      const refs = []
      for (let i = items.length - 1; i >= 0; i--) if (items[i].done) refs.push(refAt(items, i))
      act({ op: "batch", ops: refs.map(r => ({ op: "remove", ref: r })) })
      editing = null
      renderAll()
      return
    }
    const li = e.target.closest("li[data-k]")
    if (!li) return
    const it = items[+li.dataset.k]
    const move = e.target.closest("[data-move]")
    if (move) {
      takeEditText()
      act({ op: "move", ref: ref(it), section: move.dataset.move, before: null })
      editing = null
      renderAll()
    } else if (e.target.closest(".del")) {
      act({ op: "remove", ref: ref(it) })
      editing = null
      renderAll()
    } else if (e.target.closest(".chk")) {
      const changed = takeEditText()
      editing = null
      act({ op: "setDone", ref: ref(it), done: !it.done, before: null })
      li.classList.toggle("done", it.done)
      busy = true
      setTimeout(() => { busy = false; renderAll() }, changed ? 0 : 380)
    } else if (e.target.closest(".txt")) {
      if (editing) takeEditText()
      editing = it
      renderAll()
    }
  })

  document.addEventListener("focusout", e => {
    if (e.target.matches("textarea.edit")) {
      const was = editing
      setTimeout(() => { if (editing === was) commitEdit() }, 150)
    }
  })
  document.addEventListener("input", e => { if (e.target.matches("textarea.edit")) autosize(e.target) })
  document.addEventListener("keydown", e => {
    if (e.target.matches("textarea.edit") && e.key === "Enter") { e.preventDefault(); e.target.blur() }
  })

  document.addEventListener("submit", e => {
    e.preventDefault()
    const f = e.target
    const sec = f.closest(".sec").dataset.s
    const input = f.querySelector("input[type=text]")
    const date = f.querySelector("input[type=date]")
    let text = input.value.trim()
    if (!text) return
    if (date && date.value) {
      // Kort form som (1. des), med år bare når året ellers ville blitt feil.
      const [y, m, d] = date.value.split("-").map(Number)
      const short = `${d}. ${MONTHS[m - 1].replace(".", "")}`
      text += findDate(short).iso === date.value ? ` (${short})` : ` (${short} ${y})`
    }
    act({ op: "insert", text, done: false, section: sec, before: null })
    input.value = ""
    if (date) date.value = ""
    renderList(sec)
    document.getElementById("clear").hidden = !items.some(i => i.done)
    input.focus()
  })

  renderAll()
}

function pageHTML(items) {
  const df = new DateFormatter()
  df.locale = "nb_NO"
  df.dateFormat = "EEEE d. MMMM"
  const json = v => JSON.stringify(v).replace(/</g, "\\u003c")
  return `<!doctype html><html lang="no"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover">
<style>${CSS}</style>
<script>
window.onerror = function (m, s, l, c) {
  var show = function () {
    document.body.innerHTML = '<pre style="color:#FF453A;white-space:pre-wrap;font:14px -apple-system;padding:40px 4px">Feil i NotchTodo: ' + m + ' (linje ' + l + ':' + c + ')</pre>'
  }
  if (document.body) show(); else document.addEventListener("DOMContentLoaded", show)
}
</script></head><body><p style="color:rgba(255,255,255,.4);font:15px -apple-system;padding:40px 4px">Laster …</p><script>
const NAMES = ${json(NAMES)};
const DATED = ${json(DATED)};
const COLORS = ${json(COLORS)};
const MONTHS = ${json(MONTHS)};
${findDate}
${dl}
${due}
${clean}
${ordered}
${sameTask}
${refAt}
${locate}
${insertIndex}
${oneLine}
${applyOp}
(${pageMain})(${json(items)}, ${json(df.string(new Date()))});
</script></body></html>`
}

async function openApp() {
  const wv = new WebView()
  await wv.loadHTML(pageHTML(load()))
  let closed = false
  const shown = wv.present(true).then(() => { closed = true })
  let tick = 0
  let pending = false  // siden har ikke fått siste utgave av fila ennå
  const flush = async () => {
    let ops = []
    try {
      const r = await wv.evaluateJavaScript("window.takeChanges ? takeChanges() : ''")
      if (r) ops = JSON.parse(r)
    } catch (e) {}
    if (ops.length) {
      await saveOps(ops)
      pending = true
    } else if (++tick % 5 === 0) {
      // Omtrent hvert andre sekund: se etter endringer fra Mac-en eller assistenten.
      const fresh = await readTodo()
      if (fresh != null && fresh !== todoText) { todoText = fresh; pending = true }
    }
    if (pending && !closed) {
      try {
        const ok = await wv.evaluateJavaScript(`window.sync ? sync(${JSON.stringify(load())}) : false`)
        if (ok) pending = false
      } catch (e) {}
    }
  }
  while (!closed) {
    await new Promise(r => Timer.schedule(400, false, r))
    await flush()
  }
  await flush()
}

if (config.runsInWidget) {
  Script.setWidget(buildWidget(load(), config.widgetFamily || "medium"))
} else {
  await openApp()
}
Script.complete()
