// 笔记编辑器（TipTap）。由 Swift 的 WKWebView 加载，也可以在浏览器里用假的宿主测试。
//
// 与宿主（Swift）的约定：
//   宿主 → 页面：window.noteEditor.init({noteId, content, accent, assetBase})
//                window.noteEditor.getJSON()        → 正文 JSON 字符串（保存时取）
//                window.noteEditor.cursorInBody()   → 光标是否在正文（「插入排盘」前检查）
//                window.noteEditor.insertChart(id)  → 在光标处插入排盘卡片
//   页面 → 宿主：host.call(cmd, params)  → Promise，转发给后端命令（chart_get / attachment_add）
//                host.notify(event, data) → 'ready' / 'changed' / 'openChart'
//
// 正文存的是 editor.getJSON()：
//   排盘：{type: 'chart', attrs: {id}}
//   图片：{type: 'image', attrs: {src: 'attachment:<文件名>', alt, width: '480px', align: 'left'|'center'|'right'}}
//         （旧笔记的 width 是百分比，如 '50%'：显示时按 480 宽换成像素）
//   颜色：{type: 'textColor', attrs: {c: 'red'}}（固定色板，只存颜色名）
import {
  Editor, Node, Mark, StarterKit, Underline, Highlight, Image, Placeholder,
  Table, TableRow, TableCell, TableHeader,
} from './ne-deps.mjs'

// ---------- 宿主桥 ----------
const host = {
  call(cmd, params = {}) {
    const h = window.webkit?.messageHandlers?.bridge
    if (h) {
      return h.postMessage({ cmd, params }).then(text => {
        const r = JSON.parse(text)
        if (r && r.error) throw new Error(r.error)
        return r
      })
    }
    if (window.__mockHost) return window.__mockHost.call(cmd, params)
    return Promise.reject(new Error('没有宿主'))
  },
  notify(event, data = {}) {
    const h = window.webkit?.messageHandlers?.notify
    if (h) h.postMessage({ event, ...data })
    else window.__mockHost?.notify?.(event, data)
  },
}

let noteId = null
let assetBase = 'noteeditor://asset/'
let editor = null
let bodyActive = false     // 光标是否在正文里
let lastBlur = 0           // 正文最近一次失去焦点的时间

const ATTACHMENT = 'attachment:'
const displaySrc = src => (src && src.startsWith(ATTACHMENT) ? assetBase + encodeURIComponent(src.slice(ATTACHMENT.length)) : src)

function toast(msg) {
  const t = document.getElementById('toast')
  t.textContent = msg
  t.classList.add('show')
  clearTimeout(toast.timer)
  toast.timer = setTimeout(() => t.classList.remove('show'), 2600)
}

function el(tag, cls, text) {
  const e = document.createElement(tag)
  if (cls) e.className = cls
  if (text != null) e.textContent = text
  return e
}

// ---------- 文字颜色：固定色板，存 class 名 ----------
const COLORS = [
  ['red', '红'], ['orange', '橙'], ['yellow', '黄'], ['green', '绿'],
  ['blue', '蓝'], ['purple', '紫'], ['gray', '灰'],
]
const COLOR_NAMES = new Set(COLORS.map(c => c[0]))

const TextColor = Mark.create({
  name: 'textColor',
  addAttributes() {
    return {
      c: {
        default: null,
        parseHTML: el => {
          const m = el.className.match(/\bc-(\w+)/)
          return m && COLOR_NAMES.has(m[1]) ? m[1] : null
        },
        renderHTML: a => (a.c ? { class: 'c-' + a.c } : {}),
      },
    }
  },
  parseHTML() { return [{ tag: 'span[class*="c-"]' }] },
  renderHTML({ HTMLAttributes }) { return ['span', HTMLAttributes, 0] },
  addCommands() {
    return {
      setTextColor: c => ({ commands }) => commands.setMark(this.name, { c }),
      unsetTextColor: () => ({ commands }) => commands.unsetMark(this.name),
    }
  },
})

// ---------- 排盘卡片 ----------
const chartCache = new Map()
function loadChart(id) {
  if (!chartCache.has(id)) {
    const p = host.call('chart_get', { chart_id: id })
    p.catch(() => chartCache.delete(id))      // 失败了下次再试
    chartCache.set(id, p)
  }
  return chartCache.get(id)
}

const WUXING = {}
for (const [chars, cls] of [['甲乙寅卯', 'wood'], ['丙丁巳午', 'fire'], ['戊己辰戌丑未', 'earth'],
                             ['庚辛申酉', 'metal'], ['壬癸子亥', 'water']]) {
  for (const ch of chars) WUXING[ch] = `var(--wx-${cls})`
}

function ganzhiChar(ch) {
  const s = el('span', 'gz', ch)
  if (WUXING[ch]) s.style.color = WUXING[ch]
  return s
}

// 三爻卦（从下往上的阴阳）→ 五行。只给旧快照兜底用：新存的盘，后端已经在 trigrams 里给了五行
const TRIGRAM_WUXING = {
  '111': '金', '110': '金', '101': '火', '100': '木',   // 乾 兌 離 震
  '011': '木', '010': '水', '001': '土', '000': '土',   // 巽 坎 艮 坤
}
function trigramWuxing(hex) {
  if (hex.trigrams) return [hex.trigrams.lower.wuxing, hex.trigrams.upper.wuxing]
  const key = a => a.join('')
  return [TRIGRAM_WUXING[key(hex.lines.slice(0, 3))], TRIGRAM_WUXING[key(hex.lines.slice(3, 6))]]
}

