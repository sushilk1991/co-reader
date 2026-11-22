// Bridge between the native app and foliate-js. The native side calls `window.reader.*`
// and receives messages through `webkit.messageHandlers.coreader`.
import './foliate/view.js'
import { Overlayer } from './foliate/overlayer.js'

const post = (type, payload = {}) => {
    try { window.webkit?.messageHandlers?.coreader?.postMessage({ type, ...payload }) }
    catch (e) { console.error(e) }
}

window.addEventListener('error', e => post('log', { level: 'error', message: `${e.message} @ ${e.filename}:${e.lineno}` }))
window.addEventListener('unhandledrejection', e => post('log', { level: 'error', message: String(e.reason?.stack ?? e.reason) }))

const HIGHLIGHT = {
    yellow: 'rgba(255, 212, 0, 0.42)',
    green: 'rgba(110, 200, 110, 0.40)',
    blue: 'rgba(90, 170, 255, 0.38)',
    pink: 'rgba(255, 120, 170, 0.38)',
    purple: 'rgba(170, 130, 255, 0.38)',
}

const pick = x => {
    if (!x) return ''
    if (typeof x === 'string') return x
    if (Array.isArray(x)) return x.map(pick).filter(Boolean).join(', ')
    if (x.name) return pick(x.name)
    const keys = Object.keys(x)
    return keys.length ? pick(x[keys[0]]) : ''
}
const list = x => !x ? [] : (Array.isArray(x) ? x : [x]).map(pick).filter(Boolean)

const blobToDataURL = blob => new Promise((resolve, reject) => {
    const r = new FileReader()
    r.onload = () => resolve(r.result)
    r.onerror = () => reject(r.error)
    r.readAsDataURL(blob)
})

const flattenTOC = (items, depth = 0, out = []) => {
    for (const item of items ?? []) {
        out.push({ label: (item.label ?? '').trim(), href: item.href ?? '', depth })
        flattenTOC(item.subitems, depth + 1, out)
    }
    return out
}

// Rect of something inside a section iframe, in the coordinates of the top-level page.
const toPageRect = (doc, rect) => {
    const frame = doc.defaultView?.frameElement?.getBoundingClientRect()
    const dx = frame?.left ?? 0, dy = frame?.top ?? 0
    return { x: rect.left + dx, y: rect.top + dy, width: rect.width, height: rect.height }
}

const css = s => `
    @namespace epub "http://www.idpf.org/2007/ops";
    html { color-scheme: ${s.dark ? 'dark' : 'light'}; color: ${s.ink}; background: transparent !important;
           font-family: ${s.fontFamily}; font-size: ${s.fontSize}px;
           -webkit-font-smoothing: antialiased; text-rendering: optimizeLegibility;
           font-variant-ligatures: common-ligatures; font-kerning: normal; }
    body { background: transparent !important; color: ${s.ink} !important; }
    ${s.overrideFonts ? `body, p, li, blockquote, dd, div, span, td { font-family: ${s.fontFamily} !important; }` : ''}
    p, li, blockquote, dd { line-height: ${s.lineHeight} !important; text-align: ${s.justify ? 'justify' : 'start'};
        -webkit-hyphens: ${s.justify ? 'auto' : 'manual'}; hyphens: ${s.justify ? 'auto' : 'manual'};
        -webkit-hyphenate-limit-before: 3; -webkit-hyphenate-limit-after: 2; -webkit-hyphenate-limit-lines: 2;
        hanging-punctuation: allow-end last; widows: 2; orphans: 2; }
    [align="left"] { text-align: left; } [align="right"] { text-align: right; }
    [align="center"] { text-align: center; } [align="justify"] { text-align: justify; }
    a:link, a:visited { color: ${s.accent}; text-decoration-thickness: 0.5px; text-underline-offset: 2px; }
    ::selection { background: ${s.selection}; }
    pre, code { white-space: pre-wrap !important; font-size: 0.86em; }
    img, svg, video { max-width: 100%; ${s.dark ? 'filter: brightness(0.86);' : ''} }
    hr { border: 0; border-top: 0.5px solid ${s.rule}; }
    h1, h2, h3, h4 { color: ${s.ink} !important; text-wrap: balance; }
    aside[epub|type~="endnote"], aside[epub|type~="footnote"], aside[epub|type~="note"], aside[epub|type~="rearnote"] { display: none; }
    .coreader-focus-dim { opacity: 0.28; transition: opacity .25s ease; }
`

