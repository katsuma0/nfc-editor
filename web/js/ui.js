// UI engine for the web preview: iOS-style lists, navigation stacks, sheets, alerts, and the simulated system NFC sheet.
const UI = (() => {
  const S = 'stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" fill="none"';
  const ICONS = {
    wave: `<path ${S} d="M8.5 9.5a4 4 0 0 1 0 5M11.5 7a7.5 7.5 0 0 1 0 10M14.5 4.5a11 11 0 0 1 0 15"/><circle cx="5" cy="12" r="1.6" fill="currentColor"/>`,
    waveslash: `<path ${S} d="M8.5 9.5a4 4 0 0 1 0 5M11.5 7a7.5 7.5 0 0 1 0 10M14.5 4.5a11 11 0 0 1 0 15M3 3l18 18"/><circle cx="5" cy="12" r="1.6" fill="currentColor"/>`,
    pencil: `<path ${S} d="M12 4H6a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-6"/><path ${S} d="M18.5 3.5a2 2 0 0 1 2.8 2.8L13 14.6 9 15.6l1-4z"/>`,
    wrench: `<path ${S} d="M14.5 5.5a4.5 4.5 0 0 0 5.3 5.9L9.6 21.6a2.1 2.1 0 0 1-3-3L16.8 8.4a4.5 4.5 0 0 0 5.9 5.3"/><path ${S} d="M14.5 5.5l4-2.5 2.5 2.5-2.5 4"/>`,
    folder: `<path ${S} d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>`,
    gear: `<circle ${S} cx="12" cy="12" r="3"/><path ${S} d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>`,
    chevron: `<path ${S} stroke-width="2.4" d="M9 5l7 7-7 7"/>`,
    back: `<path ${S} stroke-width="2.4" d="M15 5l-7 7 7 7"/>`,
    down: `<path ${S} stroke-width="2.4" d="M6 9l6 6 6-6"/>`,
    up: `<path ${S} stroke-width="2.4" d="M6 15l6-6 6 6"/>`,
    check: `<path ${S} stroke-width="2.6" d="M5 12.5l4.5 4.5L19 7"/>`,
    xmark: `<path ${S} stroke-width="2.4" d="M6 6l12 12M18 6L6 18"/>`,
    plus: `<path ${S} stroke-width="2.2" d="M12 5v14M5 12h14"/>`,
    minus: `<path ${S} stroke-width="2.2" d="M5 12h14"/>`,
    ellipsis: `<circle ${S} cx="12" cy="12" r="9.5"/><circle cx="7.5" cy="12" r="1.3" fill="currentColor"/><circle cx="12" cy="12" r="1.3" fill="currentColor"/><circle cx="16.5" cy="12" r="1.3" fill="currentColor"/>`,
    share: `<path ${S} d="M12 3v12M8 7l4-4 4 4M5 11v8a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-8"/>`,
    trash: `<path ${S} d="M4 7h16M9 7V4h6v3M6 7l1 13a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1l1-13M10 11v6M14 11v6"/>`,
    copy: `<rect ${S} x="8" y="8" width="12" height="12" rx="2"/><path ${S} d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"/>`,
    link: `<path ${S} d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1.5 1.5"/><path ${S} d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1.5-1.5"/>`,
    linkplus: `<path ${S} d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1.5 1.5"/><path ${S} d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7"/><path ${S} d="M19 16v6M16 19h6"/>`,
    text: `<path ${S} d="M4 6h16M4 10h12M4 14h16M4 18h9"/>`,
    envelope: `<rect ${S} x="3" y="5" width="18" height="14" rx="2"/><path ${S} d="M3 7l9 6 9-6"/>`,
    person: `<circle ${S} cx="12" cy="8" r="4"/><path ${S} d="M4 21a8 8 0 0 1 16 0"/>`,
    phone: `<path ${S} d="M6 3h4l2 5-2.5 1.5a11 11 0 0 0 5 5L16 12l5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 4 5a2 2 0 0 1 2-2z"/>`,
    message: `<path ${S} d="M4 5h16v11H9l-5 4z"/>`,
    location: `<path ${S} d="M12 21s7-6.5 7-11.5A7 7 0 0 0 5 9.5C5 14.5 12 21 12 21z"/><circle ${S} cx="12" cy="9.5" r="2.5"/>`,
    map: `<path ${S} d="M3 6l6-2 6 2 6-2v14l-6 2-6-2-6 2zM9 4v14M15 6v14"/>`,
    wifi: `<path ${S} d="M2.5 9a14 14 0 0 1 19 0M5.5 12.5a10 10 0 0 1 13 0M8.5 16a5.5 5.5 0 0 1 7 0"/><circle cx="12" cy="19.5" r="1.4" fill="currentColor"/>`,
    bluetooth: `<path ${S} d="M7 7l10 8-5 5V4l5 5-10 8"/>`,
    at: `<circle ${S} cx="12" cy="12" r="4"/><path ${S} d="M16 12v1.5a2.5 2.5 0 0 0 5 0V12a9 9 0 1 0-3.5 7.1"/>`,
    app: `<rect ${S} x="4" y="4" width="16" height="16" rx="4"/><circle cx="17" cy="7" r="3" fill="currentColor"/>`,
    doc: `<path ${S} d="M6 3h8l4 4v14H6z"/><path ${S} d="M14 3v4h4M9 13h6M9 17h6"/>`,
    box: `<path ${S} d="M3 8l9-4 9 4v9l-9 4-9-4zM3 8l9 4 9-4M12 12v9"/>`,
    number: `<path ${S} d="M9 4L7 20M17 4l-2 16M4 9h17M3 15h17"/>`,
    dashedcircle: `<circle ${S} cx="12" cy="12" r="8.5" stroke-dasharray="3.2 3.2"/>`,
    richtext: `<path ${S} d="M5 4h14v16H5z"/><path ${S} d="M8 8h8M8 12h8M8 16h5"/>`,
    question: `<circle ${S} cx="12" cy="12" r="9"/><path ${S} d="M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.7.3-1 .9-1 1.7"/><circle cx="12" cy="17" r="1" fill="currentColor"/>`,
    lock: `<rect ${S} x="5" y="10" width="14" height="10" rx="2"/><path ${S} d="M8 10V7a4 4 0 0 1 8 0v3"/>`,
    cpu: `<rect ${S} x="6" y="6" width="12" height="12" rx="2"/><rect ${S} x="10" y="10" width="4" height="4"/><path ${S} d="M9 3v3M15 3v3M9 18v3M15 18v3M3 9h3M3 15h3M18 9h3M18 15h3"/>`,
    memorychip: `<rect ${S} x="5" y="4" width="14" height="16" rx="2"/><path ${S} d="M9 4v16M13 4v16M2 8h3M2 12h3M2 16h3M19 8h3M19 12h3M19 16h3"/>`,
    key: `<circle ${S} cx="8" cy="12" r="4"/><path ${S} d="M12 12h9M18 12v3M15 12v2.5"/>`,
    terminal: `<rect ${S} x="3" y="5" width="18" height="14" rx="2"/><path ${S} d="M7 9l3 3-3 3M12 15h5"/>`,
    docdown: `<path ${S} d="M6 3h8l4 4v14H6z"/><path ${S} d="M14 3v4h4M12 10v7M9.5 14.5L12 17l2.5-2.5"/>`,
    signature: `<path ${S} d="M3 17c3-6 5-8 6-8s0 9 2 9 3-7 4-7 1 5 3 5 2-2 3-2"/>`,
    info: `<circle ${S} cx="12" cy="12" r="9"/><path ${S} d="M12 11v6"/><circle cx="12" cy="8" r="1.1" fill="currentColor"/>`,
    grid: `<rect ${S} x="4" y="4" width="16" height="16" rx="2"/><path ${S} d="M4 9.3h16M4 14.7h16M9.3 4v16M14.7 4v16"/>`,
    building: `<path ${S} d="M5 21V4h14v17M9 8h2M13 8h2M9 12h2M13 12h2M9 16h2M13 16h2M3 21h18"/>`,
    phoneframe: `<rect ${S} x="6" y="2" width="12" height="20" rx="3"/><path ${S} d="M10 5h4"/>`,
    search: `<circle ${S} cx="10.5" cy="10.5" r="6"/><path ${S} d="M15 15l5 5"/>`,
    lines: `<path ${S} d="M4 8h16M4 12h16M4 16h16"/>`,
    eraser: `<path ${S} d="M4 17l8-10 7 5-4.5 6H9z"/><path ${S} d="M9 18h11"/>`,
    docs: `<rect ${S} x="7" y="7" width="12" height="14" rx="2"/><path ${S} d="M17 7V5a2 2 0 0 0-2-2H7a2 2 0 0 0-2 2v12"/>`,
    format: `<path ${S} d="M4 12a8 8 0 1 0 3-6.2"/><path ${S} d="M4 4v5h5"/>`,
    minuscircle: `<circle cx="12" cy="12" r="10" fill="currentColor"/><path stroke="#fff" stroke-width="2.4" stroke-linecap="round" d="M7 12h10"/>`,
    checkcircle: `<circle cx="12" cy="12" r="10" fill="currentColor"/><path stroke="#fff" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" fill="none" d="M7.5 12.5l3 3 6-6"/>`,
    download: `<path ${S} d="M12 4v11M7.5 10.5L12 15l4.5-4.5M5 19h14"/>`,
    upload: `<path ${S} d="M12 15V4M7.5 8.5L12 4l4.5 4.5M5 19h14"/>`,
    sparkle: `<path ${S} d="M12 3l2 5 5 2-5 2-2 5-2-5-5-2 5-2z"/>`,
    calendar: `<rect ${S} x="4" y="5" width="16" height="15" rx="2"/><path ${S} d="M4 10h16M8 3v4M16 3v4"/>`,
    tag: `<path ${S} d="M3 12V4h8l10 10-8 8z"/><circle cx="7.5" cy="8.5" r="1.4" fill="currentColor"/>`,
    hand: `<path ${S} d="M7 12V6a1.5 1.5 0 0 1 3 0v5M10 10V4.5a1.5 1.5 0 0 1 3 0V11M13 6a1.5 1.5 0 0 1 3 0v6M16 9a1.5 1.5 0 0 1 3 0v5a6 6 0 0 1-6 6h-1.5a6 6 0 0 1-5.1-2.8L4 13a1.5 1.5 0 0 1 2.5-1.5L7 12"/>`,
  };
  const SVG_NS = 'http://www.w3.org/2000/svg';
  function icon(name, cls) {
    const svg = document.createElementNS(SVG_NS, 'svg');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('aria-hidden', 'true');
    if (cls) svg.setAttribute('class', cls);
    svg.innerHTML = ICONS[name] || ICONS.question;
    return svg;
  }
  function el(tag, props = {}, ...children) {
    const node = document.createElement(tag);
    for (const [k, v] of Object.entries(props)) {
      if (v == null || v === false) continue;
      if (k === 'class') node.className = v;
      else if (k === 'text') node.textContent = v;
      else if (k === 'html') node.innerHTML = v;
      else if (k === 'style') node.style.cssText = v;
      else if (k.startsWith('on')) node.addEventListener(k.slice(2).toLowerCase(), v);
      else node.setAttribute(k, v === true ? '' : v);
    }
    for (const c of children.flat()) { if (c == null || c === false) continue; node.append(c.nodeType ? c : document.createTextNode(String(c))); }
    return node;
  }

  // Lists and cells
  function section(o) {
    const s = el('div', { class: 'section' + (o.cls ? ' ' + o.cls : '') });
    if (o.header) s.append(el('div', { class: 'section-header', text: o.header }));
    const rows = (o.rows || []).filter(Boolean);
    if (rows.length) s.append(el('div', { class: 'group' }, rows));
    if (o.footer) s.append(typeof o.footer === 'string' ? el('div', { class: 'section-footer' + (o.footerClass ? ' ' + o.footerClass : ''), text: o.footer }) : o.footer);
    return s;
  }
  function iconBox(name, bg) { return el('div', { class: 'icon-box', style: bg ? 'background:' + bg : '' }, icon(name)); }
  function row(o) {
    const classes = ['cell'];
    if (o.icon || o.iconPlain) classes.push('has-icon');
    if (o.onClick) classes.push('tappable');
    if (o.destructive) classes.push('destructive');
    if (o.blue) classes.push('blue');
    if (o.center) classes.push('center');
    if (o.disabled) classes.push('disabled');
    if (o.cls) classes.push(o.cls);
    const node = el(o.onClick ? 'button' : 'div', { class: classes.join(' '), type: o.onClick ? 'button' : null, onClick: o.onClick });
    if (o.icon) node.append(iconBox(o.icon, o.iconBg));
    if (o.iconPlain) node.append(el('div', { class: 'icon-plain', style: o.iconColor ? 'color:' + o.iconColor : '' }, icon(o.iconPlain)));
    const body = el('div', { class: 'body' });
    if (o.title != null) body.append(el('div', { class: 'title' + (o.mono ? ' mono' : ''), text: o.title }));
    if (o.subtitle) body.append(el('div', { class: 'subtitle' + (o.subtitleWrap ? ' wrap' : '') + (o.subtitleMono ? ' mono' : ''), text: o.subtitle }));
    if (o.caption) body.append(el('div', { class: 'caption', text: o.caption }));
    if (o.custom) body.append(o.custom);
    node.append(body);
    if (o.value != null) node.append(el('div', { class: 'value' + (o.valueWrap ? ' wrap' : '') + (o.valueMono ? ' mono' : ''), text: o.value }));
    if (o.right) node.append(o.right);
    if (o.accessory === 'chevron' || (o.onClick && o.accessory === undefined && !o.right)) node.append(icon('chevron', 'chevron'));
    if (o.accessory === 'check') node.append(icon('check', 'chevron'));
    return node;
  }
  function toggleRow(o) {
    const sw = el('button', { class: 'switch' + (o.value ? ' on' : ''), type: 'button', role: 'switch', 'aria-checked': String(!!o.value), 'aria-label': o.title });
    let value = !!o.value;
    const node = row({ icon: o.icon, iconBg: o.iconBg, title: o.title, subtitle: o.subtitle, subtitleWrap: true, right: sw, disabled: o.disabled, accessory: 'none' });
    const flip = () => { value = !value; sw.classList.toggle('on', value); sw.setAttribute('aria-checked', String(value)); haptic('tap'); o.onChange && o.onChange(value); };
    sw.addEventListener('click', (e) => { e.stopPropagation(); flip(); });
    return node;
  }
  function fieldRow(o) {
    const input = o.multiline ? el('textarea', { placeholder: o.placeholder || '', rows: o.rows || 4 }) : el('input', { type: o.type || 'text', placeholder: o.placeholder || '', inputmode: o.inputmode || null, autocapitalize: o.autocap || 'none', autocorrect: o.autocorrect ? 'on' : 'off', spellcheck: 'false' });
    input.value = o.value || '';
    if (o.mono) input.classList.add('mono');
    if (o.left) input.classList.add('left');
    if (o.maxLength) input.maxLength = o.maxLength;
    input.addEventListener('input', () => o.onInput && o.onInput(input.value, input));
    if (o.label) {
      const node = el('div', { class: 'cell labeled' + (o.icon ? ' has-icon' : '') });
      if (o.icon) node.append(iconBox(o.icon, o.iconBg));
      node.append(el('div', { class: 'title', text: o.label }), input);
      return node;
    }
    const node = el('div', { class: 'cell' + (o.icon ? ' has-icon' : '') });
    if (o.icon) node.append(iconBox(o.icon, o.iconBg));
    node.append(input);
    return node;
  }
  function selectRow(o) {
    const sel = el('select', { 'aria-label': o.title });
    for (const opt of o.options) { const e = el('option', { value: opt.value, text: opt.label }); if (opt.value === o.value) e.selected = true; sel.append(e); }
    const label = el('span', { class: 'select-value', text: (o.options.find((x) => x.value === o.value) || o.options[0] || { label: '' }).label });
    sel.addEventListener('change', () => { label.textContent = (o.options.find((x) => x.value === sel.value) || { label: sel.value }).label; o.onChange && o.onChange(sel.value); });
    const wrap = el('div', { class: 'select-wrap' }, label, icon('down'), sel);
    return row({ icon: o.icon, iconBg: o.iconBg, title: o.title, subtitle: o.subtitle, right: wrap, accessory: 'none' });
  }
  function stepperRow(o) {
    let value = o.value;
    const label = el('div', { class: 'value', text: (o.format || String)(value) });
    const minus = el('button', { type: 'button', 'aria-label': 'Decrease' }, icon('minus'));
    const plus = el('button', { type: 'button', 'aria-label': 'Increase' }, icon('plus'));
    const update = () => { label.textContent = (o.format || String)(value); minus.disabled = value <= o.min; plus.disabled = value >= o.max; o.onChange && o.onChange(value); };
    minus.addEventListener('click', () => { if (value > o.min) { value -= o.step || 1; update(); } });
    plus.addEventListener('click', () => { if (value < o.max) { value += o.step || 1; update(); } });
    minus.disabled = value <= o.min; plus.disabled = value >= o.max;
    const node = row({ title: o.title, subtitle: o.subtitle, subtitleWrap: true, right: el('div', { style: 'display:flex;align-items:center;gap:10px' }, label, el('div', { class: 'stepper' }, minus, plus)), accessory: 'none' });
    return node;
  }
  function buttonRow(o) { return row({ iconPlain: o.icon, iconColor: o.destructive ? 'var(--red)' : null, title: o.title, subtitle: o.subtitle, onClick: o.onClick, destructive: o.destructive, blue: !o.destructive, center: o.center, accessory: 'none', disabled: o.disabled }); }
  function bigButton(o) {
    const b = el('button', { class: 'big-button' + (o.destructive ? ' destructive' : ''), type: 'button', onClick: () => { haptic('tap'); o.onClick(); } }, o.icon ? icon(o.icon) : null, el('span', { text: o.title }));
    b.disabled = !!o.disabled;
    if (o.scan !== false) { b.dataset.scan = '1'; b.disabled = b.disabled || nfc.isBusy; }
    return el('div', { class: 'section button' }, b);
  }
  function segmented(o) {
    const node = el('div', { class: 'segmented', role: 'tablist' });
    for (const opt of o.options) {
      const b = el('button', { type: 'button', text: opt.label, class: opt.value === o.value ? 'active' : '', role: 'tab' });
      b.addEventListener('click', () => { node.querySelectorAll('button').forEach((x) => x.classList.remove('active')); b.classList.add('active'); haptic('tap'); o.onChange(opt.value); });
      node.append(b);
    }
    return node;
  }
  const textBlock = (text, cls) => el('p', { class: 'plain-text' + (cls ? ' ' + cls : ''), text });
  function hexField(o) {
    let bytes = o.value || new Uint8Array();
    const input = el('input', { type: 'text', class: 'mono', placeholder: o.placeholder || (o.byteCount ? Array(o.byteCount).fill('00').join(' ') : 'hex bytes'), inputmode: 'text', autocapitalize: 'characters', spellcheck: 'false', autocorrect: 'off' });
    input.value = NDEF.hex(bytes, ' ');
    const caption = el('div', { class: 'caption' });
    let dirty = bytes.length > 0;
    const describe = () => {
      const n = NDEF.normalizeHex(input.value);
      const odd = n.length % 2 === 1;
      const count = Math.floor(n.length / 2);
      let msg = count === 1 ? '1 byte' : count + ' bytes';
      let bad = odd;
      if (o.byteCount && count !== o.byteCount) { msg += `, needs ${o.byteCount}`; bad = true; }
      if (odd) msg += ', half a byte at the end';
      caption.textContent = msg; caption.style.color = bad && dirty ? 'var(--red)' : '';
      bytes = odd ? new Uint8Array() : (NDEF.fromHex(n) || new Uint8Array());
      return bad;
    };
    input.addEventListener('input', () => {
      dirty = true;
      const pos = input.selectionStart;
      const raw = NDEF.normalizeHex(input.value);
      const formatted = raw.match(/.{1,2}/g)?.join(' ') || '';
      input.value = formatted;
      try { input.setSelectionRange(Math.min(formatted.length, pos + (formatted.length > raw.length ? 1 : 0)), Math.min(formatted.length, pos + 1)); } catch (e) { /* ignore */ }
      describe();
      o.onChange && o.onChange(bytes);
    });
    describe();
    const body = el('div', { class: 'body' }, o.label ? el('div', { class: 'title', text: o.label }) : null, input, caption);
    return el('div', { class: 'cell plain' }, body);
  }
  function emptyState(o) { return el('div', { class: 'empty-state' }, icon(o.icon), el('h3', { text: o.title }), o.text ? el('p', { text: o.text }) : null); }
  function hexDump(bytes, pageSize, start = 0) {
    const lines = [];
    for (let i = 0; i < bytes.length; i += pageSize) {
      const chunk = bytes.slice(i, i + pageSize);
      lines.push((start + i / pageSize).toString(16).toUpperCase().padStart(2, '0') + ': ' + NDEF.hex(chunk, ' ').padEnd(pageSize * 3 - 1) + '  ' + NDEF.ascii(chunk));
    }
    return el('pre', { class: 'hexdump', text: lines.join('\n') });
  }
  const dateLabel = (iso) => { const d = new Date(iso); return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' }) + ', ' + d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' }); };
  const bytesLabel = (n) => (n === 1 ? '1 byte' : n + ' bytes');

  // Navigation
  function navButton(o) {
    const b = el('button', { class: 'navbtn' + (o.cls ? ' ' + o.cls : ''), type: 'button', 'aria-label': o.label || o.title, onClick: o.onClick });
    if (o.icon) b.append(icon(o.icon));
    if (o.title) b.append(el('span', { text: o.title, style: o.bold ? 'font-weight:600' : '' }));
    return b;
  }
  class NavStack {
    constructor(container, opts = {}) { this.container = container; this.hasTabbar = opts.hasTabbar !== false; this.stack = []; }
    get top() { return this.stack[this.stack.length - 1]; }
    build(screen, depth) {
      const node = el('div', { class: 'screen' });
      const bar = el('div', { class: 'navbar' });
      const left = el('div', { class: 'left' });
      const title = el('div', { class: 'title' + (screen.largeTitle ? '' : ' visible'), text: screen.title });
      const right = el('div', { class: 'right' });
      bar.append(left, title, right);
      const content = el('div', { class: 'content' + (this.hasTabbar ? '' : ' no-tabbar') });
      node.append(bar, content);
      const ctx = { nav: this, node, content, screen, refresh: () => this.renderContent(entry), setTitle: (t) => { title.textContent = t; screen.title = t; } };
      const entry = { screen, node, content, left, right, ctx, title };
      if (depth > 0) left.append(navButton({ icon: 'back', title: this.stack[depth - 1].screen.backTitle || this.stack[depth - 1].screen.title || 'Back', cls: 'back', onClick: () => this.pop() }));
      if (screen.left) screen.left(ctx).forEach((b) => left.append(b));
      this.renderContent(entry);
      content.addEventListener('scroll', () => { node.classList.toggle('scrolled', content.scrollTop > (screen.largeTitle ? 30 : 2)); }, { passive: true });
      return entry;
    }
    renderContent(entry) {
      const { screen, content, right, ctx } = entry;
      const scrollTop = content.scrollTop;
      content.replaceChildren();
      right.replaceChildren();
      if (screen.largeTitle) content.append(el('h1', { class: 'large-title', text: screen.title }));
      const body = screen.build(ctx);
      content.append(body);
      (screen.right ? screen.right(ctx) : []).forEach((b) => right.append(b));
      content.scrollTop = scrollTop;
      if (screen.onAppear) screen.onAppear(ctx);
    }
    push(screen, animate = true) {
      const entry = this.build(screen, this.stack.length);
      const prev = this.top;
      if (animate && prev) entry.node.classList.add('enter');
      this.container.append(entry.node);
      this.stack.push(entry);
      if (animate && prev) { void entry.node.offsetWidth; entry.node.classList.remove('enter'); prev.node.classList.add('under'); }
      return entry.ctx;
    }
    pop() {
      if (this.stack.length < 2) return;
      const entry = this.stack.pop();
      const prev = this.top;
      entry.node.classList.add('leaving');
      prev.node.classList.remove('under');
      if (prev.screen.onReturn) prev.screen.onReturn(prev.ctx);
      setTimeout(() => entry.node.remove(), 340);
    }
    popToRoot() { while (this.stack.length > 1) { const e = this.stack.pop(); e.node.remove(); } this.top.node.classList.remove('under'); if (this.top.screen.onReturn) this.top.screen.onReturn(this.top.ctx); }
    refreshTop() { if (this.top) this.renderContent(this.top); }
    refreshAll() { this.stack.forEach((e) => this.renderContent(e)); }
  }

  // Modal layers
  const host = () => document.getElementById('device');
  function layer(inner, onDim) {
    const l = el('div', { class: 'layer' });
    const dim = el('div', { class: 'dim', onClick: onDim });
    l.append(dim, inner);
    host().append(l);
    void l.offsetWidth;
    l.classList.add('open');
    return { node: l, close: () => { l.classList.remove('open'); setTimeout(() => l.remove(), 320); } };
  }
  function sheet(o) {
    const node = el('div', { class: 'sheet' });
    node.append(el('div', { class: 'grabber' }));
    const nav = new NavStack(node, { hasTabbar: false });
    let handle;
    const ctx = { close: () => handle.close() };
    const screen = Object.assign({}, o, {
      left: (c) => (o.left ? o.left(Object.assign(c, ctx)) : [navButton({ title: o.cancelTitle || 'Cancel', onClick: () => { handle.close(); o.onCancel && o.onCancel(); } })]),
      right: (c) => (o.right ? o.right(Object.assign(c, ctx)) : []),
      build: (c) => o.build(Object.assign(c, ctx)),
    });
    handle = layer(node, () => { if (!o.modal) { handle.close(); o.onCancel && o.onCancel(); } });
    nav.push(screen, false);
    return ctx;
  }
  function alert(o) {
    return new Promise((resolve) => {
      const box = el('div', { class: 'alert-box', role: 'alertdialog' });
      const text = el('div', { class: 'text' }, el('h2', { text: o.title }), o.message ? el('p', { text: o.message }) : null);
      let input = null;
      if (o.field) { input = el('input', { type: 'text', placeholder: o.field.placeholder || '', autocapitalize: 'sentences' }); input.value = o.field.value || ''; text.append(el('div', { class: 'field' }, input)); }
      const buttons = o.buttons || [{ title: 'OK', bold: true }];
      const bar = el('div', { class: 'buttons' + (buttons.length > 2 ? ' stacked' : '') });
      let handle;
      buttons.forEach((b) => bar.append(el('button', { type: 'button', text: b.title, class: (b.bold ? 'bold ' : '') + (b.style === 'destructive' ? 'destructive' : ''), onClick: () => { handle.close(); resolve({ button: b.id || b.title, value: input ? input.value : null }); } })));
      box.append(text, bar);
      handle = layer(box, null);
      if (input) setTimeout(() => input.focus(), 350);
    });
  }
  const confirm = async (o) => (await alert({ title: o.title, message: o.message, buttons: [{ title: 'Cancel', id: 'cancel', bold: !o.destructive }, { title: o.confirmTitle || 'OK', id: 'ok', style: o.destructive ? 'destructive' : 'default', bold: !!o.destructive || o.bold }] })).button === 'ok';
  const prompt = async (o) => { const r = await alert({ title: o.title, message: o.message, field: { placeholder: o.placeholder, value: o.value }, buttons: [{ title: 'Cancel', id: 'cancel' }, { title: o.confirmTitle || 'Save', id: 'ok', bold: true }] }); return r.button === 'ok' ? r.value : null; };
  function actionSheet(o) {
    return new Promise((resolve) => {
      const node = el('div', { class: 'action-sheet' });
      const group = el('div', { class: 'group' });
      if (o.title || o.message) group.append(el('div', { class: 'head', text: [o.title, o.message].filter(Boolean).join('\n') }));
      let handle;
      o.actions.forEach((a) => group.append(el('button', { type: 'button', class: 'action' + (a.destructive ? ' destructive' : ''), text: a.title, onClick: () => { handle.close(); resolve(a.id || a.title); a.onClick && a.onClick(); } })));
      node.append(group, el('div', { class: 'group' }, el('button', { type: 'button', class: 'action cancel', text: 'Cancel', onClick: () => { handle.close(); resolve(null); } })));
      handle = layer(node, () => { handle.close(); resolve(null); });
    });
  }
  function showError(e) {
    const m = SIM.NFCError.map(e);
    if (m.isCancellation) return Promise.resolve();
    haptic('error');
    return alert({ title: m.title, message: m.message });
  }
  const success = (message) => { haptic('success'); return alert({ title: 'Done', message }); };
  function haptic(kind) {
    if (!STORE.settings.hapticsEnabled || !navigator.vibrate) return;
    try { navigator.vibrate(kind === 'success' ? [15, 60, 15] : kind === 'error' ? [40, 40, 40] : 8); } catch (e) { /* ignore */ }
  }
  async function copy(text) {
    try { await navigator.clipboard.writeText(text); haptic('tap'); return true; }
    catch (e) { const ta = el('textarea', { style: 'position:fixed;opacity:0' }); ta.value = text; document.body.append(ta); ta.select(); let ok = false; try { ok = document.execCommand('copy'); } catch (x) { /* ignore */ } ta.remove(); return ok; }
  }
  function download(name, data, mime) {
    const blob = new Blob([data], { type: mime || 'application/octet-stream' });
    const url = URL.createObjectURL(blob);
    const a = el('a', { href: url, download: name });
    document.body.append(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 2000);
  }
  function openURL(url) { window.open(url, '_blank', 'noopener'); }

  // Simulated system NFC sheet
  const busyListeners = [];
  const nfc = {
    isBusy: false,
    get selectedTagId() { return STORE.settings.simulatedTag || 'ntag216-blank'; },
    set selectedTagId(v) { STORE.settings.simulatedTag = v; STORE.saveSettings(); },
    onBusy(fn) { busyListeners.push(fn); },
    setBusy(v) { nfc.isBusy = v; document.querySelectorAll('button[data-scan]').forEach((b) => { b.disabled = v; }); busyListeners.forEach((fn) => fn(v)); },
    run(o) {
      if (nfc.isBusy) return Promise.reject(SIM.E.failed('Another NFC operation is in progress.'));
      nfc.setBusy(true);
      return new Promise((resolve, reject) => {
        let cancelled = false, presented = false, timer = null, handle;
        const art = el('div', { class: 'art' }, el('div', { class: 'ring pulse' }), el('div', { class: 'ring', style: 'inset:18px;opacity:0.35' }), el('div', { class: 'phone' }, icon('phoneframe')), el('div', { class: 'mark' }));
        const msg = el('div', { class: 'msg', text: o.alertMessage || 'Hold your iPhone near the tag.' });
        const heading = el('h2', { text: 'Ready to Scan' });
        const finish = (fn) => { nfc.setBusy(false); handle.close(); fn(); };
        const cancel = () => { if (cancelled) return; cancelled = true; clearTimeout(timer); finish(() => reject(SIM.E.cancelled())); };
        const chips = el('div', { class: 'chips' });
        const present = async (id) => {
          if (presented || cancelled) return;
          presented = true; clearTimeout(timer);
          nfc.selectedTagId = id;
          chips.querySelectorAll('.chip').forEach((c) => c.classList.toggle('active', c.dataset.id === id));
          art.classList.add('busy'); heading.textContent = 'Scanning';
          const tag = SIM.get(id);
          tag.sessionStart();
          const session = { get alertMessage() { return msg.textContent; }, set alertMessage(v) { msg.textContent = v; }, delay: (ms) => new Promise((r) => setTimeout(r, ms)) };
          try {
            const value = await o.body(session, tag);
            SIM.save();
            if (cancelled) return;
            art.classList.remove('busy'); art.classList.add('success'); art.querySelector('.mark').append(icon('check')); heading.textContent = 'Done'; msg.textContent = o.successMessage || 'Done.';
            haptic('success');
            setTimeout(() => finish(() => resolve(value)), 700);
          } catch (e) {
            SIM.save();
            if (cancelled) return;
            const m = SIM.NFCError.map(e);
            art.classList.remove('busy'); art.classList.add('fail'); art.querySelector('.mark').append(icon('xmark')); heading.textContent = 'Scan failed'; msg.textContent = m.message;
            haptic('error');
            setTimeout(() => finish(() => reject(m)), 1300);
          }
        };
        for (const t of SIM.list()) {
          const chip = el('button', { type: 'button', class: 'chip' + (t.id === nfc.selectedTagId ? ' active' : ''), text: t.name, 'data-id': t.id, onClick: () => present(t.id) });
          chips.append(chip);
        }
        const sim = el('div', { class: 'sim' }, el('div', { class: 'label' }, el('span', { text: 'Simulator: tap a tag to present it' }), el('span', { text: 'auto in 1.5 s' })), chips, el('div', { class: 'hint', text: 'A real iPhone shows this sheet from iOS and reads whatever tag you hold to it. The web preview presents one of these pretend tags instead.' }));
        const card = el('div', { class: 'nfc-card' }, el('button', { class: 'close', type: 'button', 'aria-label': 'Close', onClick: cancel }, icon('xmark')), heading, msg, art, el('button', { class: 'cancel', type: 'button', text: 'Cancel', onClick: cancel }), sim);
        handle = layer(card, cancel);
        timer = setTimeout(() => present(nfc.selectedTagId), 1500);
      });
    },
  };

  return { icon, el, section, row, toggleRow, fieldRow, selectRow, stepperRow, buttonRow, bigButton, segmented, textBlock, hexField, emptyState, hexDump, dateLabel, bytesLabel,
    navButton, NavStack, sheet, alert, confirm, prompt, actionSheet, showError, success, haptic, copy, download, openURL, nfc };
})();