function miniHex(lines, moving = new Set(), wuxing = []) {
  const box = el('div', 'mini-hex')
  for (let i = lines.length - 1; i >= 0; i--) {         // lines[0] 是初爻，画在最下面
    const yao = el('div', 'yao ' + (lines[i] === 1 ? 'yang' : 'yin'))
    const wx = wuxing[i < 3 ? 0 : 1]                    // 下卦三爻用下卦五行，上卦三爻用上卦五行
    if (wx) yao.dataset.wx = wx                         // 颜色由 body.wx-on 的 CSS 决定，切换不用重画
    yao.append(el('span'))
    if (lines[i] !== 1) yao.append(el('span'))
    if (moving.has(i)) yao.classList.add('moving')
    box.append(yao)
  }
  return box
}

function guaBlock(hex, label, moving) {
  const g = el('div', 'gua')
  g.append(el('div', 'name', hex.name), miniHex(hex.lines, moving, trigramWuxing(hex)), el('div', 'lbl', label))
  return g
}

function guaPair(org, chg) {
  const pair = el('div', 'gua-pair')
  const moving = new Set()
  org.lines.forEach((v, i) => { if (v !== chg.lines[i]) moving.add(i) })
  if (moving.size === 0) {
    pair.append(guaBlock(org, '本卦'))
  } else {
    // 和 DualGuaView 一样：只在本卦的动爻旁画 →，两卦中间不再画大箭头（否则动爻在中间时会出现两个箭头）
    pair.append(guaBlock(org, '本卦', moving), guaBlock(chg, '变卦'))
  }
  return pair
}

// 通用卡片：不是内置三种的排盘（如插件）在快照里带 card，照着画一排卦（格式见后端 casebook/charts.py）
function guaRow(guas) {
  const row = el('div', 'gua-row')
  for (const g of guas || []) {
    if (Array.isArray(g.lines)) row.append(guaBlock(g, g.label || ''))
  }
  return row
}

/** 梅花数字起卦 / 指定起卦：卡片抬头写怎么起的卦（时间起卦写时间）。 */
const TRIGRAMS = ['乾', '兑', '离', '震', '巽', '坎', '艮', '坤']
const LINES = ['初爻', '二爻', '三爻', '四爻', '五爻', '上爻']
function meihuaMethodText(q) {
  if (q?.method === 'number') return '数字起卦 ' + (q.numbers || []).join('·')
  if (q?.method === 'specified') return `指定起卦 上${TRIGRAMS[q.upper - 1] ?? '?'}下${TRIGRAMS[q.lower - 1] ?? '?'} ${LINES[q.moving_line - 1] ?? ''}动`
  return ''
}

function head(...parts) {
  const h = el('div', 'cc-head')
  parts.filter(Boolean).forEach((p, i) => {
    if (i > 0) h.append(' · ')
    if (i === 0) h.append(el('b', null, p)); else h.append(p)
  })
  return h
}

function renderCard(dom, chart) {
  const s = chart.snapshot || {}
  const body = []
  if (chart.type === 'bazi') {
    const c = s.chart
    const pillars = el('div', 'bazi-pillars')
    for (const [lbl, key] of [['年柱', 'year'], ['月柱', 'month'], ['日柱', 'day'], ['时柱', 'hour']]) {
      const p = el('div', 'pillar')
      const gz = [...c.pillars[key].ganzhi]
      p.append(el('div', 'lbl', lbl), ganzhiChar(gz[0]), ganzhiChar(gz[1]))
      pillars.append(p)
    }
    body.push(head('八字', s.name, c.gender, c.input_time), pillars)
  } else if (chart.type === 'iching') {
    body.push(head('易经速查'), guaPair(s.original, s.changed))
  } else if (chart.type === 'meihua') {
    body.push(head('梅花易数', (s.bazi?.input_time || '').slice(0, 16) || meihuaMethodText(s.qigua)), guaPair(s.original, s.changed))
  } else if (s.card) {
    const c = s.card
    body.push(head(c.title || '排盘', c.subtitle), guaRow(c.guas))
  } else {
    body.push(head('排盘'), el('div', 'cc-missing', '这个版本还不支持显示这种排盘'))
  }
  dom.replaceChildren(...body, dom.querySelector('.cc-del'))
  renderBelow(dom.parentElement?.querySelector('.chart-below'), chart)
}

/** 卡片外面、下方：所问之事（chart.title）在上，一排特点在下（可以左右滑）。都没有就不占地方。 */
function renderBelow(box, chart) {
  if (!box) return
  const parts = []
  if (chart.title) parts.push(el('div', 'cc-question', chart.title))
  if (chart.tags?.length) {
    const row = el('div', 'cc-tags')
    for (const t of chart.tags) {
      const chip = el('span', 'cc-tag', t.name.length > 8 ? t.name.slice(0, 8) + '…' : t.name)   // 最多 8 个字
      chip.title = t.name
      row.append(chip)
    }
    parts.push(row)
  }
  if (!parts.length) { box.replaceChildren(); return }
  const inner = el('div', 'chart-below-inner')
  inner.append(...parts)
  box.replaceChildren(inner)
}

// 正文里的卡片，按排盘 id 记下来：排盘窗口里改了所问之事 / 特点，宿主调 refreshChart 重画这些卡片
const cardViews = new Map()          // id → Set<{card, labels}>

