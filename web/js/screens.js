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
  const iconColorFor = (kind) => ({ erase: 'var(--red)', copy: 'var(--blue)', lock: 'var(--orange)', memory: '#5856D6', format: '#AF52DE', password: 'var(--green)', advanced: '#48484A', dump: '#FF2D55', counter: 'var(--gray)', signature: '#00C7BE',
    mirror: '#32ADE6', lockpages: '#C2410C', ulc: '#B7791F', desfire: '#1F7A4D', type5: '#0E6BA8', felica: '#D63384' })[kind];
  const writeBody = (records, options) => (session, tag) => SIM.ops.writeRecords(session, tag, records, options);
  const writeSuccess = (r) => `Wrote ${UI.bytesLabel(r.bytesWritten)}.${r.capacity ? ` ${UI.bytesLabel(Math.max(0, r.capacity - r.bytesWritten))} free.` : ''}${r.locked ? ' The tag is now read only.' : ''}`;
  const writtenToTags = (n) => (n === 1 ? 'Written to 1 tag.' : `Written to ${n} tags.`);
  const timeLabel = (d) => new Date(d).toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
  const hex2 = (n) => '0x' + (n & 0xFF).toString(16).toUpperCase().padStart(2, '0');
  const hex4 = (n) => (n & 0xFFFF).toString(16).toUpperCase().padStart(4, '0');
  const check = (message) => UI.alert({ title: 'Check the input', message });
  // Optional passwords: an empty field means none, anything else must be the full length.
  const optionalBytes = (bytes) => (bytes.length ? new Uint8Array(bytes) : null);
  const badOptional = (bytes, n) => bytes.length !== 0 && bytes.length !== n;
  // A scan button with its explanation underneath, like a ScanButton in a Section with a footer.
  function scanButton(o, footer, footerClass) {
    const b = bigButton(o);
    if (footer) b.append(el('div', { class: 'section-footer' + (footerClass ? ' ' + footerClass : ''), text: footer }));
    return b;
  }
  const lockMark = () => UI.icon('lock', 'lock-mark');
  const colorValue = (node, color) => { const v = node && node.querySelector('.value'); if (v) v.style.color = color; return node; };
  // Originality signature verdicts, worded as in TagDetailView and SignatureToolView.
  const VERDICTS = {
    genuine: { title: 'Genuine NXP chip', text: "The signature matches NXP's public key for this serial number.", color: 'var(--green)', icon: 'seal' },
    notGenuine: { title: "Signature does not match NXP's key", text: "The signature does not match NXP's public key for this serial number. The chip is likely a clone.", color: 'var(--red)', icon: 'sealx' },
    noKey: { title: 'No public key for this chip', text: 'NXP has not published a public key for this chip, so the signature cannot be checked.', color: 'var(--secondary)', icon: 'question' },
  };
  // NTAG213 TT: byte 4 of READ_TT_STATUS is C for a closed loop, O for an open one and I when the chip cannot tell.
  function tamperInfo(hexText) {
    const b = NDEF.fromHex(hexText || '') || new Uint8Array();
    const unknown = { text: 'Unknown', color: 'var(--secondary)' };
    if (b.length < 5) return unknown;
    return ({ 0x43: { text: 'Wire intact', color: 'var(--green)' }, 0x4F: { text: 'Wire open, the tag was tampered with', color: 'var(--red)' }, 0x49: { text: 'Not determined', color: 'var(--orange)' } })[b[4]] || unknown;
  }

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
        if (STORE.scans.history.length) wrap.append(section({ rows: [buttonRow({ icon: 'table', title: 'Export scan log', onClick: () => UI.download('NFC scan log.csv', STORE.exportScanLogCSV(), 'text/csv') })], footer: 'A CSV file with the serial number, chip, record count and time of every scan in this session, for a spreadsheet.' }));
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
        const copySignature = () => UI.copy(hexSpaced(info.signature)).then(() => UI.alert({ title: 'Copied', message: 'The 32-byte signature is on the clipboard.' }));
        const signatureRow = () => {
          if (!info.signature) return null;
          const v = info.signatureVerdict && VERDICTS[info.signatureVerdict];
          if (!v) return r('Signature', info.signature.slice(0, 16) + '…', 'signature', { valueMono: true, onClick: copySignature });
          return colorValue(r('Signature', v.title, v.icon, { subtitle: hexSpaced(info.signature.slice(0, 8)) + '…', subtitleMono: true, onClick: copySignature }), v.color);
        };
        const tamperRow = () => { if (!info.tamperStatus) return null; const t = tamperInfo(info.tamperStatus); return colorValue(r('Tamper', t.text, 'shield', { subtitle: info.tamperStatus, subtitleMono: true }), t.color); };
        // The mirror setting comes first, like TagDetailView; scans saved before the dedicated tamper row may still carry a tamper extra.
        const extras = info.extras.filter((f) => f.label !== 'Tamper status');
        const orderedExtras = [...extras.filter((f) => f.label === 'Mirror'), ...extras.filter((f) => f.label !== 'Mirror')];
        const rows = [
          r('Tag type', SIM.info.typeLine(info), 'wave'),
          r('Chip', SIM.info.chipLine(info), 'cpu'),
          r('Technology', info.technology, 'info'),
          // A 7-byte or longer serial does not fit beside the title at phone width, so it goes under it.
          SIM.info.serialLine(info).length > 14
            ? row({ icon: 'key', iconBg: '#636366', title: 'Serial number', subtitle: SIM.info.serialLine(info), subtitleMono: true, onClick: () => UI.copy(SIM.info.serialLine(info)).then(() => UI.haptic('tap')), accessory: 'none' })
            : r('Serial number', SIM.info.serialLine(info), 'key', { valueMono: true, onClick: () => UI.copy(SIM.info.serialLine(info)).then(() => UI.haptic('tap')), accessory: 'none' }),
          r('ATQA', SIM.info.atqaLine(info), 'number', { valueMono: true }),
          r('SAK', SIM.info.sakLine(info), 'number', { valueMono: true }),
          r('Password protected', info.passwordProtected == null ? 'Unknown' : info.passwordProtected ? 'Yes' : 'No', 'lock'),
          r('Memory', SIM.info.memoryLine(info), 'memorychip'),
          r('Data format', info.chip.nfcForumType ? `NFC Forum Type ${info.chip.nfcForumType}` : 'Unknown', 'doc'),
          r('Size', SIM.info.sizeLine(info), 'grid'),
          r('Writable', SIM.info.writableLine(info), 'pencil'),
          info.counter != null ? r('Counter', String(info.counter) + (info.counterEnabled === false ? ' (disabled)' : ''), 'number') : (info.counterEnabled != null ? r('Counter', info.counterEnabled ? 'Enabled' : 'Disabled', 'number') : null),
          signatureRow(),
          tamperRow(),
          // Long hex values (GET_VERSION, for example) go under the title so they never run into it.
          ...orderedExtras.map((f) => { const mono = /^[0-9A-F ]+$/.test(f.value); return mono && f.value.length > 14 ? row({ icon: f.icon || 'info', iconBg: '#636366', title: f.label, subtitle: f.value, subtitleMono: true, subtitleWrap: true, accessory: 'none' }) : r(f.label, f.value, f.icon || 'info', { valueMono: mono }); }),
        ];
        // Chip notes sit under the list as its footer, like TagDetailView.
        wrap.append(section({ header: 'Tag', rows, footer: info.chip.notes || null }));
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
  function pageRow(p, onClick, note, locked) {
    const node = row({ onClick, accessory: 'none', custom: el('div', { class: 'page-row' + (p.readable ? '' : ' unreadable') }, el('span', { class: 'idx', text: '0x' + p.index.toString(16).toUpperCase().padStart(2, '0') }), el('span', { class: 'bytes', text: p.readable ? NDEF.hex(p.bytes, ' ') : 'protected' }), el('span', { class: 'ascii', text: p.readable ? NDEF.ascii(p.bytes) : '' }), note ? el('span', { class: 'tag', text: note }) : null, locked ? lockMark() : null) });
    if (locked) node.setAttribute('aria-label', `Block ${p.index}, locked`);
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
    let editing = false, several = false;
    return {
      title: 'Write', largeTitle: true,
      right: (ctx) => [navButton({ icon: 'ellipsis', label: 'More', onClick: () => more(ctx) }), navButton({ title: editing ? 'Done' : 'Edit', bold: editing, onClick: () => { editing = !editing; ctx.refresh(); } })],
      onReturn: (ctx) => ctx.refresh(),
      build(ctx) {
        const q = STORE.queue;
        const wrap = el('div');
        const rows = q.drafts.map((d, i) => draftRow(d, i, ctx));
        rows.push(row({ icon: 'plus', iconBg: 'var(--green)', title: 'Add a record', blue: true, accessory: 'none', onClick: () => UI.sheetAddRecord((kind) => openEditor(ctx, NDEF.draft(kind, kind === 'text' || kind === 'smartPoster' ? { language: STORE.settings.defaultLanguage } : {}))) }));
        const n = q.drafts.length;
        wrap.append(section({ header: 'Records', rows, footer: n ? `${n === 1 ? '1 record' : n + ' records'}, ${UI.bytesLabel(STORE.queueBytes())}. An NTAG213 holds 140 bytes, an NTAG215 496, an NTAG216 868.` : 'Add a record, then hold a tag to the phone to write it.' }));
        const o = q.options;
        const summary = [o.verifyAfterWrite ? 'Verify after write' : null, o.eraseFirst ? 'Erase first' : null, o.lockAfterWrite ? 'Lock after write' : null].filter(Boolean).join(', ') || 'None';
        wrap.append(section({ header: 'Options', rows: [
          row({ icon: 'gear', iconBg: '#636366', title: 'Write options', subtitle: summary, onClick: () => ctx.nav.push(writeOptionsScreen()) }),
          toggleRow({ icon: 'layers', iconBg: 'var(--blue)', title: 'Write to several tags', value: several, onChange: (v) => { several = v; ctx.refresh(); } }),
        ], footer: several ? 'The NFC sheet stays open, so hold the tags one after another and tap Cancel when you are done. iOS closes the sheet after 60 seconds.' : null }));
        const lockNote = o.lockAfterWrite ? (several ? 'Every tag will be locked permanently.' : 'The tag will be locked permanently.') : null;
        wrap.append(scanButton({ title: several ? 'Write to tags' : 'Write to tag', icon: 'wave', disabled: !n, onClick: () => write(ctx) }, lockNote, 'danger'));
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
      if (several) {
        // One sheet for many tags: the body returns the running count the sheet shows while it waits for the next tag.
        try {
          const count = await UI.nfc.runBatch({ alertMessage: 'Hold your iPhone near the first tag.', body: async (s, t, handled) => { await SIM.ops.writeRecords(s, t, records, options); return `${writtenToTags(handled + 1)} Hold the next one.`; } });
          if (options.lockAfterWrite) { STORE.queue.options.lockAfterWrite = false; STORE.saveQueue(); ctx.refresh(); }
          UI.success(writtenToTags(count));
        } catch (e) { fail(e); }
        return;
      }
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
        wrap.append(section({ rows: [toggleRow({ title: 'Lock tag after write', value: o.lockAfterWrite, onChange: (v) => { o.lockAfterWrite = v; STORE.saveQueue(); } })], footer: 'A locked tag can never be written again, by any app. The switch turns itself off after every write.', footerClass: 'danger' }));
        return wrap;
      },
    };
  }
  UI.sheetAddRecord = (onPick) => {
    UI.sheet({ title: 'Add a record', build(ctx) {
      const wrap = el('div');
      // Same three groups as AddRecordView, in WRITABLE order; any kind not named lands under Advanced.
      // Picking a kind closes this sheet and opens the editor, so the rows are buttons without a chevron.
      const common = ['text', 'url', 'email', 'contact', 'phone', 'sms', 'geo', 'address'], connect = ['wifi', 'bluetooth', 'social', 'app'];
      const groups = [['Common', (id) => common.includes(id)], ['Connect', (id) => connect.includes(id)], ['Advanced', (id) => !common.includes(id) && !connect.includes(id)]];
      for (const [header, test] of groups) {
        wrap.append(section({ header, rows: NDEF.WRITABLE.filter(test).map((id) => { const k = NDEF.kindInfo(id); return row({ icon: k.icon, title: k.name, subtitle: k.blurb, subtitleWrap: true, accessory: 'none', onClick: () => { ctx.close(); setTimeout(() => onPick(id), 320); } }); }) }));
      }
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
            case 'bluetooth': return [f('mac', 'Address', { placeholder: 'AA:BB:CC:DD:EE:FF', mono: true, autocap: 'characters' }), f('name', 'Name', { placeholder: 'Optional', autocap: 'words' }), tog('handover', 'Wrap in Handover Select (Android pairing)', 'Android offers to pair only when the pairing record comes inside a Handover Select record. iPhones ignore both.')];
            case 'social': return [sel('platform', 'Platform', NDEF.SOCIAL.map((s) => ({ value: s[0], label: s[1] }))), f('handle', 'Username', { placeholder: 'without the @' })];
            case 'app': return [f('package', 'Package', { placeholder: 'com.example.app' })];
            case 'customMIME': return [f('mime', 'MIME type', { placeholder: 'text/plain' }), ...payloadRows()];
            case 'external': return [f('domain', 'Domain', { placeholder: 'example.com' }), f('externalType', 'Type', { placeholder: 'thing' }), ...payloadRows()];
            case 'raw': case 'unknown': return [sel('tnf', 'Type name format', NDEF.TNF_LABEL.map((l, i) => ({ value: String(i), label: l }))), f('type', 'Type (hex)', { placeholder: '54', mono: true, autocap: 'characters' }), f('identifier', 'Identifier (hex)', { placeholder: 'Optional', mono: true, autocap: 'characters' }), f('payloadHex', null, { placeholder: 'Payload in hex', mono: true, autocap: 'characters', multiline: true })];
            case 'smartPoster': return [f('url', 'URL', { placeholder: 'https://example.com', type: 'url', inputmode: 'url' }), f('title', 'Title', { placeholder: 'Shown before the link opens', autocap: 'sentences' }), f('language', 'Language', { placeholder: 'en', maxLength: 5 })];
            case 'empty': return [row({ title: 'Nothing to edit. An empty record takes 3 bytes.', accessory: 'none' })];
            default: return [row({ title: 'Nothing to edit.', accessory: 'none' })];
          }
        };
        footer = el('div', { class: 'section-footer' });
        const note = { smartPoster: 'Some readers show the title before they open the URL; iPhones open the URL. https:// is added when you leave it out.' }[d.kind];
        const render = () => { wrap.replaceChildren(...[section({ rows: makeRows(), footer }), note ? textBlock(note) : null].filter(Boolean)); validateNow(); };
        render();
        return wrap;
      },
    });
  };

  // Tools tab
  // Grouped by the chips each tool talks to, like ToolsView.
  const TOOL_GROUPS = [
    { header: 'Any tag', tools: [
      ['erase', 'Erase tag', 'Remove every record from a tag.', 'eraser', () => eraseTool()],
      ['copy', 'Copy tag', 'Read one tag and write it to another.', 'docs', () => copyTool()],
      ['lock', 'Lock tag', 'Make a tag read only for good.', 'lock', () => lockTool()],
      ['memory', 'Memory editor', 'Read and edit memory page by page.', 'memorychip', () => memoryEditorTool()],
      ['format', 'Format memory', 'Prepare a blank or damaged tag for NDEF.', 'format', () => formatTool()],
      ['dump', 'Write dump', 'Write a saved memory dump to a tag.', 'docdown', () => writeDumpTool()],
      ['advanced', 'Advanced commands', 'Send raw commands to the chip.', 'terminal', () => advancedTool()],
    ] },
    { header: 'NTAG and Ultralight', footer: 'These tools talk to NXP NTAG and MIFARE Ultralight chips. Each screen says which models it needs.', tools: [
      ['password', 'Password', 'Protect a tag with a password, or remove one.', 'key', () => passwordTool()],
      ['counter', 'Counter', 'Read the tag counter or switch it on and off.', 'number', () => counterTool()],
      ['mirror', 'Mirror', 'Put the serial number or scan count into a link.', 'linkplus', () => mirrorTool()],
      ['lockpages', 'Lock pages', 'See which pages are locked and lock chosen ones.', 'lockstack', () => lockPagesTool()],
      ['signature', 'Signature', 'Check that the chip is a genuine NXP chip.', 'seal', () => signatureTool()],
      ['ulc', 'Ultralight C key', 'Test, set or remove the 3DES key.', 'key', () => ultralightCTool()],
    ] },
    { header: 'DESFire', tools: [['desfire', 'DESFire card', 'List applications, format, or set up NDEF.', 'creditcard', () => desfireTool()]] },
    { header: 'ISO 15693', tools: [['type5', 'Type 5 settings', 'AFI, DSFID, block locks, SLIX and ST25TV passwords.', 'sliders', () => type5Tool()]] },
    { header: 'FeliCa', footer: 'Every tool starts with a scan. Nothing is written until you tap the blue button and hold a tag to the phone.', tools: [['felica', 'FeliCa', 'Read and write blocks of a service.', 'grid', () => feliCaTool()]] },
  ];
  function toolsScreen() {
    return {
      title: 'Tools', largeTitle: true,
      right: () => [settingsButton()],
      build(ctx) {
        const wrap = el('div');
        for (const g of TOOL_GROUPS) wrap.append(section({ header: g.header, rows: g.tools.map(([id, title, subtitle, icon, make]) => row({ icon, iconBg: iconColorFor(id), title, subtitle, subtitleWrap: true, onClick: () => ctx.nav.push(make()) })), footer: g.footer }));
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
  const LOCK_METHODS = {
    bits: { label: 'Lock bits', icon: 'lock', explain: 'Sets the lock bits of the chip. No app and no phone can change the tag again, not even with raw commands.', warn: 'Locking is permanent. The records stay readable, but the tag can never be written, erased or formatted again, by this app or any other.', button: 'Lock tag', confirm: 'Lock this tag permanently?', message: 'The tag you scan next becomes read only forever.', confirmTitle: 'Lock', sheet: 'Tag locked.', done: 'The tag is now read only.' },
    flag: { label: 'NDEF flag only', icon: 'doc', explain: 'Marks a Type 2 or Type 5 tag read only in its capability container, so phones refuse to write records. Raw page writes, the memory editor and passwords still work.', warn: 'The read only flag is permanent too. It cannot be cleared, so phones will never write records to this tag again.', button: 'Set read only flag', confirm: 'Mark this tag read only permanently?', message: 'Phones will treat the tag you scan next as read only forever.', confirmTitle: 'Mark read only', sheet: 'Read only flag set.', done: 'The tag is now marked read only. Phones will no longer write records to it.' },
  };
  function lockTool() {
    let understood = false, method = 'bits';
    return {
      title: 'Lock tag',
      build(ctx) {
        const m = LOCK_METHODS[method];
        const wrap = el('div');
        wrap.append(segmented({ options: Object.entries(LOCK_METHODS).map(([value, x]) => ({ value, label: x.label })), value: method, onChange: (v) => { method = v; ctx.refresh(); } }));
        wrap.append(section({ header: 'Method', rows: [row({ icon: m.icon, iconBg: 'var(--orange)', title: m.label, subtitle: m.explain, subtitleWrap: true, accessory: 'none' })] }));
        wrap.append(section({ rows: [toggleRow({ title: 'I understand this cannot be undone', value: understood, onChange: (v) => { understood = v; ctx.refresh(); } })], footer: m.warn, footerClass: 'danger' }));
        wrap.append(bigButton({ title: m.button, icon: 'lock', destructive: true, disabled: !understood, onClick: async () => {
          const chosen = method, x = LOCK_METHODS[chosen];
          if (!await UI.confirm({ title: x.confirm, message: x.message, confirmTitle: x.confirmTitle, destructive: true })) return;
          try { await UI.nfc.run({ alertMessage: HOLD, successMessage: x.sheet, body: (s, t) => (chosen === 'bits' ? SIM.ops.lock(s, t) : SIM.ops.setNDEFReadOnlyFlag(s, t)) }); UI.success(x.done); } catch (e) { fail(e); }
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
        ], footer: 'Reads every page of the chip; tap a page to change it. Pages 0 to 3 hold the serial number, lock bits and capability container, and the last pages hold the configuration.' }));
        wrap.append(bigButton({ title: dump ? 'Read again' : 'Read memory', icon: 'wave', onClick: async () => {
          if (password.length && password.length !== 4) return UI.alert({ title: 'Check the input', message: 'The password must be 4 bytes. Leave it empty if the tag has none.' });
          try {
            dump = await UI.nfc.run({ alertMessage: HOLD, successMessage: 'Memory read.', body: async (s, t) => {
              const d = await SIM.ops.readMemory(s, t, password.length ? password : null);
              // ISO 15693 tags report which blocks are locked (block security status), so the editor can mark them.
              if (t.kind === 'type5') { s.alertMessage = 'Reading which blocks are locked.'; try { d.locked = (await SIM.ops.type5Settings(s, t)).lockedBlocks; } catch (e) { d.locked = null; } }
              return d;
            } });
            ctx.refresh();
          } catch (e) { fail(e); }
        } }));
        const chip = (dump && dump.chip) || {};
        const type5 = chip.nfcForumType === 5;
        const isLocked = (p) => !!(type5 && dump.locked && dump.locked[p.index]);
        if (dump) {
          const note = (p) => { if (type5) return p.index === 0 ? 'CC' : ''; if (!chip.supportsRawPages) return ''; if (p.index <= 1) return 'UID'; if (p.index === 2) return 'lock'; if (p.index === 3) return 'CC'; if (chip.configPage != null && p.index >= chip.configPage) return ['CFG0', 'CFG1', 'PWD', 'PACK'][p.index - chip.configPage] || 'cfg'; if (chip.dynamicLockPage != null && p.index === chip.dynamicLockPage) return 'lock'; return ''; };
          const rows = dump.pages.map((p) => pageRow(p, chip.supportsRawPages === false ? null : () => editPage(p), note(p), isLocked(p)));
          let footer = chip.supportsRawPages === false ? 'This chip does not allow single pages to be written. The pages show the NDEF file as read from the tag.' : 'Pages marked in red could not be read.';
          if (type5) footer = dump.locked ? 'Tap a block to edit or lock it. A lock marks blocks that can no longer be written.' : 'Tap a block to edit it. This tag did not report which blocks are locked.';
          if (type5 && dump.locked) { const n = dump.locked.filter(Boolean).length; wrap.append(section({ rows: [row({ icon: 'lock', iconBg: 'var(--orange)', title: 'Locked blocks', value: n ? String(n) : 'None', accessory: 'none' })] })); }
          wrap.append(section({ header: `${dump.pages.length} ${type5 ? 'blocks' : 'pages'} of ${dump.pageSize} bytes`, rows, footer }));
        }
        return wrap;
        function editPage(p) {
          let bytes = p.readable ? new Uint8Array(p.bytes) : new Uint8Array(dump.pageSize);
          const locked = isLocked(p);
          const risky = type5 ? p.index === 0 : (p.index <= 3 || (chip.configPage != null && p.index >= chip.configPage) || (chip.dynamicLockPage != null && p.index === chip.dynamicLockPage));
          const unit = type5 ? 'Block' : 'Page';
          // The same hex label as the list and the sheet title, so the alerts name the row that was tapped.
          const label = unit + ' 0x' + p.index.toString(16).toUpperCase().padStart(2, '0');
          UI.sheet({ title: label, build(sctx) {
            const w = el('div');
            const footer = locked ? 'Locked. This block can no longer be written.' : risky ? (type5 ? 'Block 0 holds the capability container. A wrong value makes the records unreadable.' : 'This page holds the serial number, lock bits, capability container or configuration. A wrong value can lock the tag for good.') : `The ${unit.toLowerCase()} is written exactly as typed.`;
            w.append(section({ rows: [hexField({ label: 'Bytes', value: bytes, byteCount: dump.pageSize, onChange: (b) => { bytes = b; } })], footer, footerClass: risky || locked ? 'danger' : null }));
            if (type5 && !locked) w.append(section({ rows: [buttonRow({ icon: 'lock', title: 'Lock block', destructive: true, onClick: async () => {
              if (!await UI.confirm({ title: `Lock ${label.toLowerCase()} for good?`, message: 'The block keeps its current bytes and can never be written again.', confirmTitle: 'Lock block', destructive: true })) return;
              try {
                dump.locked = await UI.nfc.run({ alertMessage: HOLD, successMessage: 'Block locked.', body: (s, t) => SIM.ops.type5LockBlocks(s, t, [p.index]) });
                sctx.close(); ctx.refresh(); UI.success(`${label} is now read only.`);
              } catch (e) { fail(e); }
            } })], footer: 'Locking makes the block read only forever. Write the bytes you want first.' }));
            w.append(bigButton({ title: type5 ? 'Write block' : 'Write page', icon: 'wave', destructive: risky, disabled: locked, onClick: async () => {
              if (bytes.length !== dump.pageSize) return UI.alert({ title: 'Check the input', message: `Enter exactly ${UI.bytesLabel(dump.pageSize)}.` });
              if (risky && !await UI.confirm({ title: 'Write a system page?', message: 'This can brick the tag.', confirmTitle: 'Write', destructive: true })) return;
              try { await UI.nfc.run({ alertMessage: HOLD, successMessage: `${unit} written.`, body: (s, t) => SIM.ops.writePage(s, t, p.index, bytes, password.length ? password : null) }); p.bytes = new Uint8Array(bytes); p.readable = true; sctx.close(); ctx.refresh(); UI.success(`${label} written.`); } catch (e) { fail(e); }
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
    let mode = 'set', password = new Uint8Array(), pack = new Uint8Array([0, 0]), protectReads = false, fromPage = 4, authLimit = 0, current = new Uint8Array(), showCurrent = false, remove = new Uint8Array(), cfgPassword = new Uint8Array();
    return {
      title: 'Password',
      build(ctx) {
        const wrap = el('div');
        wrap.append(segmented({ options: [{ value: 'set', label: 'Set' }, { value: 'remove', label: 'Remove' }, { value: 'config', label: 'Lock config' }], value: mode, onChange: (v) => { mode = v; ctx.refresh(); } }));
        if (mode === 'set') {
          wrap.append(section({ rows: [hexField({ label: 'Password', value: password, byteCount: 4, onChange: (b) => { password = b; } }), hexField({ label: 'PACK', value: pack, byteCount: 2, onChange: (b) => { pack = b; } })], footer: 'The PACK is 2 bytes the tag answers with when the password is right. 00 00 is fine.' }));
          wrap.append(section({ rows: [
            toggleRow({ title: 'Also protect reads', subtitle: 'Off: anyone can read, only the password can write.', value: protectReads, onChange: (v) => { protectReads = v; } }),
            stepperRow({ title: 'Protect from page', value: fromPage, min: 0, max: 255, onChange: (v) => { fromPage = v; } }),
            selectRow({ title: 'Wrong attempts allowed', value: String(authLimit), options: [{ value: '0', label: 'Unlimited' }, ...[1, 2, 3, 4, 5, 6, 7].map((n) => ({ value: String(n), label: String(n) }))], onChange: (v) => { authLimit = Number(v); } }),
          ], footer: 'Page 4 is the first page of user memory, so 4 protects everything you can write. With a limit, the tag rejects the password for good after that many wrong tries.' }));
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
        } else if (mode === 'config') {
          wrap.append(section({ rows: [row({ icon: 'lock', iconBg: 'var(--orange)', title: 'Lock configuration', subtitle: 'Sets CFGLCK, which freezes the protected pages, read protection, attempt limit, counter and mirror settings for good. The password and PACK can still be changed.', subtitleWrap: true, accessory: 'none' })], footer: 'Set the password, counter and mirror the way you want them first. Lock the configuration last, when nobody should be able to switch the protection off.' }));
          wrap.append(section({ rows: [hexField({ label: 'Current password', value: cfgPassword, byteCount: 4, onChange: (b) => { cfgPassword = b; } })], footer: 'Only needed when the configuration pages are password protected. Leave it empty otherwise.' }));
          wrap.append(scanButton({ title: 'Lock configuration', icon: 'lock', destructive: true, onClick: async () => {
            if (badOptional(cfgPassword, 4)) return check('The current password must be 4 bytes. Leave it empty if the tag has none.');
            if (!await UI.confirm({ title: 'Lock the configuration for good?', message: 'The protected pages, the protection mode, the attempt limit and the counter and mirror settings of the tag you scan next can never be changed again.', confirmTitle: 'Continue', destructive: true })) return;
            if (!await UI.confirm({ title: 'Are you sure?', message: 'This is the last check. Locking the configuration cannot be undone by any app.', confirmTitle: 'Lock configuration', destructive: true })) return;
            const pwd = optionalBytes(cfgPassword);
            try { await UI.nfc.run({ alertMessage: HOLD, successMessage: 'Configuration locked.', body: (s, t) => SIM.ops.lockConfiguration(s, t, pwd) }); UI.success('The configuration of this tag is now locked for good.'); } catch (e) { fail(e); }
          } }, 'You are asked twice before the scan starts.', 'danger'));
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
    let sourceId = 'paste', pasted = '', fileDump = null, fileName = '', from = 4, to = 225, includeSystem = false, serial = false, password = new Uint8Array();
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
        const pagesFooter = serial ? 'Pages 0 and 1 are written too, so the tag takes the serial number from the dump. Only magic clone chips accept this; a real NXP chip refuses pages 0 and 1 and the write stops there. Page 2 carries the second check byte of the serial number, so keep it in the range. Lock bits and configuration pages are written as well and can lock the tag for good.'
          : includeSystem ? 'The lock bytes, capability container and configuration pages will be written as they are in the dump. Wrong values cannot be undone. The serial number pages are skipped because the tag does not accept writes to them.'
            : 'Only user memory inside the range is written. The serial number, lock bytes, capability container and configuration pages are skipped.';
        wrap.append(section({ header: 'Pages', rows: [
          stepperRow({ title: 'From page', value: from, min: 0, max: 255, onChange: (v) => { from = v; } }),
          stepperRow({ title: 'To page', value: to, min: 0, max: 255, onChange: (v) => { to = v; } }),
          toggleRow({ title: 'Include pages 0 to 3 and config pages', value: includeSystem || serial, disabled: serial, onChange: (v) => { includeSystem = v; ctx.refresh(); } }),
          toggleRow({ title: 'Also write serial number pages (magic chips only)', value: serial, onChange: (v) => { serial = v; ctx.refresh(); } }),
        ], footer: pagesFooter, footerClass: includeSystem || serial ? 'danger' : null }));
        wrap.append(section({ rows: [hexField({ label: 'Password (optional)', value: password, byteCount: 4, onChange: (b) => { password = b; } })] }));
        wrap.append(bigButton({ title: 'Write dump', icon: 'docdown', onClick: async () => {
          const dump = currentDump();
          if (sourceId === 'paste' && pasted.trim() && !dump) return UI.alert({ title: 'Check the input', message: 'The pasted text is not valid hex. Use an even number of hex digits.' });
          if (!dump || !dump.pages.length) return UI.alert({ title: 'Check the input', message: 'Choose a source with at least one page.' });
          if (from > to) return UI.alert({ title: 'Check the input', message: 'The start page must not be after the end page.' });
          if (password.length && password.length !== 4) return UI.alert({ title: 'Check the input', message: 'The password must be 4 bytes. Leave it empty if the tag has none.' });
          const withSerial = serial, system = includeSystem || serial;
          const message = withSerial ? `Pages 0, 1 and ${Math.max(from, 2)} to ${to} of the next tag you scan are overwritten, serial number included.` : `Pages ${from} to ${to} of the next tag you scan are overwritten.`;
          if (!await UI.confirm({ title: 'Write the dump?', message, confirmTitle: 'Write', destructive: true })) return;
          try {
            const written = await UI.nfc.run({ alertMessage: HOLD, successMessage: 'Written.', body: (s, t) => {
              const chip = t.spec;
              let range = [from, to], source = dump;
              if (!system && chip.userRange) range = [Math.max(from, chip.userRange[0]), Math.min(to, chip.userRange[1])];
              else range = [Math.max(from, 2), to];
              // The range starts at page 2; pages 0 and 1 join it on their own when serial number pages are on.
              if (withSerial) { source = Object.assign({}, dump, { pages: dump.pages.filter((p) => p.index <= 1 || (p.index >= range[0] && p.index <= range[1])) }); range = [0, range[1]]; }
              return SIM.ops.writeDump(s, t, source, range, password.length ? password : null, withSerial);
            } });
            UI.success(`Wrote ${written} pages.`);
          } catch (e) { fail(e); }
        } }));
        return wrap;
      },
    };
  }
  function counterTool() {
    let values = null, enable = true, needsPassword = false, password = new Uint8Array();
    return {
      title: 'Counter',
      build(ctx) {
        const wrap = el('div');
        wrap.append(section({ rows: values ? values.map((v, i) => row({ title: values.length > 1 ? `Counter ${i}` : 'Scans', value: String(v), accessory: 'none' })) : [row({ title: 'Not read yet', subtitle: 'NTAG 213, 215 and 216 count every scan once the counter is on. Ultralight EV1 has three counters.', subtitleWrap: true, accessory: 'none' })] }));
        wrap.append(bigButton({ title: 'Read counter', icon: 'number', onClick: async () => {
          try { values = await UI.nfc.run({ alertMessage: HOLD, successMessage: 'Counter read.', body: async (s, t) => { if (t.spec.counterCount === 3) { const out = []; for (let a = 0; a < 3; a++) out.push(await SIM.ops.readCounter(s, t, a)); return out; } return [await SIM.ops.readCounter(s, t, 2)]; } }); ctx.refresh(); } catch (e) { fail(e); }
        } }));
        wrap.append(section({ rows: [
          toggleRow({ title: 'Counter enabled', subtitle: 'Applies to the next NTAG you scan.', value: enable, onChange: (v) => { enable = v; ctx.refresh(); } }),
          toggleRow({ title: 'Counter needs the password', value: needsPassword, onChange: (v) => { needsPassword = v; } }),
          hexField({ label: 'Password (optional)', value: password, byteCount: 4, onChange: (b) => { password = b; } }),
        ], footer: "Only NTAG 213, 215 and 216 can switch their counter on or off. With Counter needs the password on, the tag tells its count only to a reader that gave the password." }));
        wrap.append(bigButton({ title: enable ? 'Enable counter' : 'Disable counter', icon: 'wave', onClick: async () => {
          if (badOptional(password, 4)) return check('The password must be 4 bytes. Leave it empty if the tag has none.');
          const on = enable, protect = needsPassword, pwd = optionalBytes(password);
          const done = on ? `The counter is now enabled. ${protect ? 'Reading it needs the password.' : 'Any reader can read it.'}` : 'The counter is now disabled.';
          try { await UI.nfc.run({ alertMessage: HOLD, successMessage: on ? 'Counter enabled.' : 'Counter disabled.', body: (s, t) => SIM.ops.setCounter(s, t, on, protect, pwd) }); UI.success(done); } catch (e) { fail(e); }
        } }));
        return wrap;
      },
    };
  }
  function signatureTool() {
    let result = null;
    return {
      title: 'Signature',
      build(ctx) {
        const wrap = el('div');
        if (!result) wrap.append(section({ rows: [row({ title: 'Not read yet', subtitle: "NXP signs every NTAG 213, 215, 216 and MIFARE Ultralight EV1 chip with a 32-byte originality signature tied to its serial number. The app checks it against NXP's public key to tell a genuine NXP chip from a clone.", subtitleWrap: true, accessory: 'none' })] }));
        else {
          const v = VERDICTS[result.verdict];
          wrap.append(section({ header: 'Result', rows: [
            row({ iconPlain: v.icon, iconColor: v.color, title: v.title, subtitle: v.text, subtitleWrap: true, accessory: 'none' }),
            result.signature ? el('div', { class: 'cell plain' }, el('div', { class: 'result-row', text: hexSpaced(result.signature) })) : null,
            result.signature ? buttonRow({ icon: 'copy', title: 'Copy', onClick: async () => { await UI.copy(hexSpaced(result.signature)); UI.alert({ title: 'Copied', message: '32 bytes as hex.' }); } }) : null,
          ], footer: `Read at ${timeLabel(result.readAt)}. The iPhone checks the signature against the serial number without a network; the web preview simulates it.` }));
        }
        wrap.append(bigButton({ title: 'Read signature', icon: 'signature', onClick: async () => {
          try {
            result = await UI.nfc.run({ alertMessage: HOLD, successMessage: 'Signature checked.', body: async (s, t) => {
              const verdict = await SIM.ops.verifySignature(s, t);
              return { verdict, signature: verdict === 'noKey' ? null : await SIM.ops.readSignature(s, t), readAt: new Date() };
            } });
            ctx.refresh();
          } catch (e) { fail(e); }
        } }));
        return wrap;
      },
    };
  }

  // Mirror: an NTAG21x writes its serial number or read counter into a link while it is read.
  const MIRROR_KINDS = {
    uid: { label: 'UID', about: 'The tag writes its 7-byte serial number as 14 hex digits.', example: '04A2246A4F6B80', valueName: 'serial number' },
    counter: { label: 'Counter', about: 'The tag writes its read counter as 6 hex digits. The counter is switched on for you and goes up by one for each read.', example: '00002A', valueName: 'read counter' },
    both: { label: 'Both', about: 'The tag writes its serial number, the letter x, then its read counter. The counter is switched on for you.', example: '04A2246A4F6B80x00002A', valueName: 'serial number and read counter' },
  };
  const MIRROR_SETTING_NAMES = { none: 'Off', uid: 'Serial number', counter: 'Read counter', both: 'Serial number and counter' };
  function mirrorTool() {
    let url = 'https://example.com/tag?id={mirror}', kind = 'uid', password = new Uint8Array(), setting = null, lastWritten = null;
    const problem = () => {
      const u = url.trim();
      if (!u) return 'Enter a link.';
      if (u.split('{mirror}').length > 2) return 'Use {mirror} only once.';
      if (!/^[a-z][a-z0-9+.-]*:\S+$/i.test(u)) return 'Enter a full link, for example https://example.com/tag?id={mirror}.';
      return null;
    };
    const passwordProblem = () => (badOptional(password, 4) ? 'The password must be 4 bytes. Leave it empty if the tag has none.' : null);
    return {
      title: 'Mirror',
      build(ctx) {
        const wrap = el('div');
        const k = MIRROR_KINDS[kind];
        const stored = el('div', { class: 'result-row' }), seen = el('div', { class: 'result-row' });
        // The link as stored (with placeholder zeros) and as a phone reads it, kept current while typing.
        const preview = () => {
          const m = SIM.ops.mirroredURL(url.trim() || 'https://example.com/tag?id={mirror}', kind);
          stored.textContent = m.fullURL;
          seen.textContent = m.fullURL.slice(0, m.placeholderIndex) + k.example + m.fullURL.slice(m.placeholderIndex + k.example.length);
        };
        wrap.append(section({ header: 'Link', rows: [fieldRow({ value: url, placeholder: 'https://example.com/tag?id={mirror}', type: 'url', inputmode: 'url', onInput: (v) => { url = v; preview(); } })], footer: 'Type {mirror} where the value should go. Without it, the value goes at the end of the link.' }));
        wrap.append(section({ header: 'Mirror', rows: [selectRow({ title: 'Mirror', value: kind, options: Object.entries(MIRROR_KINDS).map(([value, x]) => ({ value, label: x.label })), onChange: (v) => { kind = v; ctx.refresh(); } })], footer: k.about }));
        wrap.append(section({ header: 'Result', rows: [row({ title: 'Written to the tag', custom: stored, accessory: 'none' }), row({ title: 'What a phone sees, for example', custom: seen, accessory: 'none' })], footer: 'The zeros are placeholders. The chip swaps them for live values while it is read, so the stored link never changes.' }));
        preview();
        wrap.append(section({ header: 'Password', rows: [hexField({ label: 'Password', value: password, byteCount: 4, onChange: (b) => { password = b; } })], footer: 'Only needed when the tag is password protected.' }));
        wrap.append(scanButton({ title: 'Write mirrored URL', icon: 'wave', onClick: async () => {
          const err = problem() || passwordProblem(); if (err) return check(err);
          const u = url.trim(), kd = kind, pwd = optionalBytes(password);
          try {
            lastWritten = await UI.nfc.run({ alertMessage: HOLD, successMessage: 'Mirrored link written.', body: (s, t) => SIM.ops.writeMirroredURL(s, t, u, kd, pwd) });
            ctx.refresh();
            UI.success(`The tag now holds the link. Each read shows the ${MIRROR_KINDS[kd].valueName} in place of the zeros.`);
          } catch (e) { fail(e); }
        } }, 'Works on NTAG 213, 215 and 216, including the F and TT models. The link replaces every record on the tag.'));
        if (lastWritten) wrap.append(section({ header: 'Last written', rows: [el('div', { class: 'cell plain' }, el('div', { class: 'result-row', text: lastWritten }))] }));
        if (setting) {
          wrap.append(section({ header: 'Mirror setting', rows: [
            row({ title: 'Mirror', value: MIRROR_SETTING_NAMES[setting.kind] || 'Off', accessory: 'none' }),
            setting.kind !== 'none' ? row({ title: 'Starts at', value: `Page ${setting.page}, byte ${setting.byte}`, accessory: 'none' }) : null,
          ], footer: `Read at ${timeLabel(setting.readAt)}.` }));
        }
        wrap.append(section({ rows: [buttonRow({ icon: 'search', title: 'Read mirror setting', onClick: async () => {
          try { setting = await UI.nfc.run({ alertMessage: HOLD, successMessage: 'Mirror setting read.', body: async (s, t) => Object.assign(await SIM.ops.readMirror(s, t), { readAt: new Date() }) }); ctx.refresh(); } catch (e) { fail(e); }
        } })], footer: 'Shows what the tag mirrors and where in its memory the value starts.' }));
        wrap.append(section({ rows: [buttonRow({ icon: 'link', title: 'Turn mirror off', onClick: async () => {
          const err = passwordProblem(); if (err) return check(err);
          const pwd = optionalBytes(password);
          try { await UI.nfc.run({ alertMessage: HOLD, successMessage: 'Mirror turned off.', body: (s, t) => SIM.ops.disableMirror(s, t, pwd) }); if (setting) { setting = null; ctx.refresh(); } UI.success('The mirror is off. The tag now returns the link exactly as stored.'); } catch (e) { fail(e); }
        } })], footer: 'The link stays on the tag with its placeholder zeros. Only the live values stop.' }));
        return wrap;
      },
    };
  }

  // Lock pages: static and dynamic lock bits, one group per bit.
  function lockPagesTool() {
    let state = null, selected = new Set(), password = new Uint8Array();
    const label = (g) => (g.from === 3 && g.to === 3 ? 'Page 3, capability container' : g.from === g.to ? `Page ${g.from}` : `Pages ${g.from} to ${g.to}`);
    const chosen = () => state.groups.filter((g) => selected.has(g.from));
    return {
      title: 'Lock pages',
      build(ctx) {
        const wrap = el('div');
        wrap.append(scanButton({ title: state ? 'Read again' : 'Read lock state', icon: 'search', onClick: async () => {
          try {
            state = await UI.nfc.run({ alertMessage: HOLD, successMessage: 'Lock state read.', body: async (s, t) => ({ groups: await SIM.ops.lockState(s, t), chip: SIM.info.chipLine({ chip: t.spec }), uid: NDEF.hex(t.uid), readAt: new Date() }) });
            selected = new Set(); ctx.refresh();
          } catch (e) { fail(e); }
        } }, 'Reads the lock bits of an NTAG or MIFARE Ultralight tag. Each lock bit covers one page or a group of pages, and once set it can never be cleared.'));
        if (!state) return wrap;
        const lockedCount = state.groups.filter((g) => g.locked).length;
        wrap.append(section({ header: 'Tag', rows: [
          row({ title: 'Chip', value: state.chip, valueWrap: true, accessory: 'none' }),
          row({ title: 'Serial number', value: hexSpaced(state.uid).replace(/ /g, ':'), valueMono: true, valueWrap: true, accessory: 'none' }),
          row({ title: 'Locked groups', value: `${lockedCount} of ${state.groups.length}`, accessory: 'none' }),
        ], footer: `Read at ${timeLabel(state.readAt)}.` }));
        const rows = state.groups.map((g) => {
          if (g.locked) return row({ title: label(g), subtitle: 'Locked', right: lockMark(), accessory: 'none' });
          if (!g.lockable) return row({ title: label(g), subtitle: 'Cannot be locked', accessory: 'none', disabled: true });
          return toggleRow({ title: label(g), value: selected.has(g.from), onChange: (v) => { if (v) selected.add(g.from); else selected.delete(g.from); ctx.refresh(); } });
        });
        wrap.append(section({ header: 'Pages', rows, footer: 'Switch on the groups you want to lock. Page 3 holds the capability container; pages 4 and up hold your records.' }));
        const open = state.groups.filter((g) => !g.locked && g.lockable);
        wrap.append(section({ rows: [
          buttonRow({ title: 'Select every unlocked group', disabled: !open.length || open.every((g) => selected.has(g.from)), onClick: () => { open.forEach((g) => selected.add(g.from)); ctx.refresh(); } }),
          buttonRow({ title: 'Clear selection', disabled: !selected.size, onClick: () => { selected = new Set(); ctx.refresh(); } }),
        ] }));
        wrap.append(section({ header: 'Password', rows: [hexField({ label: 'Password', value: password, byteCount: 4, onChange: (b) => { password = b; } })], footer: 'Only needed when the lock pages are password protected.' }));
        wrap.append(scanButton({ title: 'Lock selected pages', icon: 'lock', destructive: true, disabled: !selected.size, onClick: async () => {
          const groups = chosen().map((g) => Object.assign({}, g, { locked: true }));
          if (!groups.length) return check('Choose at least one group of pages to lock.');
          if (badOptional(password, 4)) return check('The password must be 4 bytes. Leave it empty if the tag has none.');
          const pages = groups.reduce((n, g) => n + g.to - g.from + 1, 0);
          if (!await UI.confirm({ title: pages === 1 ? 'Lock 1 page for good?' : `Lock ${pages} pages for good?`, message: 'Locked pages can never be written again, and the lock bits can never be cleared.', confirmTitle: 'Lock', destructive: true })) return;
          const uid = state.uid, pwd = optionalBytes(password);
          try {
            const after = await UI.nfc.run({ alertMessage: 'Hold your iPhone near the same tag.', successMessage: 'Pages locked.', body: (s, t) => {
              if (NDEF.hex(t.uid) !== uid) throw SIM.E.input('This is a different tag. Read its lock state first.');
              return SIM.ops.lockPages(s, t, groups, pwd);
            } });
            state = Object.assign({}, state, { groups: after, readAt: new Date() }); selected = new Set(); ctx.refresh();
            UI.success(pages === 1 ? 'The page is locked. The list shows the new lock state.' : 'The pages are locked. The list shows the new lock state.');
          } catch (e) { fail(e); }
        } }, 'Locked pages can never be written again by any app, and lock bits can never be cleared. Hold the same tag you read.', 'danger'));
        return wrap;
      },
    };
  }

  // Ultralight C: 16-byte 3DES key, AUTH0 (first protected page) and AUTH1 (write only).
  function ultralightCTool() {
    const DEFAULT_KEY = NDEF.utf8('BREAKMEIFYOUCAN!');
    let current = new Uint8Array(DEFAULT_KEY), next = new Uint8Array(), firstPage = 4, writeOnly = true;
    const asText = (b) => (b.length === 16 ? NDEF.ascii(b) : 'Needs 16 bytes');
    const protectionFooter = () => {
      if (firstPage >= 48) return 'Page 48 is past the end of the memory, so no page needs the key.';
      const hex = firstPage.toString(16).toUpperCase().padStart(2, '0');
      return `${writeOnly ? 'Writing' : 'Reading and writing'} pages ${firstPage} (0x${hex}) and up needs the key; user memory starts at page 4. ${writeOnly ? 'Turn off “Only protect writes” to hide the records from phones without the key too.' : 'Phones cannot read the records without the key.'}`;
    };
    return {
      title: 'Ultralight C key',
      build(ctx) {
        const wrap = el('div');
        const currentText = row({ title: 'As text', value: asText(current), valueMono: true, accessory: 'none' });
        wrap.append(section({ header: 'Current key', rows: [
          hexField({ label: 'Key', value: current, byteCount: 16, onChange: (b) => { current = b; currentText.querySelector('.value').textContent = asText(b); } }),
          currentText,
          buttonRow({ icon: 'key', title: 'Use default key', onClick: () => { current = new Uint8Array(DEFAULT_KEY); ctx.refresh(); } }),
        ], footer: 'New tags use the factory key BREAKMEIFYOUCAN! until it is changed. A tag never gives its key back, so keep a copy of any key you set.' }));
        wrap.append(section({ rows: [buttonRow({ icon: 'checkcircle', title: 'Test key', onClick: async () => {
          if (current.length !== 16) return check('Enter the current 16-byte key.');
          const key = new Uint8Array(current);
          try { await UI.nfc.run({ alertMessage: HOLD, successMessage: 'Key accepted.', body: (s, t) => SIM.ops.ultralightCAuthenticate(s, t, key) }); UI.success('The tag accepted the key.'); } catch (e) { fail(e); }
        } })], footer: 'Runs the 3DES handshake with the current key. Nothing on the tag changes.' }));
        wrap.append(section({ header: 'New key', rows: [
          hexField({ label: 'Key', value: next, byteCount: 16, onChange: (b) => { next = b; } }),
          buttonRow({ icon: 'sparkle', title: 'Generate random key', onClick: () => { next = crypto.getRandomValues(new Uint8Array(16)); ctx.refresh(); } }),
        ], footer: 'Keep a copy of the new 16-byte key before you set it. Without it, the protected pages are out of reach for good.' }));
        const footer = el('div', { class: 'section-footer', text: protectionFooter() });
        wrap.append(section({ header: 'Protection', rows: [
          stepperRow({ title: 'Protect from page', value: firstPage, min: 3, max: 48, onChange: (v) => { firstPage = v; footer.textContent = protectionFooter(); } }),
          toggleRow({ title: 'Only protect writes', value: writeOnly, onChange: (v) => { writeOnly = v; footer.textContent = protectionFooter(); } }),
        ], footer }));
        wrap.append(scanButton({ title: 'Set key and protection', icon: 'key', onClick: async () => {
          if (current.length !== 16) return check('Enter the current 16-byte key.');
          if (next.length !== 16) return check('Enter a new 16-byte key.');
          const cur = new Uint8Array(current), key = new Uint8Array(next), page = firstPage, wo = writeOnly;
          if (!await UI.confirm({ title: 'Set a new key?', message: `The tag you scan next will need the new key to ${wo ? 'write' : 'read or write'} pages ${page} and up. The key can never be read back from the tag.`, confirmTitle: 'Set key' })) return;
          try {
            await UI.nfc.run({ alertMessage: HOLD, successMessage: 'Key set.', body: (s, t) => SIM.ops.ultralightCSetKey(s, t, cur, key, page, wo) });
            current = key; ctx.refresh();
            UI.success(`The new key is set and pages ${page} and up are protected. The current key field now holds the new key.`);
          } catch (e) { fail(e); }
        } }, 'Authenticates with the current key, writes the new key, then sets the first protected page.'));
        wrap.append(section({ rows: [buttonRow({ icon: 'lock', title: 'Remove protection', onClick: async () => {
          if (current.length !== 16) return check('Enter the current 16-byte key.');
          const key = new Uint8Array(current);
          try { await UI.nfc.run({ alertMessage: HOLD, successMessage: 'Protection removed.', body: (s, t) => SIM.ops.ultralightCRemoveProtection(s, t, key) }); UI.success('Every page can be read and written without the key again.'); } catch (e) { fail(e); }
        } })], footer: 'Authenticates with the current key and opens every page again. The key itself stays on the tag.' }));
        return wrap;
      },
    };
  }

  // DESFire: overview without a key, then format and NDEF application setup with the card master key.
  function desfireTool() {
    let reading = null, masterKey = new Uint8Array(8), size = 2048, formatFirst = false;
    const HOLD_CARD = 'Hold your iPhone near the card.';
    const keyType = (maxKeys) => ({ 0: 'DES or 2K3DES', 1: '3K3DES', 2: 'AES' })[(maxKeys >> 6) & 3] || 'Unknown';
    const yesNo = (bit) => (bit ? 'Yes' : 'No');
    const overview = async (s, t) => Object.assign(await SIM.ops.desfireOverview(s, t), { chip: t.spec.name, storage: t.spec.userMemoryBytes, readAt: new Date() });
    const keyProblem = () => (masterKey.length === 8 || masterKey.length === 16 ? null : 'The master key must be 8 or 16 bytes.');
    return {
      title: 'DESFire card',
      build(ctx) {
        const wrap = el('div');
        wrap.append(scanButton({ title: reading ? 'Read again' : 'Read card', icon: 'search', onClick: async () => {
          try { reading = await UI.nfc.run({ alertMessage: HOLD_CARD, successMessage: 'Card read.', body: overview }); ctx.refresh(); } catch (e) { fail(e); }
        } }, 'Reads the version, the applications, the free memory and the master key settings. Most cards allow this without a key.'));
        if (reading) {
          wrap.append(section({ header: 'Card', rows: [
            row({ title: 'Chip', value: reading.chip, valueWrap: true, accessory: 'none' }),
            row({ title: 'Storage', value: UI.bytesLabel(reading.storage), accessory: 'none' }),
            row({ title: 'Free memory', value: reading.freeMemory == null ? 'Not reported' : UI.bytesLabel(reading.freeMemory), accessory: 'none' }),
            row({ title: 'NDEF application', value: reading.hasNDEFApplication ? 'Yes' : 'No', accessory: 'none' }),
            row({ title: 'Version', subtitle: hexSpaced(reading.version), subtitleMono: true, subtitleWrap: true, accessory: 'none' }),
          ], footer: `Read at ${timeLabel(reading.readAt)}. DESFire D40 cards do not report their free memory.` }));
          const apps = reading.applications;
          wrap.append(section({ header: 'Applications', rows: apps.length ? apps.map((a) => row({ title: a, mono: true, value: a === '000001' && reading.hasNDEFApplication ? 'NDEF' : null, accessory: 'none' })) : [row({ title: 'No applications', accessory: 'none' })], footer: 'Application IDs are shown most significant byte first, the way datasheets write them. An empty list can also mean the card only lists its applications after authentication.' }));
          const ks = reading.keySettings;
          wrap.append(section({ header: 'Key settings', rows: [
            row({ title: 'Master key type', value: keyType(reading.maxKeys), accessory: 'none' }),
            row({ title: 'Master key can change', value: yesNo(ks & 0x01), accessory: 'none' }),
            row({ title: 'List without key', value: yesNo(ks & 0x02), accessory: 'none' }),
            row({ title: 'Create without key', value: yesNo(ks & 0x04), accessory: 'none' }),
            row({ title: 'Settings can change', value: yesNo(ks & 0x08), accessory: 'none' }),
          ], footer: 'These settings belong to the card master key, the key that guards formatting and creating applications.' }));
        }
        wrap.append(section({ header: 'Master key', rows: [
          hexField({ label: 'Card master key', value: masterKey, onChange: (b) => { masterKey = b; } }),
          buttonRow({ icon: 'key', title: 'Use default key', onClick: () => { masterKey = new Uint8Array(8); ctx.refresh(); } }),
        ], footer: '8 bytes for DES or 16 for 2K3DES; a new card uses 8 zero bytes. The key is only used to authenticate and is never changed.' }));
        let ndefFooter = 'Creates application 000001 with the NFC Forum name D2760000850101, a capability container file E103 and an NDEF file E104 of the chosen size, so phones see a normal NDEF tag.';
        if (formatFirst) ndefFooter += ' Format first deletes every application on the card before creating it.';
        else if (reading && reading.freeMemory != null) { ndefFooter += ` The card reported ${UI.bytesLabel(reading.freeMemory)} free.`; if (size + 32 > reading.freeMemory) ndefFooter += ' The NDEF file may not fit; choose a smaller size.'; }
        wrap.append(section({ header: 'NDEF application', rows: [
          stepperRow({ title: 'NDEF file', value: size, min: 256, max: 7936, step: 256, format: (v) => UI.bytesLabel(v), onChange: (v) => { if (v !== size) { size = v; ctx.refresh(); } } }),
          toggleRow({ title: 'Format first', value: formatFirst, onChange: (v) => { formatFirst = v; ctx.refresh(); } }),
        ], footer: ndefFooter }));
        wrap.append(scanButton({ title: 'Create NDEF application', icon: 'wave', onClick: async () => {
          const err = keyProblem(); if (err) return check(err);
          const ff = formatFirst, sz = size, key = new Uint8Array(masterKey);
          const message = ff ? `The card you scan next is formatted first, which deletes every application on it, then gets an NDEF application with a ${UI.bytesLabel(sz)} NDEF file.` : `The card you scan next gets an NDEF application with a ${UI.bytesLabel(sz)} NDEF file. Existing applications stay.`;
          if (!await UI.confirm({ title: 'Create the NDEF application?', message, confirmTitle: ff ? 'Format and create' : 'Create application', destructive: ff })) return;
          try {
            reading = await UI.nfc.run({ alertMessage: HOLD_CARD, successMessage: 'NDEF application created.', body: async (s, t) => { await SIM.ops.desfireCreateNDEFApplication(s, t, key, ff, sz); return overview(s, t); } });
            ctx.refresh();
            UI.success(`The card now has an NDEF application with a ${UI.bytesLabel(sz)} NDEF file. Write records to it in the Write tab.`);
          } catch (e) { fail(e); }
        } }, 'Afterwards the card works like any NDEF tag: write records to it in the Write tab.'));
        wrap.append(scanButton({ title: 'Format card', icon: 'trash', destructive: true, onClick: async () => {
          const err = keyProblem(); if (err) return check(err);
          if (!await UI.confirm({ title: 'Format this card?', message: 'Formatting deletes every application and file on the card, including any NDEF data.', confirmTitle: 'Continue', destructive: true })) return;
          if (!await UI.confirm({ title: 'Erase everything on the card?', message: 'This cannot be undone. The card you scan next is wiped back to an empty card.', confirmTitle: 'Format card', destructive: true })) return;
          const key = new Uint8Array(masterKey);
          try {
            reading = await UI.nfc.run({ alertMessage: HOLD_CARD, successMessage: 'Card formatted.', body: async (s, t) => { await SIM.ops.desfireFormat(s, t, key); return overview(s, t); } });
            ctx.refresh();
            UI.success('The card is empty. Create the NDEF application to use it as an NDEF tag again.');
          } catch (e) { fail(e); }
        } }, 'Formatting deletes every application and file on the card for good. It needs the card master key.', 'danger'));
        return wrap;
      },
    };
  }

  // Type 5 (ISO 15693): AFI, DSFID and block locks for every tag, then ICODE SLIX and ST25TV commands.
  const SLIX_PASSWORDS = [['read', 'Read'], ['write', 'Write'], ['privacy', 'Privacy'], ['destroy', 'Destroy'], ['easAFI', 'EAS and AFI']];
  const slixName = (id) => ({ read: 'read', write: 'write', privacy: 'privacy', destroy: 'destroy', easAFI: 'EAS and AFI' })[id];
  // Locked block flags as "0 to 3, 7, 10 to 12".
  function blockRanges(flags) {
    const out = [];
    for (let i = 0; i < flags.length; i++) {
      if (!flags[i]) continue;
      let j = i; while (j + 1 < flags.length && flags[j + 1]) j++;
      out.push(i === j ? String(i) : `${i} to ${j}`); i = j;
    }
    return out.join(', ');
  }
  function type5Tool() {
    let mode = 'settings', reading = null, afi = new Uint8Array(), lockAFI = false, dsfid = new Uint8Array(), lockDSFID = false, lockFrom = 0, lockTo = 0;
    let slixId = 'read', slixCurrent = new Uint8Array(), slixNew = new Uint8Array(), privacyPassword = new Uint8Array(), destroyPassword = new Uint8Array();
    let stNumber = 0, stCurrent = new Uint8Array(), stNew = new Uint8Array();
    const run = (successMessage, body) => UI.nfc.run({ alertMessage: HOLD, successMessage, body });
    const hexSp = (b) => NDEF.hex(b, ' ');
    const MODES = { settings: 'AFI, DSFID and block locks work on every ISO 15693 tag.', slix: 'For NXP ICODE SLIX, SLIX2 and DNA tags. Other chips refuse these commands.', st: 'For ST25TV tags from STMicroelectronics. Other chips refuse these commands.' };
    return {
      title: 'Type 5 settings',
      build(ctx) {
        const wrap = el('div');
        wrap.append(segmented({ options: [{ value: 'settings', label: 'Settings' }, { value: 'slix', label: 'ICODE SLIX' }, { value: 'st', label: 'ST25TV' }], value: mode, onChange: (v) => { mode = v; ctx.refresh(); } }));
        wrap.append(textBlock(MODES[mode]));
        if (mode === 'settings') buildSettings(ctx, wrap);
        else if (mode === 'slix') buildSLIX(ctx, wrap);
        else buildST(ctx, wrap);
        return wrap;
      },
    };
    function buildSettings(ctx, wrap) {
      wrap.append(scanButton({ title: reading ? 'Read again' : 'Read settings', icon: 'search', onClick: async () => {
        try {
          reading = await run('Settings read.', async (s, t) => Object.assign(await SIM.ops.type5Settings(s, t), { chip: SIM.info.chipLine({ chip: t.spec }), readAt: new Date() }));
          afi = new Uint8Array([reading.afi]); dsfid = new Uint8Array([reading.dsfid]);
          const last = reading.totalBlocks - 1; lockFrom = Math.min(lockFrom, last); lockTo = Math.min(lockTo, last);
          ctx.refresh();
        } catch (e) { fail(e); }
      } }, 'Reads the DSFID, the AFI, the memory size and which blocks are locked.'));
      if (reading) {
        const locked = reading.lockedBlocks.filter(Boolean).length;
        const family = reading.isSLIX ? ' Passwords, privacy and EAS for this ICODE SLIX are under ICODE SLIX above.' : reading.isST ? ' Passwords for this ST25TV are under ST25TV above.' : '';
        wrap.append(section({ header: 'Tag', rows: [
          row({ title: 'Chip', value: reading.chip, valueWrap: true, accessory: 'none' }),
          row({ title: 'DSFID', value: hex2(reading.dsfid), valueMono: true, accessory: 'none' }),
          row({ title: 'AFI', value: hex2(reading.afi), valueMono: true, accessory: 'none' }),
          row({ title: 'Memory', value: `${reading.totalBlocks} blocks of ${reading.blockSize} bytes`, accessory: 'none' }),
          row({ title: 'Locked blocks', value: locked ? String(locked) : 'None', subtitle: locked ? 'Locked: blocks ' + blockRanges(reading.lockedBlocks) : null, subtitleWrap: true, accessory: 'none' }),
        ], footer: `Read at ${timeLabel(reading.readAt)}.${family}` }));
      }
      const writeByte = async (name, bytes, lock, op) => {
        if (bytes.length !== 1) return check(`Enter the ${name} as one byte, for example 00.`);
        const v = bytes[0];
        if (lock && !await UI.confirm({ title: `Write and lock the ${name}?`, message: `The ${name} becomes ${hex2(v)} forever. It can never be changed again.`, confirmTitle: 'Write and lock', destructive: true })) return;
        try { await run(lock ? `${name} written and locked.` : `${name} written.`, (s, t) => op(s, t, v, lock)); UI.success(lock ? `The ${name} is now ${hex2(v)} and locked.` : `The ${name} is now ${hex2(v)}.`); } catch (e) { fail(e); }
      };
      wrap.append(section({ header: 'AFI', rows: [
        hexField({ label: 'AFI', value: afi, byteCount: 1, onChange: (b) => { afi = b; } }),
        toggleRow({ title: 'Lock the AFI', value: lockAFI, onChange: (v) => { lockAFI = v; } }),
        buttonRow({ icon: 'pencil', title: 'Write AFI', onClick: () => writeByte('AFI', afi, lockAFI, SIM.ops.type5WriteAFI) }),
      ], footer: 'The application family identifier tells readers what kind of item the tag is on; 00 means any. Locking makes the value permanent.' }));
      wrap.append(section({ header: 'DSFID', rows: [
        hexField({ label: 'DSFID', value: dsfid, byteCount: 1, onChange: (b) => { dsfid = b; } }),
        toggleRow({ title: 'Lock the DSFID', value: lockDSFID, onChange: (v) => { lockDSFID = v; } }),
        buttonRow({ icon: 'pencil', title: 'Write DSFID', onClick: () => writeByte('DSFID', dsfid, lockDSFID, SIM.ops.type5WriteDSFID) }),
      ], footer: 'The data storage format identifier says how the memory is organised, and most readers ignore it. Locking makes the value permanent.' }));
      const maxBlock = reading ? reading.totalBlocks - 1 : 255;
      const lockLabel = () => (lockFrom === lockTo ? `Lock block ${lockFrom}` : `Lock blocks ${lockFrom} to ${lockTo}`);
      const lockButton = buttonRow({ icon: 'lock', title: lockLabel(), destructive: true, onClick: async () => {
        if (lockFrom > lockTo) return check('The first block must not be after the last one.');
        const blocks = []; for (let b = lockFrom; b <= lockTo; b++) blocks.push(b);
        if (!await UI.confirm({ title: blocks.length === 1 ? `Lock block ${lockFrom} for good?` : `Lock blocks ${lockFrom} to ${lockTo} for good?`, message: 'These blocks become read only forever. This cannot be undone.', confirmTitle: 'Lock', destructive: true })) return;
        try {
          const flags = await run(blocks.length === 1 ? 'Block locked.' : 'Blocks locked.', (s, t) => SIM.ops.type5LockBlocks(s, t, blocks));
          if (reading && flags.length === reading.totalBlocks) { reading.lockedBlocks = flags; ctx.refresh(); }
          UI.success(blocks.length === 1 ? `Block ${blocks[0]} is now read only.` : `Blocks ${lockFrom} to ${lockTo} are now read only.`);
        } catch (e) { fail(e); }
      } });
      const relabel = () => { lockButton.querySelector('.title').textContent = lockLabel(); };
      wrap.append(section({ header: 'Lock blocks', rows: [
        stepperRow({ title: 'From block', value: lockFrom, min: 0, max: maxBlock, onChange: (v) => { lockFrom = v; relabel(); } }),
        stepperRow({ title: 'To block', value: lockTo, min: 0, max: maxBlock, onChange: (v) => { lockTo = v; relabel(); } }),
        lockButton,
      ], footer: "Locked blocks can never be written again, by any reader. Read the settings first so the steppers match the tag's size.", footerClass: 'danger' }));
    }
    function buildSLIX(ctx, wrap) {
      wrap.append(section({ header: 'Passwords', rows: [
        selectRow({ title: 'Password', value: slixId, options: SLIX_PASSWORDS.map(([value, label]) => ({ value, label })), onChange: (v) => { slixId = v; } }),
        hexField({ label: 'Current password', value: slixCurrent, byteCount: 4, onChange: (b) => { slixCurrent = b; } }),
        hexField({ label: 'New password', value: slixNew, byteCount: 4, onChange: (b) => { slixNew = b; } }),
        buttonRow({ icon: 'key', title: 'Set password', onClick: async () => {
          if (badOptional(slixCurrent, 4)) return check('The current password must be 4 bytes. Leave it empty if the tag does not ask for it.');
          if (slixNew.length !== 4) return check('Enter a new 4-byte password.');
          const id = slixId, cur = optionalBytes(slixCurrent), next = new Uint8Array(slixNew);
          if (!await UI.confirm({ title: `Change the ${slixName(id)} password?`, message: `The tag will answer to ${hexSp(next)} from now on. Write it down first; it cannot be read back.`, confirmTitle: 'Change' })) return;
          try { await run('Password set.', (s, t) => SIM.ops.slixSetPassword(s, t, id, cur, next)); UI.success(`The ${slixName(id)} password is now ${hexSp(next)}. Keep it somewhere safe.`); } catch (e) { fail(e); }
        } }),
        buttonRow({ icon: 'key', title: 'Present password', onClick: async () => {
          if (slixCurrent.length !== 4) return check('Enter the current 4-byte password.');
          const id = slixId, pwd = new Uint8Array(slixCurrent);
          try { await run('Password accepted.', (s, t) => SIM.ops.slixPresentPassword(s, t, id, pwd)); UI.success(`The tag accepted the ${slixName(id)} password.`); } catch (e) { fail(e); }
        } }),
      ], footer: 'Each 4-byte SLIX password guards one feature, and changing it needs the current one. Present password checks the current one and unlocks the tag until the scan ends; on the pretend tag every password starts as 00 00 00 00.' }));
      const privacy = async (on) => {
        if (privacyPassword.length !== 4) return check('Enter the 4-byte privacy password.');
        const pwd = new Uint8Array(privacyPassword);
        if (on && !await UI.confirm({ title: 'Turn privacy mode on?', message: `The tag hides until the privacy password ${hexSp(pwd)} is presented. Without that password you cannot use the tag again.`, confirmTitle: 'Turn on', destructive: true })) return;
        try { await run(on ? 'Privacy mode on.' : 'Privacy mode left.', (s, t) => SIM.ops.slixSetPrivacy(s, t, on, pwd)); UI.success(on ? 'The tag is in privacy mode. Present the privacy password to use it again.' : 'The tag left privacy mode until it next loses power. Once it leaves the field it hides again.'); } catch (e) { fail(e); }
      };
      wrap.append(section({ header: 'Privacy', rows: [
        hexField({ label: 'Privacy password', value: privacyPassword, byteCount: 4, onChange: (b) => { privacyPassword = b; } }),
        buttonRow({ icon: 'eye', title: 'Turn privacy on', onClick: () => privacy(true) }),
        buttonRow({ icon: 'eye', title: 'Leave privacy mode', onClick: () => privacy(false) }),
      ], footer: 'In privacy mode the tag hides its memory and serial number until the privacy password is presented. Leaving privacy mode only lasts until the tag next loses power, so it hides again once it leaves the field.' }));
      const eas = async (on) => {
        try { await run(on ? 'EAS on.' : 'EAS off.', (s, t) => SIM.ops.slixSetEAS(s, t, on)); UI.success(on ? 'EAS is on. Security gates now sound for this tag.' : 'EAS is off.'); } catch (e) { fail(e); }
      };
      wrap.append(section({ header: 'EAS', rows: [
        buttonRow({ icon: 'bell', title: 'Turn EAS on', onClick: () => eas(true) }),
        buttonRow({ icon: 'bell', title: 'Turn EAS off', onClick: () => eas(false) }),
        buttonRow({ icon: 'bell', title: 'Test EAS alarm', onClick: async () => {
          try { const on = await run('EAS checked.', (s, t) => SIM.ops.slixEASAlarm(s, t)); UI.alert({ title: on ? 'EAS is on' : 'EAS is off', message: on ? 'The tag answered the EAS alarm. Security gates would sound.' : 'The tag did not answer the EAS alarm.' }); } catch (e) { fail(e); }
        } }),
      ], footer: 'EAS is the shop anti-theft bit: with it on, security gates sound for the tag.' }));
      wrap.append(section({ header: 'Destroy', rows: [
        hexField({ label: 'Destroy password', value: destroyPassword, byteCount: 4, onChange: (b) => { destroyPassword = b; } }),
        buttonRow({ icon: 'trash', title: 'Destroy tag', destructive: true, onClick: async () => {
          if (destroyPassword.length !== 4) return check('Enter the 4-byte destroy password.');
          const pwd = new Uint8Array(destroyPassword);
          if (!await UI.confirm({ title: 'Destroy this tag?', message: 'Destroy is permanent. The tag never answers any reader again.', confirmTitle: 'Continue', destructive: true })) return;
          if (!await UI.confirm({ title: 'Destroy the tag for good?', message: 'This is the last question. The tag you scan next stops answering every reader, forever.', confirmTitle: 'Destroy tag', destructive: true })) return;
          try { await run('Tag destroyed.', (s, t) => SIM.ops.slixDestroy(s, t, pwd)); UI.success('The tag is destroyed and will not answer again.'); } catch (e) { fail(e); }
        } }),
      ], footer: 'Destroy switches the tag off forever, and nothing can bring it back. In the web preview, Reset simulated tags in Settings restores the pretend tag.', footerClass: 'danger' }));
    }
    function buildST(ctx, wrap) {
      wrap.append(section({ header: 'Password', rows: [
        stepperRow({ title: 'Password number', subtitle: '0 guards the configuration, 1 to 3 the memory areas.', value: stNumber, min: 0, max: 3, onChange: (v) => { stNumber = v; } }),
        hexField({ label: 'Current password', value: stCurrent, byteCount: 8, onChange: (b) => { stCurrent = b; } }),
        hexField({ label: 'New password', value: stNew, byteCount: 8, onChange: (b) => { stNew = b; } }),
      ], footer: "ST25TV passwords are 8 bytes, all zeros on a new chip. The chip's datasheet says what each password guards." }));
      wrap.append(section({ rows: [buttonRow({ icon: 'key', title: 'Present password', onClick: async () => {
        if (stCurrent.length !== 8) return check('Enter the current 8-byte password. New chips use 8 zero bytes.');
        const n = stNumber, pwd = new Uint8Array(stCurrent);
        try { await run('Password accepted.', (s, t) => SIM.ops.stPresentPassword(s, t, n, pwd)); UI.success(`The tag accepted password ${n}.`); } catch (e) { fail(e); }
      } })], footer: 'Tells you whether the tag accepts the password. The tag stays unlocked only while it has power, which ends with the scan.' }));
      wrap.append(section({ rows: [buttonRow({ icon: 'pencil', title: 'Write password', onClick: async () => {
        if (stCurrent.length !== 8) return check('Enter the current 8-byte password. New chips use 8 zero bytes.');
        if (stNew.length !== 8) return check('Enter a new 8-byte password.');
        const n = stNumber, cur = new Uint8Array(stCurrent), next = new Uint8Array(stNew);
        if (!await UI.confirm({ title: `Change password ${n}?`, message: `Password ${n} becomes ${hexSp(next)}. Write it down first; it cannot be read back.`, confirmTitle: 'Change' })) return;
        try {
          await run('Password written.', async (s, t) => { await SIM.ops.stPresentPassword(s, t, n, cur); await SIM.ops.stWritePassword(s, t, n, next); });
          stCurrent = next; stNew = new Uint8Array(); ctx.refresh();
          UI.success(`Password ${n} is now ${hexSp(next)}.`);
        } catch (e) { fail(e); }
      } })], footer: 'The tag only takes a new password right after the current one, so both are sent in the same scan. Write the new password down first.' }));
    }
  }

  // FeliCa: read and write 16-byte blocks of a service without encryption, and check which services exist.
  // "0-3" or "0, 4, 8-9" as block numbers; null when the text is not a list of blocks from 0 to 255.
  function parseBlockList(text) {
    const out = [];
    for (const part of text.split(/[\s,]+/).filter(Boolean)) {
      const m = part.match(/^(\d+)(?:-(\d+))?$/);
      if (!m) return null;
      const a = Number(m[1]), b = m[2] != null ? Number(m[2]) : a;
      if (a > b || b > 255) return null;
      for (let i = a; i <= b; i++) out.push(i);
    }
    return out.length ? out : null;
  }
  function feliCaTool() {
    let service = new Uint8Array([0x00, 0x0B]), blocksText = '0-3', result = null, writeBlock = 0, writeData = new Uint8Array(), servicesText = '0009, 000B, 008B, 090F, 108F', services = null;
    const HOLD_CARD = 'Hold your iPhone near the card.';
    const MAX = 32;
    const code = () => (service[0] << 8) | service[1];
    return {
      title: 'FeliCa',
      build(ctx) {
        const wrap = el('div');
        wrap.append(section({ header: 'Service', rows: [
          hexField({ label: 'Service code', value: service, byteCount: 2, onChange: (b) => { service = b; } }),
          fieldRow({ label: 'Blocks', value: blocksText, placeholder: 'for example 0-13', mono: true, onInput: (v) => { blocksText = v; } }),
        ], footer: 'On a FeliCa Lite-S, service 000B reads the user blocks and 0009 reads and writes them. List blocks as numbers and ranges, such as 0-13 or 0, 4, 8-9.' }));
        wrap.append(scanButton({ title: 'Read blocks', icon: 'search', onClick: async () => {
          if (service.length !== 2) return check('Enter a 2-byte service code, for example 00 0B.');
          const blocks = parseBlockList(blocksText);
          if (!blocks) return check('List the blocks as numbers or ranges, for example 0-13.');
          if (blocks.length > MAX) return check(`Read at most ${MAX} blocks at a time.`);
          const c = code();
          try { const data = await UI.nfc.run({ alertMessage: HOLD_CARD, successMessage: 'Blocks read.', body: (s, t) => SIM.ops.feliCaRead(s, t, c, blocks) }); result = { code: c, rows: blocks.map((b, i) => ({ block: b, bytes: data[i] })), readAt: new Date() }; ctx.refresh(); } catch (e) { fail(e); }
        } }, 'iPhone only finds FeliCa cards whose system code this app declares: 12FC (NDEF), FE00, 0003 and 8008. Services that need encryption cannot be read.'));
        if (result) {
          wrap.append(section({ header: `Service ${hex4(result.code)}`, rows: result.rows.map((r) => row({ title: `Block ${r.block}`, custom: el('div', { class: 'result-row block16', text: NDEF.hex(r.bytes, ' ') + '\n' + NDEF.ascii(r.bytes) }), accessory: 'none', onClick: () => { writeBlock = r.block; writeData = new Uint8Array(r.bytes); ctx.refresh(); } })), footer: `Read at ${timeLabel(result.readAt)}. Tap a block to load it into the write section below.` }));
        }
        wrap.append(section({ header: 'Write a block', rows: [
          stepperRow({ title: 'Block', value: writeBlock, min: 0, max: 255, onChange: (v) => { writeBlock = v; } }),
          hexField({ label: 'Data', value: writeData, byteCount: 16, onChange: (b) => { writeData = b; } }),
          buttonRow({ icon: 'pencil', title: 'Write block', onClick: async () => {
            if (service.length !== 2) return check('Enter a 2-byte service code, for example 00 0B.');
            if (writeData.length !== 16) return check('Enter exactly 16 bytes for the block.');
            const c = code(), blk = writeBlock, data = new Uint8Array(writeData);
            if (blk >= 0x80 && !await UI.confirm({ title: 'Write a system block?', message: `Block ${blk} is a system block on FeliCa Lite-S. Some values there, such as in the MC block, make the card read only for good.`, confirmTitle: 'Write block', destructive: true })) return;
            try { await UI.nfc.run({ alertMessage: HOLD_CARD, successMessage: 'Block written.', body: (s, t) => SIM.ops.feliCaWrite(s, t, c, blk, data) }); UI.success(`Block ${blk} of service ${hex4(c)} was written.`); } catch (e) { fail(e); }
          } }),
        ], footer: 'Writes 16 bytes to one block of the service code above. Only services that allow writing without encryption accept it, such as 0009 on FeliCa Lite-S.' }));
        wrap.append(section({ header: 'Service codes', rows: [
          fieldRow({ value: servicesText, placeholder: '0009, 000B, 008B, 090F, 108F', mono: true, onInput: (v) => { servicesText = v; } }),
          buttonRow({ icon: 'search', title: 'Check services', onClick: async () => {
            const parts = servicesText.split(/[\s,]+/).filter(Boolean);
            if (!parts.length || parts.some((p) => !/^[0-9a-f]{4}$/i.test(p))) return check('Enter service codes as four hex digits each, for example 000B, 090F.');
            if (parts.length > MAX) return check(`Check at most ${MAX} service codes at a time.`);
            const codes = parts.map((p) => parseInt(p, 16));
            try { const list = await UI.nfc.run({ alertMessage: HOLD_CARD, successMessage: 'Services checked.', body: (s, t) => SIM.ops.feliCaServices(s, t, codes) }); services = { list, checkedAt: new Date() }; ctx.refresh(); } catch (e) { fail(e); }
          } }),
        ], footer: 'Four hex digits per service code, separated by commas or spaces.' }));
        if (services) wrap.append(section({ header: 'Services', rows: services.list.map((x) => colorValue(row({ title: hex4(x.code), mono: true, value: x.exists ? 'Found' : 'Not found', accessory: 'none' }), x.exists ? 'var(--green)' : 'var(--secondary)')), footer: `Checked at ${timeLabel(services.checkedAt)}. Found services can still need encryption to read.` }));
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
      wrap.append(section({ header: 'What it does', rows: [row({ title: 'NFC Editor reads, writes and edits NFC tags. Scan a tag to see its chip, serial number, memory and records.', subtitleWrap: true, accessory: 'none' })], footer: 'Everything stays on your iPhone. No accounts, no analytics.' }));
      const steps = ['Open Shortcuts and tap Automation.', 'Tap New Automation, or the plus button, and choose NFC.', 'Tap Scan and hold your iPhone near the tag, then name it.', 'Choose Run Immediately if you do not want to be asked each time.', 'Pick the action to run, for example Open URL, Set Focus or an NFC Editor action.'];
      wrap.append(section({ header: 'Automations', rows: [
        row({ icon: 'layers', iconBg: '#5856D6', title: 'Run an action when a tag is scanned', subtitle: 'iOS runs automations on a tag scan from the Shortcuts app, not from other apps. To set one up:', subtitleWrap: true, accessory: 'none' }),
        el('div', { class: 'cell plain' }, el('ol', { class: 'steps' }, steps.map((t) => el('li', { text: t })))),
      ], footer: 'iOS reads the tag for the automation itself, so the tag does not need any records and NFC Editor does not need to be open.' }));
      wrap.append(section({ header: 'Shortcuts actions', rows: [
        row({ icon: 'wave', title: 'Read NFC tag', subtitle: 'Opens the app, scans a tag and returns its records as text, one line per record.', subtitleWrap: true, accessory: 'none' }),
        row({ icon: 'pencil', iconBg: 'var(--green)', title: 'Write profile to tag', subtitle: 'Opens the app and writes a saved profile to the next tag you hold, then checks it.', subtitleWrap: true, accessory: 'none' }),
      ], footer: 'Find both in the Shortcuts app under NFC Editor, or ask Siri to “Read an NFC tag with NFC Editor”. Both open the app to scan, because iOS only allows NFC in the app in front; the web preview cannot run them.' }));
      wrap.append(section({ header: 'Limits', rows: [row({ title: 'iOS does not let apps read MIFARE Classic data blocks or emulate a tag, so NFC Editor does neither. An app also cannot start an action on its own when a tag is scanned; use a Shortcuts automation for that.', accessory: 'none' })] }));
      // A link opens outside the app, so like Link in AboutView it has no chevron.
      wrap.append(section({ rows: [buttonRow({ icon: 'terminal', title: 'Source code on GitHub', onClick: () => UI.openURL('https://github.com/katsuma0/nfc-editor') })] }));
      return wrap;
    } };
  }

  return { app, read: readScreen, write: writeScreen, tools: toolsScreen, saved: savedScreen, openSettings };
})();
