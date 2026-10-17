// Persistence for the web preview: settings, saved tags and profiles, the write queue and scan history.
const STORE = (() => {
  const read = (k, fallback) => { try { const v = JSON.parse(localStorage.getItem(k)); return v == null ? fallback : v; } catch (e) { return fallback; } };
  const write = (k, v) => { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) { /* private mode or full */ } };
  const uuid = () => (crypto.randomUUID ? crypto.randomUUID() : String(Date.now()) + Math.random().toString(16).slice(2));

  const settings = Object.assign({ hapticsEnabled: true, verifyAfterWrite: true, defaultLanguage: 'en', readFullMemoryOnScan: true, keepScreenAwake: false, simulatedTag: 'ntag216-blank', commandHistory: [] }, read('nfce.settings', {}));
  const saveSettings = () => write('nfce.settings', settings);
  const addCommandToHistory = (hex) => { const h = hex.trim().toUpperCase(); if (!h) return; settings.commandHistory = [h, ...settings.commandHistory.filter((x) => x !== h)].slice(0, 50); saveSettings(); };
  const clearCommandHistory = () => { settings.commandHistory = []; saveSettings(); };

  let items = read('nfce.saved', []);
  const saveItems = () => { items.sort((a, b) => (a.updatedAt < b.updatedAt ? 1 : -1)); write('nfce.saved', items); };
  const add = (item) => { items.unshift(item); saveItems(); return item; };
  const update = (item) => { item.updatedAt = new Date().toISOString(); items = items.map((x) => (x.id === item.id ? item : x)); saveItems(); };
  const remove = (id) => { items = items.filter((x) => x.id !== id); saveItems(); };
  const item = (id) => items.find((x) => x.id === id);
  const duplicate = (id) => { const src = item(id); if (!src) return null; const copy = JSON.parse(JSON.stringify(src)); copy.id = uuid(); copy.name = src.name + ' copy'; copy.createdAt = copy.updatedAt = new Date().toISOString(); return add(copy); };
  const makeTag = (name, info) => { const now = new Date().toISOString(); return { id: uuid(), name, kind: 'tag', createdAt: now, updatedAt: now, drafts: info.records.map((r) => NDEF.fromRecord(r)), records: info.records.map(SIM.serializeRecord), tagInfo: SIM.serializeInfo(info) }; };
  const makeProfile = (name, drafts) => { const now = new Date().toISOString(); let records = []; try { records = drafts.flatMap(NDEF.buildAll).map(SIM.serializeRecord); } catch (e) { records = []; } return { id: uuid(), name, kind: 'profile', createdAt: now, updatedAt: now, drafts: JSON.parse(JSON.stringify(drafts)), records, tagInfo: null }; };
  const itemRecords = (it) => { if (it.kind === 'profile') { try { return it.drafts.flatMap(NDEF.buildAll); } catch (e) { return []; } } return (it.records || []).map(SIM.restoreRecord); };
  const itemInfo = (it) => (it.tagInfo ? SIM.restoreInfo(it.tagInfo) : null);
  const subtitle = (it) => { const recs = itemRecords(it); const n = recs.length; const parts = [n === 1 ? '1 record' : n + ' records', UI.bytesLabel(n ? NDEF.byteCount(recs) : 0)]; if (it.tagInfo) parts.push(it.tagInfo.chip.name); return parts.join(', '); };
  const exportText = (it) => JSON.stringify(it, null, 2);
  const importText = (text) => {
    const parsed = JSON.parse(text);
    const list = Array.isArray(parsed) ? parsed : [parsed];
    let n = 0;
    for (const raw of list) {
      if (!raw || typeof raw !== 'object' || !raw.name || !raw.kind) continue;
      const copy = Object.assign({ drafts: [], records: [], tagInfo: null }, raw, { id: uuid(), updatedAt: new Date().toISOString() });
      items.unshift(copy); n++;
    }
    saveItems();
    return n;
  };

  const queue = Object.assign({ drafts: [], options: { lockAfterWrite: false, verifyAfterWrite: true, eraseFirst: false } }, read('nfce.queue', {}));
  queue.options.lockAfterWrite = false;
  const saveQueue = () => write('nfce.queue', { drafts: queue.drafts, options: { lockAfterWrite: false, verifyAfterWrite: queue.options.verifyAfterWrite, eraseFirst: queue.options.eraseFirst } });
  const queueRecords = () => queue.drafts.flatMap(NDEF.buildAll);
  const queueBytes = () => { try { return queue.drafts.length ? NDEF.byteCount(queueRecords()) : 0; } catch (e) { return queue.drafts.reduce((n, d) => n + NDEF.draftSize(d), 0); } };

  const scans = { last: null, history: [] };
  const recordScan = (info) => { scans.last = info; scans.history = [info, ...scans.history].slice(0, 20); };
  // Same columns as AppState.exportScanLogCSV: serial, chip, record count, ISO 8601 time. Fields with a comma,
  // a quote or a line break are quoted so spreadsheets keep them in one cell.
  const csvField = (v) => { const t = String(v); return /[",\r\n]/.test(t) ? '"' + t.replace(/"/g, '""') + '"' : t; };
  const exportScanLogCSV = () => ['Serial,Chip,Records,Scanned at', ...scans.history.map((i) => [SIM.info.serialLine(i), SIM.info.chipLine(i), i.records.length, i.scannedAt].map(csvField).join(','))].join('\r\n') + '\r\n';

  return { settings, saveSettings, addCommandToHistory, clearCommandHistory, get items() { return items; }, add, update, remove, item, duplicate, makeTag, makeProfile, itemRecords, itemInfo, subtitle, exportText, importText, queue, saveQueue, queueRecords, queueBytes, scans, recordScan, exportScanLogCSV, uuid };
})();