function refreshChartCards(id) {
  chartCache.delete(id)
  const views = cardViews.get(id)
  if (!views) return
  for (const v of [...views]) {
    if (!v.card.isConnected) { views.delete(v); continue }
    loadChart(id).then(c => { renderCard(v.card, c); renderChartLabels(v.labels, c) }).catch(() => {})
  }
}

// ---------- 排盘卡片旁的标签：加 / 删立刻存进数据库（和插入排盘一样，不等保存） ----------
// 新加的标签排在最后（后端按添加先后返回），所以新标签往下加，不会把旧的往下顶。
const labelBoxes = new Map()       // 标签区 → 它的排盘；标签被彻底删除时，所有卡片一起刷新

/** 某个标签被彻底删除：所有卡片上去掉它。 */
function dropLabelEverywhere(labelId) {
  for (const [box, chart] of labelBoxes) {
    if (!box.isConnected) { labelBoxes.delete(box); continue }
    if ((chart.labels || []).some(l => l.id === labelId)) {
      chart.labels = chart.labels.filter(l => l.id !== labelId)
      renderChartLabels(box, chart)
    }
  }
}

function renderChartLabels(box, chart) {
  labelBoxes.set(box, chart)
  box.replaceChildren()
  // 标签放在 .cl-chips 里：标签多了在这里面竖向滚动；「＋ 标签」和浮窗在外面，不会被滚动区裁掉
  const chips = el('div', 'cl-chips')
  for (const l of chart.labels || []) {
    const chip = el('span', 'cl-chip')
    chip.title = l.name                                   // 名字太长被省略时，悬停看全名
    chip.append(el('span', 'cl-name', l.name))
    const x = el('button', 'cl-x', '×')
    x.title = '去掉这个标签'
    x.addEventListener('click', async e => {
      e.stopPropagation()
      try {
        chart.labels = (await host.call('chart_label_remove', { chart_id: chart.id, label_id: l.id })).labels
        renderChartLabels(box, chart)
      } catch (err) { toast('去掉标签失败：' + err.message) }
    })
    chip.append(x)
    chips.append(chip)
  }
  if (chips.childElementCount) box.append(chips)
  const add = el('button', 'cl-add', '＋ 标签')
  add.addEventListener('click', e => { e.stopPropagation(); openLabelPopover(box, add, chart) })
  box.append(add)
}

function openLabelPopover(box, anchorBtn, chart) {
  document.querySelectorAll('.cl-pop').forEach(p => p.remove())
  const pop = el('div', 'cl-pop')
  const input = el('input')
  input.placeholder = '搜索或新建，如：疾病'
  input.maxLength = 20
  const list = el('div', 'cl-list')
  pop.append(input, list)
  box.append(pop)
  box.classList.add('open')
  const close = () => {
    pop.remove()
    box.classList.remove('open')
    document.removeEventListener('mousedown', outside, true)
  }
  const outside = e => { if (!pop.contains(e.target) && e.target !== anchorBtn) close() }
  document.addEventListener('mousedown', outside, true)

  const addByName = async name => {
    name = name.trim()
    if (!name) return
    try {
      chart.labels = (await host.call('chart_label_add', { chart_id: chart.id, name })).labels
      close()
      renderChartLabels(box, chart)
    } catch (err) { toast('添加标签失败：' + err.message) }
  }
  const refresh = async () => {
    const kw = input.value.trim()
    let found = []
    try { found = (await host.call('label_search', { keyword: kw })).labels } catch { /* 搜不到就只显示新建 */ }
    const have = new Set((chart.labels || []).map(l => l.id))
    list.replaceChildren()
    for (const l of found.filter(l => !have.has(l.id))) {
      const row = el('div', 'cl-row')
      const b = el('button', 'cl-item', l.name)
      b.title = l.name
      b.addEventListener('click', () => addByName(l.name))
      const x = el('button', 'cl-del', '×')
      x.title = '彻底删除这个标签'
      x.addEventListener('click', async e => {
        e.stopPropagation()
        const detail = l.uses > 0
          ? `有 ${l.uses} 处笔记或排盘正在用这个标签，删除后它们上面的这个标签都会被去掉，无法恢复。`
          : '删除后无法恢复。'
        if (!confirm(`删除标签「${l.name}」？\n${detail}`)) return
        try {
          await host.call('label_delete', { label_id: l.id })
          dropLabelEverywhere(l.id)
          host.notify('labelDeleted', { id: l.id })     // 让 Swift 那边的笔记标签行也去掉
          refresh()
        } catch (err) { toast('删除标签失败：' + err.message) }
      })
      row.append(b, x)
      list.append(row)
    }
    if (kw && !found.some(l => l.name === kw)) {
      const b = el('button', 'cl-item cl-new', `新建标签「${kw}」`)
      b.addEventListener('click', () => addByName(kw))
      list.append(b)
    }
  }
  input.addEventListener('input', refresh)
  input.addEventListener('keydown', e => {
    if (e.key === 'Enter') { e.preventDefault(); addByName(input.value) }
    if (e.key === 'Escape') { e.preventDefault(); close() }
  })
  refresh()
  input.focus()
}

