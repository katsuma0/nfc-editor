// Every screen of the app, built from the UI components. Mirrors the SwiftUI views one for one.
const SCREENS = (() => {
  const { el, row, section, toggleRow, fieldRow, selectRow, stepperRow, buttonRow, bigButton, segmented, textBlock, hexField, emptyState, hexDump, navButton } = UI;
  const app = { navs: {}, select: () => {} };
  const HOLD = 'Hold your iPhone near the tag.';
  const fail = (e) => UI.showError(e);
  const hexSpaced = (h) => (h.match(/.{2}/g) || []).join(' ');

  // Shared pieces
  const settingsButton = () => navButton({ icon: 'gear', label: 'Settings', onClick: openSettings });
  function recordRow(record, onClick) {
    const s = NDEF.parse(record);
    return row({ icon: s.icon, title: s.detail, subtitle: s.title, caption: UI.bytesLabel(NDEF.encodedSize(record)), onClick, subtitleWrap: false });
  }
  const iconColorFor = (kind) => ({ erase: 'var(--red)', copy: 'var(--blue)', lock: 'var(--orange)', memory: '#5856D6', format: '#AF52DE', password: 'var(--green)', advanced: '#48484A', dump: '#FF2D55', counter: 'var(--gray)', signature: '#00C7BE' })[kind];
  const writeBody = (records, options) => (session, tag) => SIM.ops.writeRecords(session, tag, records, options);
  const writeSuccess = (r) => `Wrote ${UI.bytesLabel(r.bytesWritten)}.${r.capacity ? ` ${UI.bytesLabel(Math.max(0, r.capacity - r.bytesWritten))} free.` : ''}${r.locked ? ' The tag is now read only.' : ''}`;

  // Read tab
  function readScreen() {
    return {
      title: 'Read', largeTitle: true,
      right: () => [settingsButton()],
      onReturn: (ctx) => ctx.refresh(),
      build(ctx) {
        const wrap = el('div');
        const hero = el('div', { class: 'hero' }, UI.icon('wave'), el('p', { text: 'Scan a tag to see its chip, serial number, memory and records.' }));
        const scanSection = section({ cls: 'button', rows: [] });
        scanSection.replaceChildren(hero, bigButton({ title: 'Scan tag', icon: 'wave', onClick: () => scan(ctx) }).firstChild);
        wrap.append(scanSection);
        if (STORE.scans.last) wrap.append(section({ header: 'Last scan', rows: [summaryRow(STORE.scans.last, ctx)] }));
        const recent = STORE.scans.history.slice(1);
        if (recent.length) wrap.append(section({ header: 'Recent', rows: recent.map((i) => summaryRow(i, ctx)) }));
        if (!STORE.scans.last) wrap.append(textBlock('Scans are kept for this session. Save a tag from its details to keep it.'));
        return wrap;
      },
    };
    function summaryRow(info, ctx) {
      const n = info.records.length;
      return row({ iconPlain: 'cpu', title: SIM.info.chipLine(info), subtitle: SIM.info.serialLine(info), subtitleMono: true, caption: `${n === 0 ? 'No records' : n === 1 ? '1 record' : n + ' records'}, ${UI.dateLabel(info.scannedAt)}`, onClick: () => ctx.nav.push(tagDetailScreen(info)) });
    }
    async function scan(ctx) {
      const readFull = STORE.settings.readFullMemoryOnScan;
      try {
        const info = await UI.nfc.run({ alertMessage: HOLD, successMessage: 'Tag read.', body: (session, tag) => SIM.ops.readTag(session, tag, { includeDump: readFull }) });
        STORE.recordScan(info);
        ctx.refresh();
        ctx.nav.push(tagDetailScreen(info));
      } catch (e) { fail(e); }
    }
  }

  function tagDetailScreen(info) {
    return {
      title: 'Tag details', backTitle: 'Tag',
      right: (ctx) => [navButton({ icon: 'ellipsis', label: 'More', onClick: () => more(ctx) })],
      build(ctx) {
        const wrap = el('div');
        const r = (title, value, icon, opts = {}) => (value == null ? null : row(Object.assign({ icon, iconBg: '#636366', title, value, valueWrap: true, accessory: 'none' }, opts)));
        const rows = [
          r('Tag type', SIM.info.typeLine(info), 'wave'),
          r('Chip', SIM.info.chipLine(info), 'cpu'),
          r('Technology', info.technology, 'info'),
          r('Serial number', SIM.info.serialLine(info), 'key', { valueMono: true, onClick: () => UI.copy(SIM.info.serialLine(info)).then(() => UI.haptic('tap')), accessory: 'none' }),
          r('ATQA', SIM.info.atqaLine(info), 'number', { valueMono: true }),
          r('SAK', SIM.info.sakLine(info), 'number', { valueMono: true }),
          r('Password protected', info.passwordProtected == null ? 'Unknown' : info.passwordProtected ? 'Yes' : 'No', 'lock'),
          r('Memory', SIM.info.memoryLine(info), 'memorychip'),
          r('Data format', info.chip.nfcForumType ? `NFC Forum Type ${info.chip.nfcForumType}` : 'Unknown', 'doc'),
          r('Size', SIM.info.sizeLine(info), 'grid'),
          r('Writable', SIM.info.writableLine(info), 'pencil'),
          info.counter != null ? r('Counter', String(info.counter) + (info.counterEnabled === false ? ' (disabled)' : ''), 'number') : (info.counterEnabled != null ? r('Counter', info.counterEnabled ? 'Enabled' : 'Disabled', 'number') : null),
          info.signature ? r('Signature', info.signature.slice(0, 16) + '…', 'signature', { valueMono: true, onClick: () => UI.copy(hexSpaced(info.signature)).then(() => UI.alert({ title: 'Copied', message: 'The 32-byte signature is on the clipboard.' })) }) : null,
          ...info.extras.map((f) => r(f.label, f.value, f.icon || 'info', { valueMono: /^[0-9A-F ]+$/.test(f.value) })),
        ];
        if (info.chip.notes) rows.push(r('Note', info.chip.notes, 'info'));
        wrap.append(section({ header: 'Tag', rows }));
        const recordRows = info.records.length ? info.records.map((rec) => recordRow(rec, () => ctx.nav.push(recordDetailScreen(rec)))) : [row({ title: 'No records', cls: 'center', accessory: 'none' })];
        wrap.append(section({ header: 'Records', rows: recordRows, footer: info.ndefStatus === 'notSupported' ? 'The tag is not NDEF formatted, or its records are password protected.' : null }));
        if (info.dump) wrap.append(section({ header: 'Memory', rows: [row({ icon: 'memorychip', iconBg: '#5856D6', title: 'View memory dump', subtitle: `${info.dump.pages.length} pages`, onClick: () => ctx.nav.push(memoryDumpScreen(info.dump)) })] }));
        return wrap;
      },
    };
    async function more(ctx) {
      const choice = await UI.actionSheet({ actions: [
        { title: 'Save tag', id: 'save' }, { title: 'Edit in Write tab', id: 'edit' }, { title: 'Share as JSON', id: 'share' }, { title: 'Copy serial number', id: 'copy' },
      ] });
      if (choice === 'save') { const name = await UI.prompt({ title: 'Save tag', message: 'Give this tag a name.', value: `${info.chip.name} ${SIM.info.serialLine(info).slice(-5)}` }); if (name) { STORE.add(STORE.makeTag(name.trim() || info.chip.name, info)); UI.haptic('success'); UI.alert({ title: 'Saved', message: 'Find it in the Saved tab.' }); } }
      if (choice === 'edit') sendToWrite(info.records.map((r) => NDEF.fromRecord(r)));
      if (choice === 'share') UI.download(`tag-${SIM.info.serialLine(info).replace(/:/g, '')}.json`, STORE.exportText(STORE.makeTag(info.chip.name, info)), 'application/json');
      if (choice === 'copy') { await UI.copy(SIM.info.serialLine(info)); UI.alert({ title: 'Copied', message: SIM.info.serialLine(info) }); }
    }
  }

  function recordDetailScreen(record) {
    const s = NDEF.parse(record);
    return {
      title: s.title,
      right: (ctx) => [navButton({ title: 'Edit', onClick: () => sendToWrite([NDEF.fromRecord(record)]) })],
      build() {
        const wrap = el('div');
        wrap.append(section({ rows: [row({ icon: s.icon, title: s.detail, subtitle: s.title, subtitleWrap: true, accessory: 'none' }), ...s.fields.map((f) => row({ title: f.label, value: f.value, valueWrap: true, accessory: 'none' }))] }));
        wrap.append(section({ rows: s.actions.map((a) => buttonRow({ icon: a.type === 'open' ? 'link' : a.type === 'copy' ? 'copy' : a.type === 'wifi' ? 'wifi' : 'person', title: a.label, onClick: () => act(a) })) }));
        const t = NDEF.typeString(record);
        wrap.append(section({ header: 'Technical', rows: [
          row({ title: 'Type name format', value: NDEF.TNF_LABEL[record.tnf], accessory: 'none' }),
          row({ title: 'Type', value: t || 'None', valueMono: true, accessory: 'none' }),
          row({ title: 'Identifier', value: record.id.length ? NDEF.hex(record.id, ' ') : 'None', valueMono: true, accessory: 'none' }),
          row({ title: 'Payload', value: UI.bytesLabel(record.payload.length), accessory: 'none' }),
          el('div', { class: 'cell plain' }, el('div', { class: 'result-row', text: record.payload.length ? NDEF.hex(record.payload, ' ') : 'Empty' })),
          record.payload.length ? el('div', { class: 'cell plain' }, el('div', { class: 'result-row', text: NDEF.ascii(record.payload) })) : null,
        ] }));
        return wrap;
      },
    };
    async function act(a) {
      if (a.type === 'open') UI.openURL(a.value);
      else if (a.type === 'copy') { await UI.copy(a.value); UI.alert({ title: 'Copied', message: a.value }); }
      else if (a.type === 'wifi') { const ok = await UI.confirm({ title: `Join “${a.value.ssid}”?`, message: 'On an iPhone this joins the network right away. The web preview only shows the dialog.', confirmTitle: 'Join' }); if (ok) UI.alert({ title: 'Joined', message: `Connected to ${a.value.ssid}.` }); }
      else if (a.type === 'vcard') UI.download(`${NDEF.fullName(a.value) || 'contact'}.vcf`, NDEF.encodeVCard(a.value), 'text/vcard');
    }
  }

  function memoryDumpScreen(dump) {
    return {
      title: 'Memory dump',
      right: () => [navButton({ icon: 'share', label: 'Share', onClick: () => UI.download('memory.bin', SIM.dumpFlat(dump), 'application/octet-stream') })],
      build() {
        const wrap = el('div');
        wrap.append(section({ rows: dump.pages.map((p) => pageRow(p)), footer: 'Pages in red could not be read. Use the memory editor in Tools to change a page.' }));
        return wrap;
      },
    };
  }
  function pageRow(p, onClick, note) {
    const node = row({ onClick, accessory: 'none', custom: el('div', { class: 'page-row' + (p.readable ? '' : ' unreadable') }, el('span', { class: 'idx', text: '0x' + p.index.toString(16).toUpperCase().padStart(2, '0') }), el('span', { class: 'bytes', text: p.readable ? NDEF.hex(p.bytes, ' ') : 'protected' }), el('span', { class: 'ascii', text: p.readable ? NDEF.ascii(p.bytes) : '' }), note ? el('span', { class: 'tag', text: note }) : null) });
    node.querySelector('.body').style.flex = '1';
    return node;
  }

  function sendToWrite(drafts) {
    STORE.queue.drafts = drafts.map((d) => Object.assign({}, d, { id: STORE.uuid() }));
    STORE.saveQueue();
    app.select('write');
    const nav = app.navs.write; if (nav) { nav.popToRoot(); nav.refreshTop(); }
  }

  // Write tab
  function writeScreen() {
    let editing = false;
    return {
      title: 'Write', largeTitle: true,
      right: (ctx) => [navButton({ icon: 'ellipsis', label: 'More', onClick: () => more(ctx) }), navButton({ title: editing ? 'Done' : 'Edit', bold: editing, onClick: () => { editing = !editing; ctx.refresh(); } })],
      onReturn: (ctx) => ctx.refresh(),
      build(ctx) {
        const q = STORE.queue;
        const wrap = el('div');
        const rows = q.drafts.map((d, i) => draftRow(d, i, ctx));
        rows.push(row({ icon: 'plus', iconBg: 'var(--green)', title: 'Add a record', blue: true, accessory: 'none', onClick: () => UI.sheetAddRecord((kind) => openEditor(ctx, NDEF.draft(kind, kind === 'text' ? { language: STORE.settings.defaultLanguage } : {}))) }));
        const n = q.drafts.length;
        wrap.append(section({ header: 'Records', rows, footer: n ? `${n === 1 ? '1 record' : n + ' records'}, ${UI.bytesLabel(STORE.queueBytes())}. An NTAG213 holds 140 bytes, an NTAG215 496, an NTAG216 868.` : 'Add a record, then hold a tag to the phone to write it.' }));
        const o = q.options;
        const summary = [o.verifyAfterWrite ? 'Verify after write' : null, o.eraseFirst ? 'Erase first' : null, o.lockAfterWrite ? 'Lock after write' : null].filter(Boolean).join(', ') || 'None';
        wrap.append(section({ header: 'Options', rows: [row({ icon: 'gear', iconBg: '#636366', title: 'Write options', subtitle: summary, onClick: () => ctx.nav.push(writeOptionsScreen()) })] }));
        wrap.append(bigButton({ title: 'Write to tag', icon: 'wave', disabled: !n, onClick: () => write(ctx) }));
        return wrap;
      },
    };
    function draftRow(d, i, ctx) {
      const k = NDEF.kindInfo(d.kind);
      const err = NDEF.validate(d);
      const q = STORE.queue;
      if (!editing) return row({ icon: k.icon, title: NDEF.summary(d), subtitle: k.name + (err ? ', needs attention' : ''), caption: UI.bytesLabel(NDEF.draftSize(d)), onClick: () => openEditor(ctx, d) });
      const up = el('button', { type: 'button', 'aria-label': 'Move up', onClick: () => { q.drafts.splice(i - 1, 0, q.drafts.splice(i, 1)[0]); STORE.saveQueue(); ctx.refresh(); } }, UI.icon('up'));
      const down = el('button', { type: 'button', 'aria-label': 'Move down', onClick: () => { q.drafts.splice(i + 1, 0, q.drafts.splice(i, 1)[0]); STORE.saveQueue(); ctx.refresh(); } }, UI.icon('down'));
      up.disabled = i === 0; down.disabled = i === q.drafts.length - 1;
      const remove = el('button', { class: 'remove-btn', type: 'button', 'aria-label': 'Remove', onClick: () => { q.drafts.splice(i, 1); STORE.saveQueue(); ctx.refresh(); } }, UI.icon('minus'));
      const node = row({ title: NDEF.summary(d), subtitle: k.name, right: el('div', { class: 'reorder' }, up, down), accessory: 'none' });
      node.prepend(remove);
      return node;
    }
    function openEditor(ctx, d) {
      UI.sheetRecordEditor(d, (saved) => {
        const q = STORE.queue;
        const idx = q.drafts.findIndex((x) => x.id === saved.id);
        if (idx >= 0) q.drafts[idx] = saved; else q.drafts.push(saved);
        STORE.saveQueue(); ctx.refresh();
      });
    }
    async function write(ctx) {
      let records;
      try { records = STORE.queueRecords(); } catch (e) { return UI.alert({ title: 'Check the input', message: e.message }); }
      const options = Object.assign({}, STORE.queue.options);
      try {
        const r = await UI.nfc.run({ alertMessage: HOLD, successMessage: 'Written.', body: writeBody(records, options) });
        STORE.queue.options.lockAfterWrite = false; STORE.saveQueue(); ctx.refresh();
        UI.success(writeSuccess(r));
      } catch (e) { fail(e); }
    }
    async function more(ctx) {
      const choice = await UI.actionSheet({ actions: [{ title: 'Save as profile', id: 'save' }, { title: 'Clear all', id: 'clear', destructive: true }] });
      if (choice === 'save') { if (!STORE.queue.drafts.length) return UI.alert({ title: 'Nothing to save', message: 'Add a record first.' }); const name = await UI.prompt({ title: 'Save as profile', message: 'Give this set of records a name.', value: 'New profile' }); if (name) { STORE.add(STORE.makeProfile(name.trim() || 'New profile', STORE.queue.drafts)); UI.haptic('success'); UI.alert({ title: 'Saved', message: 'Find it under Profiles in the Saved tab.' }); } }
      if (choice === 'clear') { if (await UI.confirm({ title: 'Clear all records?', confirmTitle: 'Clear', destructive: true })) { STORE.queue.drafts = []; STORE.saveQueue(); ctx.refresh(); } }
    }
  }
  function writeOptionsScreen() {
    return {
      title: 'Write options',
      build() {
        const o = STORE.queue.options;
        const wrap = el('div');
        wrap.append(section({ rows: [
          toggleRow({ title: 'Verify after write', subtitle: 'Reads the tag back and compares it.', value: o.verifyAfterWrite, onChange: (v) => { o.verifyAfterWrite = v; STORE.saveQueue(); } }),
          toggleRow({ title: 'Erase before write', subtitle: 'Writes an empty record first.', value: o.eraseFirst, onChange: (v) => { o.eraseFirst = v; STORE.saveQueue(); } }),
        ] }));
        wrap.append(section({ rows: [toggleRow({ title: 'Lock tag after write', value: o.lockAfterWrite, onChange: (v) => { o.lockAfterWrite = v; STORE.saveQueue(); } })], footer: 'Locking is permanent. A locked tag can never be written again, by any app. The switch resets after every write.', footerClass: 'danger' }));
        return wrap;
      },
    };
  }
  UI.sheetAddRecord = (onPick) => {
    UI.sheet({ title: 'Add a record', build(ctx) {
      const wrap = el('div');
      wrap.append(section({ rows: NDEF.WRITABLE.map((id) => { const k = NDEF.kindInfo(id); return row({ icon: k.icon, title: k.name, subtitle: k.blurb, subtitleWrap: true, onClick: () => { ctx.close(); setTimeout(() => onPick(id), 320); } }); }) }));
      return wrap;
    } });
  };
  UI.sheetRecordEditor = (initial, onSave) => {
    const d = JSON.parse(JSON.stringify(initial));
    const k = NDEF.kindInfo(d.kind);
    let saveBtn, footer;
    const validateNow = () => { const err = NDEF.validate(d); if (saveBtn) saveBtn.disabled = !!err; if (footer) { footer.textContent = err || `${UI.bytesLabel(NDEF.draftSize(d))} on the tag.`; footer.classList.toggle('danger', !!err); } };
    UI.sheet({
      title: k.name,
      right: (ctx) => { saveBtn = navButton({ title: 'Save', bold: true, onClick: () => { if (NDEF.validate(d)) return; ctx.close(); onSave(d); } }); validateNow(); return [saveBtn]; },
      build() {
        const wrap = el('div');
        const f = (key, label, opts = {}) => fieldRow(Object.assign({ label, value: d.fields[key] || '', onInput: (v) => { d.fields[key] = v; validateNow(); } }, opts));
        const sel = (key, title, options) => selectRow({ title, value: d.fields[key], options, onChange: (v) => { d.fields[key] = v; validateNow(); } });
        const tog = (key, title, subtitle, rerender) => toggleRow({ title, subtitle, value: d.fields[key] === 'true', onChange: (v) => { d.fields[key] = String(v); if (rerender) render(); else validateNow(); } });
        const payloadRows = () => [tog('payloadIsHex', 'Payload is hex', null, true), d.fields.payloadIsHex === 'true' ? f('payloadHex', null, { placeholder: 'Payload in hex', mono: true, autocap: 'characters' }) : f('payloadText', null, { placeholder: 'Payload text', multiline: true, autocap: 'sentences' })];
        const makeRows = () => {
          switch (d.kind) {
            case 'text': return [f('text', null, { placeholder: 'Text', multiline: true, autocap: 'sentences', autocorrect: true }), f('language', 'Language', { placeholder: 'en', maxLength: 5 })];
            case 'url': return [f('url', null, { placeholder: 'https://example.com', type: 'url', inputmode: 'url' })];
            case 'customURI': return [f('url', null, { placeholder: 'myapp://open?id=1', type: 'url', inputmode: 'url' })];
            case 'email': return [f('email', 'To', { placeholder: 'name@example.com', type: 'email', inputmode: 'email' }), f('subject', 'Subject', { placeholder: 'Optional', autocap: 'sentences' }), f('body', null, { placeholder: 'Message (optional)', multiline: true, autocap: 'sentences', autocorrect: true })];
            case 'contact': return [f('firstName', 'First name', { autocap: 'words' }), f('lastName', 'Last name', { autocap: 'words' }), f('organization', 'Organization', { autocap: 'words' }), f('title', 'Job title', { autocap: 'words' }), f('phone', 'Phone', { type: 'tel', inputmode: 'tel' }), f('email', 'Email', { type: 'email', inputmode: 'email' }), f('website', 'Website', { type: 'url', inputmode: 'url' }), f('address', 'Address', { autocap: 'words' }), f('note', 'Note', { autocap: 'sentences' })];
            case 'phone': return [f('phone', null, { placeholder: '+1 905 555 0100', type: 'tel', inputmode: 'tel' })];
            case 'sms': return [f('phone', 'Number', { placeholder: '+1 905 555 0100', type: 'tel', inputmode: 'tel' }), f('body', null, { placeholder: 'Message (optional)', multiline: true, autocap: 'sentences', autocorrect: true })];
            case 'geo': return [f('latitude', 'Latitude', { placeholder: '43.8561', inputmode: 'decimal' }), f('longitude', 'Longitude', { placeholder: '-79.3370', inputmode: 'decimal' }), sel('geoFormat', 'Format', [{ value: 'geo', label: 'geo: URI' }, { value: 'apple', label: 'Apple Maps link' }, { value: 'google', label: 'Google Maps link' }])];
            case 'address': return [f('address', null, { placeholder: 'Street, city, province', multiline: true, autocap: 'words' }), sel('addressFormat', 'Opens in', [{ value: 'apple', label: 'Apple Maps' }, { value: 'google', label: 'Google Maps' }, { value: 'geo', label: 'geo: URI' }])];
            case 'wifi': return [f('ssid', 'Network', { placeholder: 'Name' }), f('password', 'Password', { placeholder: '8 characters or more' }), sel('auth', 'Security', NDEF.WIFI_AUTH.map((a) => ({ value: a[0], label: a[1] }))), sel('encryption', 'Encryption', NDEF.WIFI_ENC.map((a) => ({ value: a[0], label: a[1] }))), tog('hidden', 'Hidden network')];
            case 'bluetooth': return [f('mac', 'Address', { placeholder: 'AA:BB:CC:DD:EE:FF', mono: true, autocap: 'characters' }), f('name', 'Name', { placeholder: 'Optional', autocap: 'words' }), tog('handover', 'Wrap in Handover Select', 'Android pairs from a handover select plus the pairing record.')];
            case 'social': return [sel('platform', 'Platform', NDEF.SOCIAL.map((s) => ({ value: s[0], label: s[1] }))), f('handle', 'Username', { placeholder: 'without the @' })];
            case 'app': return [f('package', 'Package', { placeholder: 'com.example.app' })];
            case 'customMIME': return [f('mime', 'MIME type', { placeholder: 'text/plain' }), ...payloadRows()];
            case 'external': return [f('domain', 'Domain', { placeholder: 'example.com' }), f('externalType', 'Type', { placeholder: 'thing' }), ...payloadRows()];
            case 'raw': case 'unknown': return [sel('tnf', 'Type name format', NDEF.TNF_LABEL.map((l, i) => ({ value: String(i), label: l }))), f('type', 'Type (hex)', { placeholder: '54', mono: true, autocap: 'characters' }), f('identifier', 'Identifier (hex)', { placeholder: 'Optional', mono: true, autocap: 'characters' }), f('payloadHex', null, { placeholder: 'Payload in hex', mono: true, autocap: 'characters', multiline: true })];
            case 'smartPoster': return [f('url', 'URL', { type: 'url' }), f('title', 'Title', { autocap: 'sentences' })];
            case 'empty': return [row({ title: 'Nothing to edit. An empty record takes 3 bytes.', accessory: 'none' })];
            default: return [row({ title: 'Nothing to edit.', accessory: 'none' })];
          }
        };
        footer = el('div', { class: 'section-footer' });
        const render = () => { wrap.replaceChildren(section({ rows: makeRows(), footer })); validateNow(); };
        render();
        return wrap;
      },
    });
  };

  // Tools tab
  const TOOLS = [
    ['erase', 'Erase tag', 'Writes an empty record', 'eraser', () => eraseTool()],
    ['copy', 'Copy tag', 'Read one tag, write another', 'docs', () => copyTool()],
    ['lock', 'Lock tag', 'Make a tag read only, forever', 'lock', () => lockTool()],
    ['memory', 'Memory editor', 'Read and edit single pages', 'memorychip', () => memoryEditorTool()],
    ['format', 'Format memory', 'Prepare a blank tag for NDEF', 'format', () => formatTool()],
    ['password', 'Password', 'Set or remove an NTAG password', 'key', () => passwordTool()],
    ['advanced', 'Advanced commands', 'Send raw bytes to the chip', 'terminal', () => advancedTool()],
    ['dump', 'Write dump', 'Restore a saved memory image', 'docdown', () => writeDumpTool()],
    ['counter', 'Counter', 'Read or switch the scan counter', 'number', () => counterTool()],
    ['signature', 'Signature', 'Read the NXP originality signature', 'signature', () => signatureTool()],
  ];
  function toolsScreen() {
    return {
      title: 'Tools', largeTitle: true,
      right: () => [settingsButton()],
      build(ctx) {
        const wrap = el('div');
        wrap.append(section({ rows: TOOLS.map(([id, title, subtitle, icon, make]) => row({ icon, iconBg: iconColorFor(id), title, subtitle, onClick: () => ctx.nav.push(make()) })), footer: 'Every tool starts with a scan. Nothing is written until you tap the blue button and hold a tag to the phone.' }));
        return wrap;
      },
    };
  }
  const toolScreen = (title, build) => ({ title, build });
  function eraseTool() {
    let zero = false;
    return toolScreen('Erase tag', () => {
      const wrap = el('div');
      wrap.append(section({ rows: [toggleRow({ title: 'Also zero the whole user memory', value: zero, onChange: (v) => { zero = v; } })], footer: 'Erase writes one empty record so the tag reads as blank. The switch also overwrites every user page with zeros.' }));
      wrap.append(bigButton({ title: 'Erase tag', icon: 'eraser', destructive: true, onClick: async () => {
        if (!await UI.confirm({ title: 'Erase the next tag you scan?', message: 'Its records are gone for good.', confirmTitle: 'Erase', destructive: true })) return;
        try { await UI.nfc.run({ alertMessage: HOLD, successMessage: 'Erased.', body: (s, t) => SIM.ops.erase(s, t, zero) }); UI.success('The tag is empty.'); } catch (e) { fail(e); }
      } }));
      return wrap;
    });
  }
  function copyTool() {
    let source = null, cloneRaw = false;
    return {
      title: 'Copy tag',
      build(ctx) {
        const wrap = el('div');
        if (!source) {
          wrap.append(section({ rows: [row({ icon: 'docs', title: 'Step 1 of 2', subtitle: 'Scan the tag you want to copy.', subtitleWrap: true, accessory: 'none' })] }));
          wrap.append(bigButton({ title: 'Scan source tag', icon: 'wave', onClick: async () => { try { source = await UI.nfc.run({ alertMessage: 'Hold your iPhone near the source tag.', successMessage: 'Tag read.', body: (s, t) => SIM.ops.readTag(s, t, { includeDump: true }) }); ctx.refresh(); } catch (e) { fail(e); } } }));
          return wrap;
        }
        const n = source.records.length;
        wrap.append(section({ header: 'Source', rows: [row({ icon: 'cpu', iconBg: '#636366', title: SIM.info.chipLine(source), subtitle: `${n === 1 ? '1 record' : n + ' records'}, ${UI.bytesLabel(source.ndefUsedBytes || 0)}`, accessory: 'none' }), ...source.records.map((r) => recordRow(r))] }));
        if (source.dump && source.chip.supportsRawPages) wrap.append(section({ rows: [toggleRow({ title: 'Clone raw memory instead of records', value: cloneRaw, onChange: (v) => { cloneRaw = v; ctx.refresh(); } })], footer: 'Raw cloning copies every user page, which only makes sense between two chips of the same type.' }));
        wrap.append(bigButton({ title: 'Write to destination tag', icon: 'wave', disabled: !n && !cloneRaw, onClick: async () => {
          try {
            if (cloneRaw) { const written = await UI.nfc.run({ alertMessage: 'Hold your iPhone near the destination tag.', successMessage: 'Written.', body: (s, t) => SIM.ops.writeDump(s, t, source.dump, null, null) }); UI.success(`Wrote ${written} pages.`); }
            else { const r = await UI.nfc.run({ alertMessage: 'Hold your iPhone near the destination tag.', successMessage: 'Written.', body: writeBody(source.records, { verifyAfterWrite: true }) }); UI.success(writeSuccess(r)); }
          } catch (e) { fail(e); }
        } }));
        wrap.append(section({ rows: [buttonRow({ title: 'Start over', center: true, onClick: () => { source = null; ctx.refresh(); } })] }));
        return wrap;
      },
    };
  }
  function lockTool() {
    let understood = false;
    return {
      title: 'Lock tag',
      build(ctx) {
        const wrap = el('div');
        wrap.append(section({ rows: [toggleRow({ title: 'I understand this cannot be undone', value: understood, onChange: (v) => { understood = v; ctx.refresh(); } })], footer: 'Locking sets the lock bits on the chip. The tag keeps its records and can be read forever, but nothing can ever write to it again, not this app, not any app.', footerClass: 'danger' }));
        wrap.append(bigButton({ title: 'Lock tag', icon: 'lock', destructive: true, disabled: !understood, onClick: async () => {
          if (!await UI.confirm({ title: 'Lock the next tag you scan?', message: 'This is permanent.', confirmTitle: 'Lock', destructive: true })) return;
          try { await UI.nfc.run({ alertMessage: HOLD, successMessage: 'Locked.', body: (s, t) => SIM.ops.lock(s, t) }); UI.success('The tag is read only now.'); } catch (e) { fail(e); }
        } }));
        return wrap;
      },
    };
  }
  function memoryEditorTool() {
    let dump = null, password = new Uint8Array(), showPassword = false;
    return {
      title: 'Memory editor',
      right: (ctx) => (dump ? [navButton({ icon: 'ellipsis', label: 'More', onClick: async () => { const c = await UI.actionSheet({ actions: [{ title: 'Export as .bin', id: 'bin' }, { title: 'Copy as hex', id: 'hex' }] }); if (c === 'bin') UI.download('memory.bin', SIM.dumpFlat(dump), 'application/octet-stream'); if (c === 'hex') { await UI.copy(NDEF.hex(SIM.dumpFlat(dump), ' ')); UI.alert({ title: 'Copied', message: `${UI.bytesLabel(SIM.dumpFlat(dump).length)} as hex.` }); } } })] : []),
      build(ctx) {
        const wrap = el('div');
        wrap.append(section({ rows: [
          row({ title: 'Password', subtitle: showPassword ? 'Only for tags that need one.' : 'Tap if the tag needs one.', onClick: () => { showPassword = !showPassword; ctx.refresh(); }, accessory: 'none', right: UI.icon(showPassword ? 'up' : 'down', 'chevron') }),
          showPassword ? hexField({ value: password, byteCount: 4, onChange: (b) => { password = b; } }) : null,
        ], footer: 'Reads every page of the chip. Tap a page to change it. Pages 0 to 3 hold the serial number, lock bits and capability container; the last pages hold the configuration.' }));
        wrap.append(bigButton({ title: dump ? 'Read again' : 'Read memory', icon: 'wave', onClick: async () => {
          if (password.length && password.length !== 4) return UI.alert({ title: 'Check the input', message: 'The password must be 4 bytes. Leave it empty if the tag has none.' });
          try { dump = await UI.nfc.run({ alertMessage: HOLD, successMessage: 'Memory read.', body: (s, t) => SIM.ops.readMemory(s, t, password.length ? password : null) }); ctx.refresh(); } catch (e) { fail(e); }
        } }));
        const chip = (dump && dump.chip) || {};
        if (dump) {
          const note = (p) => { if (chip.nfcForumType === 5) return p.index === 0 ? 'CC' : ''; if (!chip.supportsRawPages) return ''; if (p.index <= 1) return 'UID'; if (p.index === 2) return 'lock'; if (p.index === 3) return 'CC'; if (chip.configPage != null && p.index >= chip.configPage) return ['CFG0', 'CFG1', 'PWD', 'PACK'][p.index - chip.configPage] || 'cfg'; if (chip.dynamicLockPage != null && p.index === chip.dynamicLockPage) return 'lock'; return ''; };
          const rows = dump.pages.map((p) => pageRow(p, chip.supportsRawPages === false ? null : () => editPage(p), note(p)));
          wrap.append(section({ header: `${dump.pages.length} pages of ${dump.pageSize} bytes`, rows, footer: chip.supportsRawPages === false ? 'This chip does not allow single pages to be written. The pages show the NDEF file as read from the tag.' : 'Pages marked in red could not be read.' }));
        }
        return wrap;
        function editPage(p) {
          let bytes = p.readable ? new Uint8Array(p.bytes) : new Uint8Array(dump.pageSize);
          const risky = p.index <= 3 || (chip.configPage != null && p.index >= chip.configPage) || (chip.dynamicLockPage != null && p.index === chip.dynamicLockPage);
          UI.sheet({ title: 'Page 0x' + p.index.toString(16).toUpperCase().padStart(2, '0'), build(sctx) {
            const w = el('div');
            w.append(section({ rows: [hexField({ label: 'Bytes', value: bytes, byteCount: dump.pageSize, onChange: (b) => { bytes = b; } })], footer: risky ? 'This page holds the serial number, lock bits, capability container or configuration. A wrong value can lock the tag for good.' : 'The page is written exactly as typed.', footerClass: risky ? 'danger' : null }));
            w.append(bigButton({ title: 'Write page', icon: 'wave', destructive: risky, onClick: async () => {
              if (bytes.length !== dump.pageSize) return UI.alert({ title: 'Check the input', message: `Enter exactly ${UI.bytesLabel(dump.pageSize)}.` });
              if (risky && !await UI.confirm({ title: 'Write a system page?', message: 'This can brick the tag.', confirmTitle: 'Write', destructive: true })) return;
              try { await UI.nfc.run({ alertMessage: HOLD, successMessage: 'Page written.', body: (s, t) => SIM.ops.writePage(s, t, p.index, bytes, password.length ? password : null) }); p.bytes = new Uint8Array(bytes); p.readable = true; sctx.close(); ctx.refresh(); UI.success(`Page ${p.index} written.`); } catch (e) { fail(e); }
            } }));
            return w;
          } });
        }
      },
    };
  }
  function formatTool() {
    return toolScreen('Format memory', () => {
      const wrap = el('div');
      wrap.append(section({ rows: [row({ icon: 'format', iconBg: '#AF52DE', title: 'What it does', subtitle: 'Writes the capability container if page 3 is blank, puts an empty NDEF record at page 4, and zeros the rest of the user memory. Works on NTAG, Ultralight and ICODE tags.', subtitleWrap: true, accessory: 'none' })], footer: 'Page 3 can only be written once per tag, so the app never touches it unless it reads as all zeros.' }));
      wrap.append(bigButton({ title: 'Format tag', icon: 'format', onClick: async () => {
        if (!await UI.confirm({ title: 'Format the next tag you scan?', message: 'Any records on it are erased.', confirmTitle: 'Format', destructive: true })) return;
        try { await UI.nfc.run({ alertMessage: HOLD, successMessage: 'Formatted.', body: (s, t) => SIM.ops.format(s, t) }); UI.success('The tag is formatted and empty.'); } catch (e) { fail(e); }
      } }));
      return wrap;
    });
  }
  function passwordTool() {
    let mode = 'set', password = new Uint8Array(), pack = new Uint8Array([0, 0]), protectReads = false, fromPage = 4, authLimit = 0, current = new Uint8Array(), showCurrent = false, remove = new Uint8Array();
    return {
      title: 'Password',
      build(ctx) {
        const wrap = el('div');
        wrap.append(segmented({ options: [{ value: 'set', label: 'Set' }, { value: 'remove', label: 'Remove' }], value: mode, onChange: (v) => { mode = v; ctx.refresh(); } }));
        if (mode === 'set') {
          wrap.append(section({ rows: [hexField({ label: 'Password', value: password, byteCount: 4, onChange: (b) => { password = b; } }), hexField({ label: 'PACK', value: pack, byteCount: 2, onChange: (b) => { pack = b; } })], footer: 'The PACK is 2 bytes the tag answers with when the password is right. 00 00 is fine.' }));
          wrap.append(section({ rows: [
            toggleRow({ title: 'Also protect reads', subtitle: 'Off: anyone can read, only the password can write.', value: protectReads, onChange: (v) => { protectReads = v; } }),
            stepperRow({ title: 'Protect from page', value: fromPage, min: 0, max: 255, onChange: (v) => { fromPage = v; } }),
            selectRow({ title: 'Wrong attempts allowed', value: String(authLimit), options: [{ value: '0', label: 'Unlimited' }, ...[1, 2, 3, 4, 5, 6, 7].map((n) => ({ value: String(n), label: String(n) }))], onChange: (v) => { authLimit = Number(v); } }),
          ], footer: 'Page 4 is the first page of user memory, so 4 protects everything you can write. With a limit set, the tag stops accepting the password for good after that many wrong tries. Leave it on Unlimited unless you really need it.' }));
          wrap.append(section({ rows: [row({ title: 'Current password', subtitle: 'Only if the tag already has one.', onClick: () => { showCurrent = !showCurrent; ctx.refresh(); }, accessory: 'none', right: UI.icon(showCurrent ? 'up' : 'down', 'chevron') }), showCurrent ? hexField({ value: current, byteCount: 4, onChange: (b) => { current = b; } }) : null] }));
          wrap.append(bigButton({ title: 'Set password', icon: 'key', onClick: async () => {
            if (password.length !== 4) return UI.alert({ title: 'Check the input', message: 'Enter a 4-byte password.' });
            if (pack.length !== 2) return UI.alert({ title: 'Check the input', message: 'Enter a 2-byte PACK, for example 00 00.' });
            if (current.length && current.length !== 4) return UI.alert({ title: 'Check the input', message: 'The current password must be 4 bytes. Leave it empty if the tag has none.' });
            let msg = `The tag you scan next will need ${NDEF.hex(password, ' ')} from page ${fromPage} on. Write the password down first; it cannot be read back from the tag.`;
            if (authLimit) msg += ` After ${authLimit === 1 ? 'one wrong attempt' : authLimit + ' wrong attempts'} the tag stops accepting the password for good.`;
            if (!await UI.confirm({ title: 'Set the password?', message: msg, confirmTitle: 'Set password' })) return;
            try { await UI.nfc.run({ alertMessage: HOLD, successMessage: 'Password set.', body: (s, t) => SIM.ops.setPassword(s, t, { password, pack, protectFromPage: fromPage, protectReads, authLimit, currentPassword: current.length ? current : null }) }); UI.success(`Pages ${fromPage} and up now need the password to ${protectReads ? 'read and write' : 'write'}.`); } catch (e) { fail(e); }
          } }));
        } else {
          wrap.append(section({ rows: [hexField({ label: 'Current password', value: remove, byteCount: 4, onChange: (b) => { remove = b; } })], footer: 'Removes the protection so the tag works like a new one. The password bytes stay on the chip but are no longer required.' }));
          wrap.append(bigButton({ title: 'Remove password', icon: 'key', onClick: async () => {
            if (remove.length !== 4) return UI.alert({ title: 'Check the input', message: 'Enter the current 4-byte password.' });
            try { await UI.nfc.run({ alertMessage: HOLD, successMessage: 'Password removed.', body: (s, t) => SIM.ops.removePassword(s, t, remove) }); UI.success('The tag no longer needs a password.'); } catch (e) { fail(e); }
          } }));
        }
        return wrap;
      },
    };
  }
  const PRESETS = {
    mifare: [['GET_VERSION', '60'], ['READ page 4', '30 04'], ['FAST_READ pages 4 to 7', '3A 04 07'], ['READ_SIG', '3C 00'], ['READ_CNT', '39 02'], ['PWD_AUTH FF FF FF FF', '1B FF FF FF FF'], ['WRITE page 4', 'A2 04 03 00 FE 00']],
    apdu: [['DESFire GetVersion', '90 60 00 00 00'], ['Select NDEF app', '00 A4 04 00 07 D2 76 00 00 85 01 01 00'], ['Select CC file', '00 A4 00 0C 02 E1 03'], ['Read binary 15 bytes', '00 B0 00 00 0F']],
    iso15693: [['Get system info', '02 2B'], ['Read block 0', '02 20 00']],
    feliCa: [['Request system code', '0C'], ['Polling', '00 FF FF 01 00']],
  };
  function advancedTool() {
    let transport = 'mifare', text = '', results = null;
    return {
      title: 'Advanced commands',
      build(ctx) {
        const wrap = el('div');
        wrap.append(segmented({ options: [{ value: 'mifare', label: 'MIFARE' }, { value: 'apdu', label: 'APDU' }, { value: 'iso15693', label: 'ISO 15693' }, { value: 'feliCa', label: 'FeliCa' }], value: transport, onChange: (v) => { transport = v; ctx.refresh(); } }));
        const ta = fieldRow({ value: text, placeholder: 'One command per line, in hex', multiline: true, mono: true, rows: 4, autocap: 'characters', onInput: (v) => { text = v; } });
        wrap.append(section({ rows: [ta, buttonRow({ icon: 'sparkle', title: 'Insert a preset', onClick: async () => { const id = await UI.actionSheet({ title: 'Presets', actions: PRESETS[transport].map(([name, hex], i) => ({ title: `${name}  ${hex}`, id: String(i) })) }); if (id != null) { text = (text.trim() ? text.trim() + '\n' : '') + PRESETS[transport][Number(id)][1]; ctx.refresh(); } } })], footer: { mifare: 'Sent as native MIFARE commands without CRC. NTAG and Ultralight answer with ACK 0A, data, or a NAK.', apdu: 'Sent as ISO 7816 APDUs: CLA INS P1 P2, optional Lc and data, optional Le. The status words come back separately.', iso15693: 'First byte is the request flags, second the command code, the rest parameters.', feliCa: 'The command byte and its parameters. Length and CRC are added by the phone.' }[transport] }));
        wrap.append(bigButton({ title: 'Send', icon: 'wave', onClick: async () => {
          const lines = text.split('\n').map((l) => l.trim()).filter(Boolean);
          if (!lines.length) return UI.alert({ title: 'Check the input', message: 'Enter at least one command.' });
          const commands = [];
          for (const l of lines) { if (!NDEF.isValidHex(l)) return UI.alert({ title: 'Check the input', message: `“${l}” is not whole bytes in hex.` }); commands.push({ transport, bytes: NDEF.fromHex(l) }); }
          try { const out = await UI.nfc.run({ alertMessage: HOLD, successMessage: 'Sent.', body: (s, t) => SIM.ops.sendRaw(s, t, commands) }); results = commands.map((c, i) => ({ command: NDEF.hex(c.bytes, ' '), response: out[i] })); lines.forEach(STORE.addCommandToHistory); ctx.refresh(); } catch (e) { fail(e); }
        } }));
        if (results) wrap.append(section({ header: 'Results', rows: results.map((r) => el('div', { class: 'cell plain' }, el('div', { class: 'result-row' }, el('span', { class: 'k', text: '> ' }), r.command, '\n', el('span', { class: 'k', text: '< ' }), r.response.bytes ? hexSpaced(r.response.bytes) : '(no data)', r.response.sw1 != null ? `  SW ${r.response.sw1.toString(16).toUpperCase().padStart(2, '0')} ${r.response.sw2.toString(16).toUpperCase().padStart(2, '0')}` : '', el('span', { class: 'k', text: `  ${r.response.elapsedMS} ms` })))) }));
        const history = STORE.settings.commandHistory;
        if (history.length) wrap.append(section({ header: 'History', rows: history.slice(0, 10).map((h) => row({ title: h, mono: true, onClick: () => { text = (text.trim() ? text.trim() + '\n' : '') + h; ctx.refresh(); }, accessory: 'none' })) }));
        return wrap;
      },
    };
  }
  function writeDumpTool() {
    let sourceId = 'paste', pasted = '', fileDump = null, fileName = '', from = 4, to = 225, includeSystem = false, password = new Uint8Array();
    const savedWithDumps = () => STORE.items.filter((i) => i.tagInfo && i.tagInfo.dump);
    const currentDump = () => {
      if (sourceId === 'paste') { if (!NDEF.isValidHex(pasted)) return null; return SIM.dumpFromFlat(NDEF.fromHex(pasted), 4); }
      if (sourceId === 'file') return fileDump;
      const it = STORE.item(sourceId); return it ? SIM.restoreDump(it.tagInfo.dump) : null;
    };
    return {
      title: 'Write dump',
      build(ctx) {
        const wrap = el('div');
        const options = [{ value: 'paste', label: 'Pasted hex' }, { value: 'file', label: 'A .bin file' }, ...savedWithDumps().map((i) => ({ value: i.id, label: i.name }))];
        const rows = [selectRow({ title: 'Source', value: sourceId, options, onChange: (v) => { sourceId = v; ctx.refresh(); } })];
        if (sourceId === 'paste') rows.push(fieldRow({ value: pasted, placeholder: 'Hex bytes of the whole memory, page 0 first', multiline: true, mono: true, rows: 5, autocap: 'characters', onInput: (v) => { pasted = v; } }));
        if (sourceId === 'file') { const input = el('input', { type: 'file', style: 'display:none' }); input.addEventListener('change', () => { const f = input.files[0]; if (!f) return; f.arrayBuffer().then((buf) => { fileDump = SIM.dumpFromFlat(new Uint8Array(buf), 4); fileName = f.name; ctx.refresh(); }); }); rows.push(buttonRow({ icon: 'upload', title: fileName ? `${fileName}, ${UI.bytesLabel(SIM.dumpFlat(fileDump).length)}` : 'Choose a file', onClick: () => input.click() })); wrap.append(input); }
        wrap.append(section({ header: 'Dump', rows, footer: 'Saved tags with a memory dump appear in the list. The Read tab saves one with every scan when “Read full memory” is on in Settings.' }));
        wrap.append(section({ header: 'Pages', rows: [stepperRow({ title: 'From page', value: from, min: 0, max: 255, onChange: (v) => { from = v; } }), stepperRow({ title: 'To page', value: to, min: 0, max: 255, onChange: (v) => { to = v; } }), toggleRow({ title: 'Include pages 0 to 3 and config pages', value: includeSystem, onChange: (v) => { includeSystem = v; } })], footer: includeSystem ? 'Serial number pages are always skipped. Lock bytes, the capability container and the configuration pages will be written as they are in the dump, which can lock or brick the tag.' : 'Only user memory inside the range is written. The serial number, lock bytes, capability container and configuration pages are skipped.', footerClass: includeSystem ? 'danger' : null }));
        wrap.append(section({ rows: [hexField({ label: 'Password (optional)', value: password, byteCount: 4, onChange: (b) => { password = b; } })] }));
        wrap.append(bigButton({ title: 'Write dump', icon: 'docdown', onClick: async () => {
          const dump = currentDump();
          if (!dump || !dump.pages.length) return UI.alert({ title: 'Check the input', message: 'Choose a source with at least one page.' });
          if (from > to) return UI.alert({ title: 'Check the input', message: 'The start page must not be after the end page.' });
          if (password.length && password.length !== 4) return UI.alert({ title: 'Check the input', message: 'The password must be 4 bytes. Leave it empty if the tag has none.' });
          if (!await UI.confirm({ title: 'Write the dump?', message: `Pages ${from} to ${to} of the next tag you scan are overwritten.`, confirmTitle: 'Write', destructive: true })) return;
          try {
            const written = await UI.nfc.run({ alertMessage: HOLD, successMessage: 'Written.', body: (s, t) => {
              const chip = t.spec;
              let range = [from, to];
              if (!includeSystem && chip.userRange) range = [Math.max(from, chip.userRange[0]), Math.min(to, chip.userRange[1])];
              else if (includeSystem) range = [Math.max(from, 2), to];
              return SIM.ops.writeDump(s, t, dump, range, password.length ? password : null);
            } });
            UI.success(`Wrote ${written} pages.`);
          } catch (e) { fail(e); }
        } }));
        return wrap;
      },
    };
  }
  function counterTool() {
    let values = null, enable = true;
    return {
      title: 'Counter',
      build(ctx) {
        const wrap = el('div');
        wrap.append(section({ rows: values ? values.map((v, i) => row({ title: values.length > 1 ? `Counter ${i}` : 'Scans', value: String(v), accessory: 'none' })) : [row({ title: 'Not read yet', subtitle: 'NTAG213, 215 and 216 count every scan once the counter is on. Ultralight EV1 has three counters.', subtitleWrap: true, accessory: 'none' })] }));
        wrap.append(bigButton({ title: 'Read counter', icon: 'number', onClick: async () => {
          try { values = await UI.nfc.run({ alertMessage: HOLD, successMessage: 'Counter read.', body: async (s, t) => { if (t.spec.counterCount === 3) { const out = []; for (let a = 0; a < 3; a++) out.push(await SIM.ops.readCounter(s, t, a)); return out; } return [await SIM.ops.readCounter(s, t, 2)]; } }); ctx.refresh(); } catch (e) { fail(e); }
        } }));
        wrap.append(section({ rows: [toggleRow({ title: 'Counter enabled', subtitle: 'Applies to the next NTAG you scan.', value: enable, onChange: (v) => { enable = v; ctx.refresh(); } })] }));
        wrap.append(bigButton({ title: enable ? 'Enable counter' : 'Disable counter', icon: 'wave', onClick: async () => {
          try { await UI.nfc.run({ alertMessage: HOLD, successMessage: enable ? 'Counter enabled.' : 'Counter disabled.', body: (s, t) => SIM.ops.setCounter(s, t, enable, null) }); UI.success(enable ? 'The tag counts scans from now on.' : 'The tag no longer counts scans.'); } catch (e) { fail(e); }
        } }));
        return wrap;
      },
    };
  }
  function signatureTool() {
    let sig = null;
    return {
      title: 'Signature',
      build(ctx) {
        const wrap = el('div');
        wrap.append(section({ rows: [sig ? el('div', { class: 'cell plain' }, el('div', { class: 'result-row', text: hexSpaced(sig) })) : row({ title: 'Not read yet', subtitle: 'NXP signs every NTAG21x and Ultralight EV1 at the factory. The 32 bytes prove the chip is genuine.', subtitleWrap: true, accessory: 'none' }), sig ? buttonRow({ icon: 'copy', title: 'Copy', onClick: async () => { await UI.copy(hexSpaced(sig)); UI.alert({ title: 'Copied', message: '32 bytes as hex.' }); } }) : null], footer: 'Verify it against NXP’s public key with the NXP TagInfo app.' }));
        wrap.append(bigButton({ title: 'Read signature', icon: 'signature', onClick: async () => { try { sig = await UI.nfc.run({ alertMessage: HOLD, successMessage: 'Signature read.', body: (s, t) => SIM.ops.readSignature(s, t) }); ctx.refresh(); } catch (e) { fail(e); } } }));
        return wrap;
      },
    };
  }

  // Saved tab
  function savedScreen() {
    let kind = 'tag', query = '';
    return {
      title: 'Saved', largeTitle: true,
      right: (ctx) => [navButton({ icon: 'download', label: 'Import', onClick: () => importFile(ctx) }), navButton({ icon: 'plus', label: 'New profile', onClick: () => { const it = STORE.add(STORE.makeProfile('New profile', [])); kind = 'profile'; ctx.refresh(); ctx.nav.push(savedDetailScreen(it.id)); } })],
      onReturn: (ctx) => ctx.refresh(),
      build(ctx) {
        const wrap = el('div');
        wrap.append(segmented({ options: [{ value: 'tag', label: 'Tags' }, { value: 'profile', label: 'Profiles' }], value: kind, onChange: (v) => { kind = v; ctx.refresh(); } }));
        const search = el('div', { class: 'searchbar' }, UI.icon('search'), el('input', { type: 'search', placeholder: 'Search', value: query, onInput: (e) => { query = e.target.value; list.replaceChildren(...rowsFor()); } }));
        wrap.append(search);
        const list = el('div');
        const rowsFor = () => { const items = STORE.items.filter((i) => i.kind === kind && (!query || i.name.toLowerCase().includes(query.toLowerCase()))); return items.length ? [section({ rows: items.map((i) => row({ icon: kind === 'tag' ? 'tag' : 'docs', iconBg: kind === 'tag' ? 'var(--orange)' : 'var(--blue)', title: i.name, subtitle: STORE.subtitle(i), caption: UI.dateLabel(i.updatedAt), onClick: () => ctx.nav.push(savedDetailScreen(i.id)) })) })] : [emptyState({ icon: kind === 'tag' ? 'tag' : 'docs', title: kind === 'tag' ? 'No saved tags' : 'No profiles', text: kind === 'tag' ? 'Scan a tag, then choose Save tag from its details.' : 'Build records in the Write tab, then choose Save as profile.' })]; };
        list.append(...rowsFor());
        wrap.append(list);
        return wrap;
      },
    };
    function importFile(ctx) {
      const input = el('input', { type: 'file', accept: '.json,application/json', style: 'display:none' });
      input.addEventListener('change', () => { const f = input.files[0]; if (!f) return; f.text().then((t) => { try { const n = STORE.importText(t); if (!n) return UI.alert({ title: 'Check the input', message: 'The file does not contain any saved items.' }); ctx.refresh(); UI.success(n === 1 ? 'Imported 1 item.' : `Imported ${n} items.`); } catch (e) { UI.alert({ title: 'Something went wrong', message: 'The file could not be read.' }); } }); });
      document.body.append(input); input.click(); setTimeout(() => input.remove(), 60000);
    }
  }
  function savedDetailScreen(id) {
    return {
      title: 'Saved item', backTitle: 'Saved',
      right: (ctx) => [navButton({ icon: 'ellipsis', label: 'More', onClick: () => more(ctx) })],
      onReturn: (ctx) => ctx.refresh(),
      build(ctx) {
        const it = STORE.item(id);
        const wrap = el('div');
        if (!it) { wrap.append(emptyState({ icon: 'trash', title: 'Deleted' })); return wrap; }
        ctx.setTitle(it.name);
        wrap.append(section({ rows: [fieldRow({ label: 'Name', value: it.name, autocap: 'words', onInput: (v) => { it.name = v.trim() || it.name; STORE.update(it); ctx.setTitle(it.name); } })] }));
        const records = STORE.itemRecords(it);
        const recRows = it.kind === 'profile' ? it.drafts.map((d, i) => { const k = NDEF.kindInfo(d.kind); return row({ icon: k.icon, title: NDEF.summary(d), subtitle: k.name, caption: UI.bytesLabel(NDEF.draftSize(d)), onClick: () => UI.sheetRecordEditor(d, (saved) => { it.drafts[i] = saved; STORE.update(it); ctx.refresh(); }) }); }) : records.map((r) => recordRow(r, () => ctx.nav.push(recordDetailScreen(r))));
        if (it.kind === 'profile') recRows.push(row({ icon: 'plus', iconBg: 'var(--green)', title: 'Add a record', blue: true, accessory: 'none', onClick: () => UI.sheetAddRecord((k) => UI.sheetRecordEditor(NDEF.draft(k), (saved) => { it.drafts.push(saved); STORE.update(it); ctx.refresh(); })) }));
        wrap.append(section({ header: 'Records', rows: recRows.length ? recRows : [row({ title: 'No records', cls: 'center', accessory: 'none' })], footer: `${STORE.subtitle(it)}.` }));
        const info = STORE.itemInfo(it);
        if (info) wrap.append(section({ header: 'Tag', rows: [row({ icon: 'cpu', iconBg: '#636366', title: SIM.info.chipLine(info), subtitle: SIM.info.serialLine(info), subtitleMono: true, caption: `Scanned ${UI.dateLabel(info.scannedAt)}`, onClick: () => ctx.nav.push(tagDetailScreen(info)) })] }));
        wrap.append(bigButton({ title: 'Write to tag', icon: 'wave', disabled: !records.length, onClick: async () => {
          let recs; try { recs = it.kind === 'profile' ? it.drafts.flatMap(NDEF.buildAll) : records; } catch (e) { return UI.alert({ title: 'Check the input', message: e.message }); }
          if (!recs.length) return UI.alert({ title: 'Check the input', message: 'Add a record first.' });
          try { const r = await UI.nfc.run({ alertMessage: HOLD, successMessage: 'Written.', body: writeBody(recs, { verifyAfterWrite: true }) }); UI.success(writeSuccess(r)); } catch (e) { fail(e); }
        } }));
        wrap.append(section({ rows: [
          buttonRow({ icon: 'pencil', title: 'Open in Write tab', onClick: () => sendToWrite(it.kind === 'profile' ? it.drafts : records.map(NDEF.fromRecord)) }),
          buttonRow({ icon: 'docs', title: 'Duplicate', onClick: () => { const c = STORE.duplicate(it.id); ctx.nav.pop(); setTimeout(() => ctx.nav.push(savedDetailScreen(c.id)), 350); } }),
          buttonRow({ icon: 'trash', title: it.kind === 'tag' ? 'Delete tag' : 'Delete profile', destructive: true, onClick: async () => { if (await UI.confirm({ title: `Delete “${it.name}”?`, confirmTitle: 'Delete', destructive: true })) { STORE.remove(it.id); ctx.nav.pop(); } } }),
        ] }));
        return wrap;
      },
    };
    async function more(ctx) {
      const it = STORE.item(id); if (!it) return;
      const actions = [{ title: 'Share as JSON', id: 'share' }];
      if (it.tagInfo && it.tagInfo.dump) actions.push({ title: 'Export memory dump (.bin)', id: 'dump' });
      const c = await UI.actionSheet({ actions });
      if (c === 'share') UI.download(`${it.name.replace(/[^\w.-]+/g, '-').toLowerCase() || 'item'}.json`, STORE.exportText(it), 'application/json');
      if (c === 'dump') UI.download(`${it.name.replace(/[^\w.-]+/g, '-').toLowerCase() || 'memory'}.bin`, SIM.dumpFlat(SIM.restoreDump(it.tagInfo.dump)), 'application/octet-stream');
    }
  }

  // Settings
  function openSettings() {
    UI.sheet({ title: 'Settings', cancelTitle: 'Done', build(ctx) {
      const s = STORE.settings;
      const wrap = el('div');
      wrap.append(section({ header: 'Scanning', rows: [
        toggleRow({ title: 'Read full memory on scan', subtitle: 'Slower, but saves a dump with every tag.', value: s.readFullMemoryOnScan, onChange: (v) => { s.readFullMemoryOnScan = v; STORE.saveSettings(); } }),
        toggleRow({ title: 'Verify after write', value: s.verifyAfterWrite, onChange: (v) => { s.verifyAfterWrite = v; STORE.queue.options.verifyAfterWrite = v; STORE.saveSettings(); STORE.saveQueue(); } }),
        fieldRow({ label: 'Default text language', value: s.defaultLanguage, placeholder: 'en', maxLength: 5, onInput: (v) => { s.defaultLanguage = v.trim() || 'en'; STORE.saveSettings(); } }),
      ] }));
      wrap.append(section({ header: 'Phone', rows: [
        toggleRow({ title: 'Haptics', value: s.hapticsEnabled, onChange: (v) => { s.hapticsEnabled = v; STORE.saveSettings(); } }),
        toggleRow({ title: 'Keep screen awake', value: s.keepScreenAwake, onChange: (v) => { s.keepScreenAwake = v; STORE.saveSettings(); UI.applyWakeLock && UI.applyWakeLock(v); } }),
      ] }));
      wrap.append(section({ header: 'Preview', rows: [
        selectRow({ title: 'Simulated tag', value: UI.nfc.selectedTagId, options: SIM.list().map((t) => ({ value: t.id, label: t.name })), onChange: (v) => { UI.nfc.selectedTagId = v; } }),
        buttonRow({ icon: 'format', title: 'Reset simulated tags', onClick: async () => { if (await UI.confirm({ title: 'Reset the pretend tags?', message: 'Every simulated tag goes back to its factory state.', confirmTitle: 'Reset', destructive: true })) { SIM.reset(); UI.alert({ title: 'Done', message: 'The tags are back to how they started.' }); } } }),
        buttonRow({ icon: 'trash', title: 'Clear command history', destructive: true, onClick: () => { STORE.clearCommandHistory(); UI.haptic('tap'); } }),
      ], footer: 'The simulated tag is what the scan sheet presents when you do not tap a different one.' }));
      wrap.append(section({ rows: [row({ icon: 'info', iconBg: '#636366', title: 'About', onClick: () => ctx.nav.push(aboutScreen()) })] }));
      return wrap;
    } });
  }
  function aboutScreen() {
    return { title: 'About', build() {
      const wrap = el('div');
      wrap.append(section({ rows: [row({ icon: 'wave', title: 'NFC Editor', subtitle: 'Web preview of version 1.0', accessory: 'none' })] }));
      wrap.append(section({ rows: [row({ title: 'Reads, writes and edits NFC tags. Every tool that other apps sell as an upgrade is here and free.', subtitleWrap: true, accessory: 'none' })], footer: 'Everything stays on your iPhone. No accounts, no analytics.' }));
      wrap.append(section({ rows: [row({ title: 'Source on GitHub', blue: true, onClick: () => UI.openURL('https://github.com/katsuma0/nfc-editor'), accessory: 'chevron' })], footer: 'iOS cannot read MIFARE Classic data or emulate a tag, so this app does not either.' }));
      return wrap;
    } };
  }

  return { app, read: readScreen, write: writeScreen, tools: toolsScreen, saved: savedScreen, openSettings };
})();