// A saved web article is one XHTML-ish file: present it to foliate as a one-section book.
const makeArticle = async blob => {
    // Headings get ids before the file is turned into the rendered document, so the
    // contents list points at ids that exist in what is on screen.
    const source = new DOMParser().parseFromString(await blob.text(), 'text/html')
    Array.from(source.querySelectorAll('h2')).slice(0, 60).forEach((h, i) => { if (!h.id) h.id = `coreader-h-${i}` })
    const html = '<!DOCTYPE html>' + source.documentElement.outerHTML
    const parse = () => new DOMParser().parseFromString(html, 'text/html')
    const doc = parse()
    const url = URL.createObjectURL(new Blob([html], { type: 'text/html' }))
    const meta = name => doc.querySelector(`meta[name="${name}"]`)?.content ?? ''
    return {
        sections: [{ id: 0, load: () => url, createDocument: parse, size: html.length, linear: 'yes' }],
        dir: 'ltr',
        toc: Array.from(doc.querySelectorAll('h2[id]')).slice(0, 60)
            .map(h => ({ label: h.textContent.trim(), href: `#${h.id}` })),
        metadata: { title: doc.title, author: meta('author'), language: doc.documentElement.lang || 'en' },
        resolveHref: href => ({ index: 0, anchor: d => d.getElementById(href.replace(/^#/, '')) ?? d.body }),
        splitTOCHref: href => [0, href.replace(/^#/, '')],
        getTOCFragment: (d, id) => d.getElementById(id) ?? d.documentElement,
        isExternal: href => /^(https?|mailto):/i.test(href),
    }
}

class Reader {
    view = null
    annotations = new Map()      // cfi -> { id, value, color, hasNote }
    byID = new Map()             // id -> cfi
    settings = null
    // Documents on screen right now. Asked of the renderer each time: keeping our own
    // list would hold every chapter visited in memory until the book closes.
    #liveDocs() { return (this.view?.renderer?.getContents?.() ?? []).map(c => c.doc).filter(Boolean) }
    #selectionTimer = null

    async open(url, options = {}) {
        try {
            this.close()
            const res = await fetch(url)
            if (!res.ok) throw new Error(`Could not read the book file (${res.status})`)
            const blob = await res.blob()
            const file = new File([blob], options.fileName ?? 'book')
            const view = document.createElement('foliate-view')
            document.body.append(view)
            this.view = view
            const isArticle = /\.html?$/i.test(options.fileName ?? '')
            await view.open(isArticle ? await makeArticle(blob) : file)
            const { book } = view

            view.addEventListener('load', e => this.#onLoad(e.detail))
            view.addEventListener('relocate', e => this.#onRelocate(e.detail))
            view.addEventListener('create-overlay', e => {
                for (const a of this.annotations.values()) if (a.index === undefined || a.index === e.detail.index)
                    view.addAnnotation(a).then(r => { if (r) a.index = r.index }).catch(() => {})
            })
            view.addEventListener('draw-annotation', e => {
                const { draw, annotation } = e.detail
                draw(Overlayer.highlight, { color: HIGHLIGHT[annotation.color] ?? HIGHLIGHT.yellow })
                if (annotation.hasNote) draw(Overlayer.underline, { color: this.settings?.accent ?? '#b3402a', width: 1.5 })
            })
            view.addEventListener('show-annotation', e => {
                const a = this.annotations.get(e.detail.value)
                if (!a) return
                const doc = e.detail.range.startContainer.ownerDocument
                post('annotationTap', { id: a.id, rect: toPageRect(doc, e.detail.range.getBoundingClientRect()) })
            })
            view.addEventListener('external-link', e => {
                e.preventDefault()
                post('externalLink', { href: e.detail.href_ ?? e.detail.a?.href ?? '' })
            })
            book.transformTarget?.addEventListener('data', ({ detail }) => {
                detail.data = Promise.resolve(detail.data).catch(() => '')
            })

            for (const a of options.annotations ?? []) this.#remember(a)
            if (options.settings) this.applySettings(options.settings)

            let cover = null
            try {
                const blob = await book.getCover?.()
                if (blob) cover = await blobToDataURL(blob)
            } catch { /* a missing cover is normal */ }

            post('opened', {
                title: pick(book.metadata?.title),
                authors: list(book.metadata?.author),
                language: pick(book.metadata?.language),
                publisher: pick(book.metadata?.publisher),
                description: pick(book.metadata?.description),
                published: pick(book.metadata?.published),
                toc: flattenTOC(book.toc),
                sectionFractions: view.getSectionFractions?.() ?? [],
                fixedLayout: !!view.isFixedLayout,
                rtl: book.dir === 'rtl',
                cover,
            })
            await view.init({ lastLocation: options.lastCFI || null, showTextStart: !options.lastCFI })
        } catch (e) {
            post('openFailed', { message: String(e?.message ?? e) })
        }
    }

    close() {
        if (!this.view) return
        try { this.view.close() } catch { /* already closed */ }
        this.view.remove()
        this.view = null
        this.annotations.clear(); this.byID.clear()
    }

    #remember(a) {
        const record = { id: a.id, value: a.cfi, color: a.color, hasNote: !!a.hasNote }
        this.annotations.set(a.cfi, record)
        this.byID.set(a.id, a.cfi)
        return record
    }

    #onLoad({ doc, index }) {
        doc.addEventListener('selectionchange', () => {
            clearTimeout(this.#selectionTimer)
            this.#selectionTimer = setTimeout(() => this.#reportSelection(doc, index), 120)
        })
        doc.addEventListener('contextmenu', e => {
            e.preventDefault()
            const img = e.target.closest?.('img, image, svg')
            const sel = doc.getSelection()
            const frame = doc.defaultView?.frameElement?.getBoundingClientRect()
            const point = { x: e.clientX + (frame?.left ?? 0), y: e.clientY + (frame?.top ?? 0) }
            if (img) this.#reportImage(img, doc, index, point)
            else post('contextMenu', { point, hasSelection: !!sel && !sel.isCollapsed })
        })
        doc.addEventListener('keydown', e => this.#key(e))
        doc.addEventListener('click', e => {
            const sel = doc.getSelection()
            if (sel && !sel.isCollapsed) return
            if (e.target.closest?.('a[href]')) return
            const frame = doc.defaultView?.frameElement?.getBoundingClientRect()
            post('tap', { x: (e.clientX + (frame?.left ?? 0)) / window.innerWidth })
        })
        // Double-click on an image opens it large; handled natively.
        doc.addEventListener('dblclick', e => {
            const img = e.target.closest?.('img, image')
            if (img) this.#reportImage(img, doc, index, null, 'imageOpen')
        })
    }

    async #reportImage(el, doc, index, point, type = 'imageContext') {
        try {
            let dataURL = null
            const src = el.currentSrc || el.src || el.href?.baseVal
            if (src) dataURL = await blobToDataURL(await (await fetch(src)).blob())
            else if (el.tagName.toLowerCase() === 'svg') {
                const xml = new XMLSerializer().serializeToString(el)
                dataURL = 'data:image/svg+xml;base64,' + btoa(unescape(encodeURIComponent(xml)))
            }
            if (!dataURL) return
            const range = doc.createRange(); range.selectNode(el)
            const caption = (el.getAttribute('alt') || el.closest('figure')?.querySelector('figcaption')?.textContent || '').trim()
            post(type, {
                dataURL, caption, point,
                cfi: this.view.getCFI(index, range),
                fraction: this.#fractionOf(doc, index, range),
                chapter: this.view.lastLocation?.tocItem?.label ?? '',
                rect: toPageRect(doc, el.getBoundingClientRect()),
            })
        } catch (e) { post('log', { level: 'warn', message: 'image: ' + e }) }
    }

    // Position of a range in the whole book, finer than the page it is on, so notes made
    // on one page still sort in reading order.
    #fractionOf(doc, index, range) {
        const fractions = this.view.getSectionFractions?.() ?? []
        const start = fractions[index], end = fractions[index + 1]
        if (start === undefined || end === undefined) return this.view.lastLocation?.fraction ?? 0
        try {
            const before = doc.createRange()
            before.setStart(doc.body, 0)
            before.setEnd(range.startContainer, range.startOffset)
            const total = doc.body.textContent.length || 1
            return start + (end - start) * Math.min(1, before.toString().length / total)
        } catch { return this.view.lastLocation?.fraction ?? start }
    }

    #reportSelection(doc, index) {
        const sel = doc.getSelection()
        if (!sel || sel.isCollapsed || !sel.rangeCount) { post('selectionCleared'); return }
        const range = sel.getRangeAt(0)
        const text = sel.toString().trim()
        if (!text) { post('selectionCleared'); return }
        const rects = Array.from(range.getClientRects())
        const first = rects[0] ?? range.getBoundingClientRect()
        const bounds = range.getBoundingClientRect()
        // Surrounding paragraph gives the AI enough context for "what does this mean".
        let block = range.commonAncestorContainer
        if (block.nodeType !== 1) block = block.parentElement
        block = block?.closest?.('p, li, blockquote, td, div, section') ?? block
        post('selection', {
            text,
            cfi: this.view.getCFI(index, range),
            context: (block?.textContent ?? '').trim().slice(0, 2400),
            chapter: this.view.lastLocation?.tocItem?.label ?? '',
            fraction: this.#fractionOf(doc, index, range),
            rect: toPageRect(doc, bounds),
            firstRect: toPageRect(doc, first),
        })
    }

    #onRelocate(detail) {
        const { fraction, location, tocItem, pageItem, cfi, section } = detail
        post('relocate', {
            cfi, fraction: fraction ?? 0,
            chapter: tocItem?.label?.trim() ?? '',
            chapterHref: tocItem?.href ?? '',
            page: pageItem?.label ?? '',
            locCurrent: location?.current ?? 0, locTotal: location?.total ?? 0,
            sectionCurrent: section?.current ?? 0, sectionTotal: section?.total ?? 0,
            visibleText: (detail.range?.toString?.() ?? '').replace(/\s+/g, ' ').trim().slice(0, 6000),
        })
    }

    #key(e) {
        if (e.metaKey || e.ctrlKey || e.altKey) return
        const k = e.key
        if (k === 'ArrowLeft' || k === 'PageUp') { e.preventDefault(); this.prev() }
        else if (k === 'ArrowRight' || k === 'PageDown' || (k === ' ' && !e.shiftKey)) { e.preventDefault(); this.next() }
        else if (k === ' ' && e.shiftKey) { e.preventDefault(); this.prev() }
        else if (k === 'Escape') post('escape')
    }

    next() { return this.view?.goRight() }
    prev() { return this.view?.goLeft() }
    async goTo(target) {
        try { await this.view?.goTo(target) } catch (e) { post('log', { level: 'warn', message: 'goTo: ' + e }) }
    }
    goToFraction(f) { return this.view?.goToFraction(Math.min(Math.max(f, 0), 1)) }
    back() { this.view?.history.back() }
    forward() { this.view?.history.forward() }

    applySettings(s) {
        this.settings = s
        const r = this.view?.renderer
        if (!r) return
        r.setAttribute('flow', s.flow === 'scrolled' ? 'scrolled' : 'paginated')
        if (s.animated) r.setAttribute('animated', ''); else r.removeAttribute('animated')
        r.setAttribute('gap', `${s.gap ?? 6}%`)
        r.setAttribute('margin', `${s.margin ?? 56}px`)
        r.setAttribute('max-inline-size', `${s.maxInlineSize ?? 680}px`)
        r.setAttribute('max-column-count', String(s.columns ?? 2))
        r.setStyles?.(css(s))
    }

    async addAnnotation(a) {
        const record = this.#remember(a)
        try { const r = await this.view.addAnnotation(record); if (r) record.index = r.index } catch (e) { post('log', { level: 'warn', message: 'annotate: ' + e }) }
        this.clearSelection()
    }
    async updateAnnotation(a) {
        await this.removeAnnotation(a.id)
        await this.addAnnotation(a)
    }
    async removeAnnotation(id) {
        const cfi = this.byID.get(id)
        if (!cfi) return
        const record = this.annotations.get(cfi)
        this.annotations.delete(cfi); this.byID.delete(id)
        try { await this.view.deleteAnnotation(record) } catch { /* section not loaded: nothing drawn */ }
    }
    async showAnnotation(id) {
        const cfi = this.byID.get(id)
        if (cfi) await this.goTo(cfi)
    }

    clearSelection() {
        for (const doc of this.#liveDocs()) doc.getSelection()?.removeAllRanges()
        post('selectionCleared')
    }

    async search(query) {
        this.view.clearSearch()
        if (!query) { post('searchDone', { query }); return }
        const token = this.searchToken = Symbol()
        try {
            for await (const result of this.view.search({ query })) {
                if (this.searchToken !== token) return
                if (result === 'done') break
                if (result.subitems) post('searchResults', {
                    query, label: result.label ?? '',
                    items: result.subitems.map(i => ({ cfi: i.cfi, pre: i.excerpt.pre, match: i.excerpt.match, post: i.excerpt.post })),
                })
            }
        } catch (e) { post('log', { level: 'warn', message: 'search: ' + e }) }
        post('searchDone', { query })
    }
    clearSearch() { this.searchToken = null; this.view?.clearSearch() }

    // Plain text of every section, for whole-book chat and the agents. Sent in pieces
    // so one huge message never blocks the bridge.
    async extractText() {
        const { book } = this.view
        const fractions = this.view.getSectionFractions?.() ?? []
        const titles = new Map()
        for (const item of flattenTOC(book.toc)) {
            try {
                const r = this.view.resolveNavigation(item.href)
                if (r && !titles.has(r.index)) titles.set(r.index, item.label)
            } catch { /* unresolvable TOC entries are skipped */ }
        }
        let count = 0
        for (let index = 0; index < book.sections.length; index++) {
            const section = book.sections[index]
            if (section.linear === 'no') continue
            try {
                const doc = await section.createDocument()
                const text = (doc.body?.innerText ?? doc.body?.textContent ?? doc.documentElement.textContent ?? '')
                    .replace(/ /g, ' ').replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim()
                if (text.length < 40) continue
                const heading = doc.querySelector('h1, h2, h3, title')?.textContent?.trim()
                post('textSection', {
                    index, title: titles.get(index) || heading || `Section ${index + 1}`,
                    cfi: this.view.getCFI(index), fraction: fractions[index] ?? index / book.sections.length, text,
                })
                count++
            } catch (e) { post('log', { level: 'warn', message: `text ${index}: ${e}` }) }
        }
        post('textDone', { count })
    }

    // Dim everything except the paragraph being read (focus mode).
    setFocusParagraph(on) {
        for (const doc of this.#liveDocs()) doc.documentElement.classList.toggle('coreader-focus', !!on)
    }
}

window.reader = new Reader()
document.addEventListener('keydown', e => window.reader.view && (
    e.key === 'ArrowLeft' ? window.reader.prev() : e.key === 'ArrowRight' ? window.reader.next() : null))
post('ready')