const ChartCard = Node.create({
  name: 'chart',
  group: 'block',
  atom: true,            // 整体：光标进不去，只能整体选中 / 拖动 / 删除
  selectable: true,
  draggable: true,
  addAttributes() {
    return {
      id: {
        default: null,
        parseHTML: el => Number(el.getAttribute('data-chart-id')),
        renderHTML: a => ({ 'data-chart-id': a.id }),
      },
    }
  },
  parseHTML() { return [{ tag: 'div[data-chart-id]' }] },
  renderHTML({ HTMLAttributes }) { return ['div', HTMLAttributes] },
  addNodeView() {
    return ({ node, getPos, editor }) => {
      // 外层 wrap：卡片居中；标签挂在卡片右边（absolute，不影响卡片居中）
      const wrap = el('div', 'chart-wrap')
      wrap.contentEditable = 'false'
      const anchor = el('div', 'chart-anchor')
      const card = el('div', 'chart-card')
      const labels = el('div', 'chart-labels')
      const below = el('div', 'chart-below')        // 卡片外、下方：所问之事 + 特点（宽度跟卡片一样）
      anchor.append(card, below, labels)
      wrap.append(anchor)

      const del = el('button', 'cc-del', '×')
      del.title = '从正文中删除这个排盘'
      del.addEventListener('mousedown', e => e.preventDefault())
      del.addEventListener('click', e => {
        e.stopPropagation()
        const pos = getPos()
        editor.chain().focus().deleteRange({ from: pos, to: pos + node.nodeSize }).run()
      })
      card.append(head('排盘', '载入中…'), del)
      if (!cardViews.has(node.attrs.id)) cardViews.set(node.attrs.id, new Set())
      cardViews.get(node.attrs.id).add({ card, labels })
      loadChart(node.attrs.id)
        .then(c => { renderCard(card, c); renderChartLabels(labels, c) })
        .catch(() => card.replaceChildren(head('排盘'), el('div', 'cc-missing', '这个排盘已被删除'), del))
      card.addEventListener('click', e => {
        if (e.target === del) return
        host.notify('openChart', { id: node.attrs.id })
      })
      return {
        dom: wrap,
        // 标签区里的点击、打字由我们自己处理，编辑器不要管（否则会选中卡片、把字打进正文）
        stopEvent: e => !!e.target.closest?.('.chart-labels'),
        ignoreMutation: () => true,
      }
    }
  },
  addCommands() {
    return { insertChart: id => ({ commands }) => commands.insertContent({ type: 'chart', attrs: { id } }) }
  },
})

// ---------- 图片：只接受存进 App 的图片（attachment:），宽度存像素 ----------
// 以前存百分比：窗口一放大图片就跟着放大。现在存像素，窗口变宽图片不变；窗口比图窄时 CSS 让它缩到放得下。
const IMG_REF_WIDTH = 480          // 旧笔记的百分比按这个宽度（默认窗口的正文宽）换成像素
const IMG_MIN_WIDTH = 40

/** attrs.width → 像素数（旧的 '50%' 按 IMG_REF_WIDTH 换算）；没有就 null。 */
function widthPx(w) {
  if (w == null || w === '') return null
  const s = String(w)
  const n = parseFloat(s)
  if (!isFinite(n)) return null
  return Math.round(s.endsWith('%') ? (n / 100) * IMG_REF_WIDTH : n)
}

let ctxImagePos = null             // 右键点中的那张图在文档里的位置（右键菜单的各项操作都对它）

const ResizableImage = Image.extend({
  draggable: true,
  addAttributes() {
    return {
      ...this.parent?.(),
      width: {
        default: null,
        parseHTML: el => el.getAttribute('width'),
        renderHTML: a => (a.width ? { width: a.width } : {}),
      },
      align: {
        default: 'left',
        parseHTML: el => el.getAttribute('data-align') || 'left',
        renderHTML: a => ({ 'data-align': a.align }),
      },
    }
  },
  parseHTML() {
    // 从网页复制来的外链图片不收（App 不联网、也不该依赖外部链接）
    return [{ tag: 'img[src]', getAttrs: el => (el.getAttribute('src').startsWith(ATTACHMENT) ? {} : false) }]
  },
  addNodeView() {
    return ({ node, getPos, editor }) => {
      const box = el('div', 'img-box')
      const img = document.createElement('img')
      img.crossOrigin = 'anonymous'                   // 裁剪要把图画进 canvas：跨域加载（宿主给了 ACAO 头）才不会被「污染」
      const handle = el('span', 'handle')
      const size = el('span', 'size')
      box.append(img, handle, size)
      const apply = n => {
        const src = displaySrc(n.attrs.src)
        if (img.getAttribute('src') !== src) img.src = src
        img.alt = n.attrs.alt || ''
        box.style.width = (widthPx(n.attrs.width) ?? IMG_REF_WIDTH) + 'px'
        box.dataset.align = n.attrs.align || 'left'
      }
      // 不超过原图的像素宽度（小图不放大到发糊）
      img.addEventListener('load', () => {
        if (img.naturalWidth) box.style.maxWidth = `min(100%, ${img.naturalWidth}px)`
      })
      // 右键：记下是哪张图、选中它，告诉宿主（宿主据此换成图片专用的右键菜单）
      box.addEventListener('contextmenu', () => {
        const pos = getPos()
        if (typeof pos !== 'number') return
        ctxImagePos = pos
        editor.commands.setNodeSelection(pos)
        host.notify('imageContext', { src: node.attrs.src, align: node.attrs.align || 'left', alt: node.attrs.alt || '' })
      })
      img.addEventListener('error', () => {
        box.classList.add('broken')
        box.textContent = '图片丢失：' + (node.attrs.alt || node.attrs.src)
      })
      apply(node)

      handle.addEventListener('mousedown', e => {
        e.preventDefault()
        e.stopPropagation()
        const startX = e.clientX
        const startW = box.getBoundingClientRect().width
        // 最宽：正文宽、原图像素宽，取小的
        const maxW = Math.min(editor.view.dom.clientWidth, img.naturalWidth || Infinity)
        let px = Math.round(startW)
        box.classList.add('resizing')
        const move = ev => {
          px = Math.round(Math.min(maxW, Math.max(IMG_MIN_WIDTH, startW + ev.clientX - startX)))
          box.style.width = px + 'px'
          size.textContent = px + ' px'
        }
        const up = () => {
          window.removeEventListener('mousemove', move)
          window.removeEventListener('mouseup', up)
          box.classList.remove('resizing')
          editor.view.dispatch(editor.view.state.tr.setNodeMarkup(getPos(), undefined, { ...node.attrs, width: px + 'px' }))
        }
        window.addEventListener('mousemove', move)
        window.addEventListener('mouseup', up)
      })
      return {
        dom: box,
        update(n) {
          if (n.type !== node.type) return false
          node = n
          apply(n)
          return true
        },
        stopEvent: e => e.target === handle || !!e.target.closest?.('.crop-rect, .crop-bar'),   // 裁剪框里的操作不交给编辑器
        ignoreMutation: () => true,
      }
    }
  },
}).configure({ inline: false, allowBase64: false })

// 图片进来：读成 base64 → 后端存进 App 的文件夹 → 正文里插入 attachment:文件名
function readBase64(file) {
  return new Promise((resolve, reject) => {
    const r = new FileReader()
    r.onload = () => resolve(String(r.result).split(',')[1] || '')
    r.onerror = () => reject(r.error)
    r.readAsDataURL(file)
  })
}

async function imageSize(file) {
  try {
    const bmp = await createImageBitmap(file)
    const s = { width: bmp.width, height: bmp.height }
    bmp.close?.()
    return s
  } catch {
    return { width: null, height: null }
  }
}

async function uploadImages(files, pos) {
  const imgs = [...files].filter(f => f.type.startsWith('image/'))
  if (!imgs.length) return false
  for (const f of imgs) {
    try {
      const [data, { width, height }] = await Promise.all([readBase64(f), imageSize(f)])
      const r = await host.call('attachment_add', {
        note_id: noteId, data, original_name: f.name || 'image.png', width, height,
      })
      // 插入时的宽度：原图像素宽，但不超过正文宽（以后窗口放大也不会跟着变大）
      const fit = Math.min(width || IMG_REF_WIDTH, editor.view.dom.clientWidth || IMG_REF_WIDTH)
      const node = editor.schema.nodes.image.create({ src: r.src, alt: f.name || '', width: Math.round(fit) + 'px' })
      const at = pos ?? editor.state.selection.from
      editor.view.dispatch(editor.state.tr.insert(Math.min(at, editor.state.doc.content.size), node))
      if (pos != null) pos += node.nodeSize
    } catch (e) {
      toast('图片保存失败：' + e.message)
    }
  }
  return true
}

// ---------- 工具栏 ----------
function setupToolbar() {
  const tb = document.getElementById('toolbar')
  // 按钮按下时不抢编辑器的焦点和选区
  tb.addEventListener('mousedown', e => { if (e.target.closest('button')) e.preventDefault() })

  const toggles = {
    bold: () => editor.chain().focus().toggleBold().run(),
    italic: () => editor.chain().focus().toggleItalic().run(),
    underline: () => editor.chain().focus().toggleUnderline().run(),
    strike: () => editor.chain().focus().toggleStrike().run(),
    bulletList: () => editor.chain().focus().toggleBulletList().run(),
    orderedList: () => editor.chain().focus().toggleOrderedList().run(),
    highlight: () => editor.chain().focus().toggleHighlight().run(),
  }
  tb.querySelectorAll('[data-cmd]').forEach(b => b.addEventListener('click', () => toggles[b.dataset.cmd]()))
  const tableOps = document.getElementById('table-ops')
  tableOps.addEventListener('change', () => {
    const op = tableOps.value
    tableOps.value = ''                       // 选完回到「表格」
    if (op) editor.chain().focus()[op]().run()
  })

  const blockType = document.getElementById('block-type')
  blockType.addEventListener('change', () => {
    const v = blockType.value
    const c = editor.chain().focus()
    if (v === 'p') c.setParagraph().run()
    else c.setHeading({ level: Number(v) }).run()
  })

  // 色板
  const palette = document.getElementById('palette')
  const colorBar = document.getElementById('color-bar')
  for (const [name, label] of COLORS) {
    const b = el('button')
    b.title = label
    b.style.background = `var(--c-${name})`
    b.addEventListener('click', () => {
      editor.chain().focus().setTextColor(name).run()
      palette.classList.remove('show')
    })
    palette.append(b)
  }
  const clear = el('button', 'clear', '默认')
  clear.addEventListener('click', () => {
    editor.chain().focus().unsetTextColor().run()
    palette.classList.remove('show')
  })
  palette.append(clear)
  document.getElementById('color-btn').addEventListener('click', e => {
    e.stopPropagation()
    palette.classList.toggle('show')
  })
  document.addEventListener('mousedown', e => {
    if (!e.target.closest('#palette') && !e.target.closest('#color-btn')) palette.classList.remove('show')
  })

  document.getElementById('table-btn').addEventListener('click', () =>
    editor.chain().focus().insertTable({ rows: 3, cols: 3, withHeaderRow: true }).run())

  const fileInput = document.getElementById('file-input')
  document.getElementById('image-btn').addEventListener('click', () => fileInput.click())
  fileInput.addEventListener('change', () => {
    uploadImages(fileInput.files)
    fileInput.value = ''
  })

  // 按当前光标位置刷新按钮的高亮状态
  return () => {
    for (const b of tb.querySelectorAll('[data-cmd]')) b.classList.toggle('on', editor.isActive(b.dataset.cmd))
    const lvl = [1, 2, 3].find(l => editor.isActive('heading', { level: l }))
    blockType.value = lvl ? String(lvl) : 'p'
    const c = editor.getAttributes('textColor').c
    colorBar.style.background = c ? `var(--c-${c})` : 'var(--fg)'
    const inTable = editor.isActive('table')   // 光标在表格里：「表格」按钮换成表格操作下拉
    document.getElementById('table-btn').hidden = inTable
    tableOps.hidden = !inTable
  }
}

// ---------- 正文内容 ----------
function parseContent(content) {
  if (!content) return null
  try {
    const doc = JSON.parse(content)
    if (doc && doc.type === 'doc') return doc
  } catch { /* 旧数据：纯文字 */ }
  // 纯文字：按行变成段落
  return {
    type: 'doc',
    content: String(content).split('\n').map(line =>
      line ? { type: 'paragraph', content: [{ type: 'text', text: line }] } : { type: 'paragraph' }),
  }
}

window.noteEditor = {
  init({ noteId: id, content, accent, assetBase: base, wuxingColor } = {}) {
    noteId = id ?? null
    document.body.classList.toggle('wx-on', !!wuxingColor)
    if (base) assetBase = base
    if (accent) document.documentElement.style.setProperty('--accent', accent)
    if (editor) editor.destroy()
    chartCache.clear()

    editor = new Editor({
      element: document.getElementById('editor'),
      extensions: [
        StarterKit, Underline, Highlight, TextColor, ChartCard, ResizableImage,
        Placeholder.configure({ placeholder: '正文' }),
        Table.configure({ resizable: true }), TableRow, TableHeader, TableCell,
      ],
      content: parseContent(content),
      editorProps: {
        handlePaste: (view, event) => {
          const files = event.clipboardData?.files
          if (!files?.length) return false
          uploadImages(files)
          return [...files].some(f => f.type.startsWith('image/'))
        },
        handleDrop: (view, event, slice, moved) => {
          const files = event.dataTransfer?.files
          if (moved || !files?.length) return false
          const pos = view.posAtCoords({ left: event.clientX, top: event.clientY })?.pos
          event.preventDefault()
          uploadImages(files, pos)
          return true
        },
      },
    })
    const refresh = window.noteEditor._refresh
    editor.on('transaction', refresh)
    editor.on('update', () => { host.notify('changed'); find?.refresh() })
    // 记录光标是否在正文：点进正文 → 在；点到标题、案主输入框等别处 → 不在
    bodyActive = false
    editor.on('focus', () => { bodyActive = true })
    editor.on('blur', () => { bodyActive = false; lastBlur = Date.now() })
    refresh()
  },

  /** 当前正文的 JSON 字符串（保存时由宿主取走）。 */
  getJSON() {
    return editor ? JSON.stringify(editor.getJSON()) : ''
  },

  /** 光标是否在正文里（宿主点「插入排盘」前先问）。 */
  cursorInBody() {
    // 宿主的按钮被点下时，正文可能刚刚失去焦点；半秒内失焦的也算还在正文里
    return !!editor && (editor.isFocused || bodyActive || Date.now() - lastBlur < 500)
  },

  /** 在光标处插入排盘卡片（宿主排完盘后调用）。选中的是一张卡片时，插到它后面，不替换。 */
  insertChart(id) {
    if (!editor) return
    const { selection } = editor.state
    const chain = editor.chain().focus()
    if (selection.node) chain.insertContentAt(selection.to, { type: 'chart', attrs: { id } }).run()
    else chain.insertChart(id).run()
  },

  focus() {
    editor?.commands.focus()
  },

  /** 五行颜色开关（在点开的排盘窗口里勾选，宿主同步过来）。 */
  setWuxingColor(on) {
    document.body.classList.toggle('wx-on', !!on)
  },

  /** 排盘窗口里改了这个排盘的所问之事 / 特点：重新取数据、重画正文里的卡片。 */
  refreshChart(id) {
    refreshChartCards(id)
  },

  /** 宿主在页面顶上盖的那一块（标题、案主、标签、术数）有多高：留出同样高的空白。 */
  setTopInset(px) {
    document.getElementById('top-inset').style.height = Math.max(0, px) + 'px'
  },

  /** 右键菜单：对齐（left / center / right）。 */
  imageAlign(align) {
    withContextImage((pos, n) => editor.view.dispatch(
      editor.state.tr.setNodeMarkup(pos, undefined, { ...n.attrs, align })))
  },

  /** 右键菜单「粘贴」：宿主已经把剪贴板的图存好了，换掉这张图（宽度、对齐不变）。 */
  replaceContextImage(src, alt) {
    withContextImage((pos, n) => editor.view.dispatch(
      editor.state.tr.setNodeMarkup(pos, undefined, { ...n.attrs, src, alt: alt ?? n.attrs.alt })))
  },

  /** 右键菜单「裁剪」：在图上出现裁剪框。 */
  cropContextImage() {
    withContextImage(pos => {
      const box = editor.view.nodeDOM(pos)
      if (box) startCrop(box, pos)
    })
  },

  /** 标签在 Swift 那边被彻底删除了：卡片上也去掉。 */
  labelDeleted(id) {
    dropLabelEverywhere(id)
  },
}

/** 右键点中的那张图还在原位就执行 fn(pos, node)（期间文档被改过、图不在了就什么都不做）。 */
function withContextImage(fn) {
  if (!editor || ctxImagePos == null) return
  const n = editor.state.doc.nodeAt(ctxImagePos)
  if (n?.type.name === 'image') fn(ctxImagePos, n)
}

// ---------- 裁剪：图上一个可拖的框，框外压暗；「完成」把框里的部分存成新图片替换原图（⌘Z 可撤销） ----------
function startCrop(box, pos) {
  if (box.classList.contains('cropping')) return
  const img = box.querySelector('img')
  if (!img?.naturalWidth) { toast('图片还没加载好'); return }
  box.classList.add('cropping')
  let r = { x: 0, y: 0, w: 1, h: 1 }                 // 裁剪框，按图片宽高的比例（0–1）
  const rect = el('div', 'crop-rect')
  for (const h of ['nw', 'n', 'ne', 'e', 'se', 's', 'sw', 'w']) {
    const c = el('span', 'ch'); c.dataset.h = h; rect.append(c)
  }
  const bar = el('div', 'crop-bar')
  const cancelBtn = el('button', null, '取消')
  const okBtn = el('button', 'ok', '完成')
  bar.append(cancelBtn, okBtn)
  box.append(rect, bar)
  const draw = () => Object.assign(rect.style, {
    left: r.x * 100 + '%', top: r.y * 100 + '%', width: r.w * 100 + '%', height: r.h * 100 + '%',
  })
  draw()

  const MIN = 0.05
  rect.addEventListener('mousedown', e => {
    e.preventDefault(); e.stopPropagation()
    const handle = e.target.dataset.h || 'move'
    const b = img.getBoundingClientRect()
    const sx = e.clientX, sy = e.clientY, s = { ...r }
    const move = ev => {
      const dx = (ev.clientX - sx) / b.width, dy = (ev.clientY - sy) / b.height
      let { x, y, w, h } = s
      if (handle === 'move') {
        x = Math.min(1 - w, Math.max(0, x + dx)); y = Math.min(1 - h, Math.max(0, y + dy))
      } else {
        if (handle.includes('w')) { const nx = Math.min(x + w - MIN, Math.max(0, x + dx)); w += x - nx; x = nx }
        if (handle.includes('e')) w = Math.min(1 - x, Math.max(MIN, w + dx))
        if (handle.includes('n')) { const ny = Math.min(y + h - MIN, Math.max(0, y + dy)); h += y - ny; y = ny }
        if (handle.includes('s')) h = Math.min(1 - y, Math.max(MIN, h + dy))
      }
      r = { x, y, w, h }; draw()
    }
    const up = () => { window.removeEventListener('mousemove', move); window.removeEventListener('mouseup', up) }
    window.addEventListener('mousemove', move)
    window.addEventListener('mouseup', up)
  })

  const end = () => {
    rect.remove(); bar.remove(); box.classList.remove('cropping')
    window.removeEventListener('keydown', onKey, true)
  }
  const finish = async () => {
    end()
    if (r.x < 0.001 && r.y < 0.001 && r.w > 0.999 && r.h > 0.999) return      // 没动过框
    try {
      const sw = Math.max(1, Math.round(r.w * img.naturalWidth)), sh = Math.max(1, Math.round(r.h * img.naturalHeight))
      const canvas = document.createElement('canvas')
      canvas.width = sw; canvas.height = sh
      canvas.getContext('2d').drawImage(img, Math.round(r.x * img.naturalWidth), Math.round(r.y * img.naturalHeight), sw, sh, 0, 0, sw, sh)
      const node = editor.state.doc.nodeAt(pos)
      const jpeg = /\.(jpe?g)$/i.test(node?.attrs.src || '')                // 照片存 JPEG，截图等存 PNG
      const blob = await new Promise(res => canvas.toBlob(res, jpeg ? 'image/jpeg' : 'image/png', 0.92))
      const data = await readBase64(blob)
      const res = await host.call('attachment_add', {
        note_id: noteId, data, original_name: '裁剪.' + (jpeg ? 'jpg' : 'png'), width: sw, height: sh,
      })
      const cur = editor.state.doc.nodeAt(pos)
      if (cur?.type.name !== 'image') return
      const oldPx = widthPx(cur.attrs.width) ?? box.getBoundingClientRect().width
      editor.view.dispatch(editor.state.tr.setNodeMarkup(pos, undefined, {
        ...cur.attrs, src: res.src, width: Math.max(IMG_MIN_WIDTH, Math.round(oldPx * r.w)) + 'px',   // 框住的部分显示大小不变
      }))
    } catch (e) {
      toast('裁剪失败：' + e.message)
    }
  }
  const onKey = e => {
    if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); end() }
    if (e.key === 'Enter') { e.preventDefault(); e.stopPropagation(); finish() }
  }
  window.addEventListener('keydown', onKey, true)
  cancelBtn.addEventListener('mousedown', e => { e.preventDefault(); e.stopPropagation(); end() })
  okBtn.addEventListener('mousedown', e => { e.preventDefault(); e.stopPropagation(); finish() })
}

// ---------- 在笔记里查找（⌘F / Ctrl+F） ----------
// 不改动正文：在页面里找出命中的文字，用 CSS 的 Custom Highlight API 涂上颜色（Safari 17.2+ 支持）。
// 正文改了（打字、删字）会自动重新找。
const find = (() => {
  const bar = document.getElementById('find-bar')
  const input = document.getElementById('find-input')
  const count = document.getElementById('find-count')
  let ranges = []
  let current = -1
  // 注意：这个文件里的 Highlight 是 TipTap 的「高亮」扩展（工具栏用），浏览器自带的高亮类要从 globalThis 拿
  const CSSHighlight = globalThis.Highlight
  const supported = typeof CSSHighlight === 'function' && !!CSS.highlights

  /** 正文里所有文字节点（跳过排盘卡片旁的标签浮窗这种界面上的字）。 */
  function textNodes() {
    const root = editor?.view.dom
    if (!root) return []
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: n => (n.parentElement?.closest('.chart-labels, .cc-del') ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT),
    })
    const out = []
    while (walker.nextNode()) out.push(walker.currentNode)
    return out
  }

  function search() {
    const q = input.value.trim().toLowerCase()
    ranges = []
    if (q) {
      for (const node of textNodes()) {            // 每个文字节点里找（英文不分大小写）
        const text = node.data.toLowerCase()
        let i = text.indexOf(q)
        while (i !== -1) {
          const r = document.createRange()
          r.setStart(node, i)
          r.setEnd(node, i + q.length)
          ranges.push(r)
          i = text.indexOf(q, i + q.length)
        }
      }
    }
    if (current >= ranges.length) current = ranges.length - 1
    if (current < 0 && ranges.length) current = 0
    paint()
  }

  function paint() {
    if (supported) {
      CSS.highlights.set('find-hit', new CSSHighlight(...ranges))
      CSS.highlights.set('find-current', new CSSHighlight(...(ranges[current] ? [ranges[current]] : [])))
    }
    count.textContent = input.value.trim() ? (ranges.length ? `${current + 1}/${ranges.length}` : '没有') : ''
  }

  /** 把当前这个滚到窗口中间（工具栏会挡住顶上一块，所以放中间）。 */
  function reveal() {
    const r = ranges[current]
    if (!r) return
    const box = r.getBoundingClientRect()
    window.scrollBy({ top: box.top - window.innerHeight / 2, behavior: 'smooth' })
  }

  function step(d) {
    if (!ranges.length) return
    current = (current + d + ranges.length) % ranges.length
    paint()
    reveal()
  }

  function open() {
    bar.hidden = false
    const sel = window.getSelection()?.toString().trim()
    if (sel && !sel.includes('\n')) input.value = sel      // 选着一段字时，直接拿来找
    input.focus()
    input.select()
    current = -1
    search()
    reveal()
  }

  function close() {
    bar.hidden = true
    ranges = []
    current = -1
    if (supported) { CSS.highlights.delete('find-hit'); CSS.highlights.delete('find-current') }
    editor?.commands.focus()
  }

  input.addEventListener('input', () => { current = -1; search(); reveal() })
  input.addEventListener('keydown', e => {
    if (e.key === 'Enter') { e.preventDefault(); step(e.shiftKey ? -1 : 1) }
    if (e.key === 'Escape') { e.preventDefault(); close() }
  })
  document.getElementById('find-next').addEventListener('click', () => step(1))
  document.getElementById('find-prev').addEventListener('click', () => step(-1))
  document.getElementById('find-close').addEventListener('click', close)
  // ⌘F / Ctrl+F（宿主那边也会转过来调 open）；⌘G / ⇧⌘G 下一个 / 上一个
  window.addEventListener('keydown', e => {
    const mod = e.metaKey || e.ctrlKey
    if (mod && e.key.toLowerCase() === 'f') { e.preventDefault(); open() }
    else if (mod && e.key.toLowerCase() === 'g' && !bar.hidden) { e.preventDefault(); step(e.shiftKey ? -1 : 1) }
    else if (e.key === 'Escape' && !bar.hidden) close()
  }, true)

  let pending = 0
  return {
    open, close,
    /** 正文变了：查找框开着就重新找（稍等一下，打字时不用每个字都找一遍）。 */
    refresh() {
      if (bar.hidden) return
      clearTimeout(pending)
      pending = setTimeout(search, 150)
    },
  }
})()

window.noteEditor.openFind = () => find.open()

window.noteEditor._refresh = setupToolbar()

// 页面滚动了多少 → 告诉宿主，宿主把顶上那块（标题、案主…）往上挪同样多，看起来就是一起滚。
// 每一帧最多报一次，不会刷屏。
let scrollQueued = false
window.addEventListener('scroll', () => {
  if (scrollQueued) return
  scrollQueued = true
  requestAnimationFrame(() => {
    scrollQueued = false
    host.notify('scroll', { y: Math.max(0, window.scrollY) })
  })
}, { passive: true })

host.notify('ready')
window.__noteEditorReady = true
