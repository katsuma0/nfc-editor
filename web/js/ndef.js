// NDEF codec, record builders, parsers and the editable draft model.
// A port of the Swift NDEF layer, kept dependency free so the web preview behaves like the app.
const NDEF = (() => {
  const TNF = { empty: 0, wellKnown: 1, media: 2, absoluteURI: 3, external: 4, unknown: 5, unchanged: 6 };
  const TNF_LABEL = ['Empty', 'Well known', 'MIME media', 'Absolute URI', 'External', 'Unknown', 'Unchanged'];
  const URI_PREFIXES = ['', 'http://www.', 'https://www.', 'http://', 'https://', 'tel:', 'mailto:',
    'ftp://anonymous:anonymous@', 'ftp://ftp.', 'ftps://', 'sftp://', 'smb://', 'nfs://', 'ftp://', 'dav://',
    'news:', 'telnet://', 'imap:', 'rtsp://', 'urn:', 'pop:', 'sip:', 'sips:', 'tftp:', 'btspp://', 'btl2cap://',
    'btgoep://', 'tcpobex://', 'irdaobex://', 'file://', 'urn:epc:id:', 'urn:epc:tag:', 'urn:epc:pat:',
    'urn:epc:raw:', 'urn:epc:', 'urn:nfc:'];
  const encoder = new TextEncoder();
  const decoder = new TextDecoder('utf-8', { fatal: false });

  // Bytes
  const utf8 = (s) => encoder.encode(s);
  const text = (b) => decoder.decode(b);
  const hex = (b, sep = '') => Array.from(b, (x) => x.toString(16).toUpperCase().padStart(2, '0')).join(sep);
  const normalizeHex = (s) => s.replace(/0x/gi, '').replace(/[^0-9a-fA-F]/g, '').toUpperCase();
  const isValidHex = (s) => { const n = normalizeHex(s); return n.length > 0 && n.length % 2 === 0; };
  const fromHex = (s) => {
    const n = normalizeHex(s);
    if (n.length % 2 !== 0) return null;
    const out = new Uint8Array(n.length / 2);
    for (let i = 0; i < out.length; i++) out[i] = parseInt(n.substr(i * 2, 2), 16);
    return out;
  };
  const concat = (...parts) => {
    const total = parts.reduce((n, p) => n + p.length, 0);
    const out = new Uint8Array(total);
    let o = 0;
    for (const p of parts) { out.set(p, o); o += p.length; }
    return out;
  };
  const equal = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);
  const ascii = (b) => Array.from(b, (x) => (x >= 32 && x < 127 ? String.fromCharCode(x) : '.')).join('');
  const percentEncode = (s) => encodeURIComponent(s).replace(/[!'()*]/g, (c) => '%' + c.charCodeAt(0).toString(16).toUpperCase());

  // Records
  function record(tnf, type, payload, id) {
    return {
      tnf,
      type: typeof type === 'string' ? utf8(type) : (type || new Uint8Array()),
      id: id || new Uint8Array(),
      payload: payload || new Uint8Array(),
    };
  }
  const typeString = (r) => text(r.type);
  const isText = (r) => r.tnf === TNF.wellKnown && typeString(r) === 'T';
  const isURI = (r) => r.tnf === TNF.wellKnown && typeString(r) === 'U';
  function encodedSize(r) {
    const sr = r.payload.length < 256;
    return 1 + 1 + (sr ? 1 : 4) + (r.id.length ? 1 : 0) + r.type.length + r.id.length + r.payload.length;
  }
  function encode(records) {
    if (!records.length) records = [record(TNF.empty)];
    const parts = [];
    records.forEach((r, i) => {
      const sr = r.payload.length < 256;
      let flags = r.tnf & 7;
      if (i === 0) flags |= 0x80;
      if (i === records.length - 1) flags |= 0x40;
      if (sr) flags |= 0x10;
      if (r.id.length) flags |= 0x08;
      const head = [flags, r.type.length];
      if (sr) head.push(r.payload.length);
      else head.push((r.payload.length >>> 24) & 255, (r.payload.length >>> 16) & 255, (r.payload.length >>> 8) & 255, r.payload.length & 255);
      if (r.id.length) head.push(r.id.length);
      parts.push(new Uint8Array(head), r.type, r.id, r.payload);
    });
    return concat(...parts);
  }
  function decode(bytes) {
    const out = [];
    let i = 0;
    let first = true;
    while (i < bytes.length) {
      const flags = bytes[i++];
      if (first && !(flags & 0x80)) throw new Error('The message does not start with a record.');
      first = false;
      if (flags & 0x20) throw new Error('Chunked records are not supported.');
      const tnf = flags & 7;
      if (tnf === 7) throw new Error('Reserved record type.');
      if (i >= bytes.length) throw new Error('The message is truncated.');
      const typeLen = bytes[i++];
      let payloadLen;
      if (flags & 0x10) { if (i >= bytes.length) throw new Error('The message is truncated.'); payloadLen = bytes[i++]; }
      else { if (i + 4 > bytes.length) throw new Error('The message is truncated.'); payloadLen = ((bytes[i] << 24) >>> 0) + (bytes[i + 1] << 16) + (bytes[i + 2] << 8) + bytes[i + 3]; i += 4; }
      let idLen = 0;
      if (flags & 0x08) { if (i >= bytes.length) throw new Error('The message is truncated.'); idLen = bytes[i++]; }
      if (i + typeLen + idLen + payloadLen > bytes.length) throw new Error('The message is truncated.');
      const type = bytes.slice(i, i + typeLen); i += typeLen;
      const id = bytes.slice(i, i + idLen); i += idLen;
      const payload = bytes.slice(i, i + payloadLen); i += payloadLen;
      out.push({ tnf, type, id, payload });
      if (flags & 0x40) return out;
    }
    throw new Error('The message has no end record.');
  }
  const byteCount = (records) => encode(records).length;
  function tlv(message) {
    const len = message.length < 255 ? [message.length] : [0xFF, message.length >> 8, message.length & 255];
    return concat(new Uint8Array([0x03, ...len]), message, new Uint8Array([0xFE]));
  }
  function messageFromTLV(bytes) {
    let i = 0;
    while (i < bytes.length) {
      const t = bytes[i];
      if (t === 0x00) { i++; continue; }
      if (t === 0xFE) return null;
      if (i + 1 >= bytes.length) return null;
      let len = bytes[i + 1];
      let start = i + 2;
      if (len === 0xFF) { if (i + 3 >= bytes.length) return null; len = (bytes[i + 2] << 8) | bytes[i + 3]; start = i + 4; }
      if (t === 0x03) return bytes.slice(start, Math.min(start + len, bytes.length));
      i = start + len;
    }
    return null;
  }

  // URI
  function abbreviate(uri) {
    let best = 0;
    for (let c = 1; c < URI_PREFIXES.length; c++) {
      if (uri.startsWith(URI_PREFIXES[c]) && URI_PREFIXES[c].length > URI_PREFIXES[best].length) best = c;
    }
    return { code: best, rest: uri.slice(URI_PREFIXES[best].length) };
  }
  const expand = (code, rest) => (URI_PREFIXES[code] || '') + rest;

  // Builders
  const B = {
    text(t, lang = 'en') {
      const l = utf8(lang.slice(0, 63));
      return record(TNF.wellKnown, 'T', concat(new Uint8Array([l.length]), l, utf8(t)));
    },
    uri(u) {
      const { code, rest } = abbreviate(u);
      return record(TNF.wellKnown, 'U', concat(new Uint8Array([code]), utf8(rest)));
    },
    absoluteURI: (u) => record(TNF.absoluteURI, u, new Uint8Array()),
    email(to, subject, body) {
      const q = [];
      if (subject) q.push('subject=' + percentEncode(subject));
      if (body) q.push('body=' + percentEncode(body));
      return B.uri('mailto:' + to + (q.length ? '?' + q.join('&') : ''));
    },
    phone: (n) => B.uri('tel:' + n.replace(/\s+/g, '')),
    sms: (n, body) => B.uri('sms:' + n.replace(/\s+/g, '') + (body ? '?body=' + percentEncode(body) : '')),
    geo(lat, lon, format = 'geo') {
      const a = Number(lat), b = Number(lon);
      if (format === 'apple') return B.uri(`https://maps.apple.com/?ll=${a},${b}`);
      if (format === 'google') return B.uri(`https://www.google.com/maps/search/?api=1&query=${a},${b}`);
      return B.uri(`geo:${a},${b}`);
    },
    address(addr, format = 'apple') {
      const e = percentEncode(addr);
      if (format === 'google') return B.uri('https://www.google.com/maps/search/?api=1&query=' + e);
      if (format === 'geo') return B.uri('geo:0,0?q=' + e);
      return B.uri('https://maps.apple.com/?q=' + e);
    },
    wifi: (cred) => record(TNF.media, 'application/vnd.wfa.wsc', encodeWifi(cred)),
    bluetooth: (oob) => record(TNF.media, 'application/vnd.bluetooth.ep.oob', encodeBluetooth(oob)),
    vcard: (card) => record(TNF.media, 'text/vcard', utf8(encodeVCard(card))),
    social: (platform, handle) => B.uri(socialURL(platform, handle)),
    androidApp: (pkg) => record(TNF.external, 'android.com:pkg', utf8(pkg)),
    mime: (type, payload) => record(TNF.media, type, payload),
    external: (domain, type, payload) => record(TNF.external, domain + ':' + type, payload),
    raw: (tnf, type, id, payload) => record(tnf, type, payload, id),
    empty: () => record(TNF.empty),
    smartPoster(uri, title, lang = 'en') {
      const inner = [B.uri(uri)];
      if (title) inner.push(B.text(title, lang));
      return record(TNF.wellKnown, 'Sp', encode(inner));
    },
    // Connection handover select: version 0x13 then an inner message with one alternative carrier record
    // ("ac") that points at the carrier record carrying the real pairing data by its identifier.
    handoverSelect(carrierID = '0') {
      const idBytes = utf8(carrierID);
      const ac = record(TNF.wellKnown, 'ac', concat(new Uint8Array([0x01, idBytes.length]), idBytes, new Uint8Array([0x00])));
      return record(TNF.wellKnown, 'Hs', concat(new Uint8Array([0x13]), encode([ac])));
    },
  };

  // Wi-Fi (WSC credential)
  const WIFI_AUTH = [['open', 'Open', 0x0001], ['wpaPSK', 'WPA Personal', 0x0002], ['wpa2PSK', 'WPA2 Personal', 0x0020], ['wpaWpa2PSK', 'WPA/WPA2 Personal', 0x0022], ['wpa3SAE', 'WPA3 Personal', 0x0020]];
  const WIFI_ENC = [['none', 'None', 0x0001], ['aes', 'AES', 0x0008], ['tkip', 'TKIP', 0x0004], ['aesTKIP', 'AES/TKIP', 0x000C]];
  const attr = (id, data) => concat(new Uint8Array([id >> 8, id & 255, data.length >> 8, data.length & 255]), data);
  const u16 = (v) => new Uint8Array([v >> 8, v & 255]);
  function encodeWifi(c) {
    const auth = (WIFI_AUTH.find((a) => a[0] === c.auth) || WIFI_AUTH[2])[2];
    const enc = c.auth === 'open' ? 0x0001 : (WIFI_ENC.find((e) => e[0] === c.encryption) || WIFI_ENC[1])[2];
    const key = c.auth === 'open' ? '' : c.password;
    const cred = concat(attr(0x1026, new Uint8Array([1])), attr(0x1045, utf8(c.ssid)), attr(0x1003, u16(auth)),
      attr(0x100F, u16(enc)), attr(0x1027, utf8(key)), attr(0x1020, new Uint8Array(6).fill(0xFF)));
    return attr(0x100E, cred);
  }
  function decodeWifi(bytes) {
    const read = (b, start, end, into) => {
      let i = start;
      while (i + 4 <= end) {
        const id = (b[i] << 8) | b[i + 1];
        const len = (b[i + 2] << 8) | b[i + 3];
        const data = b.slice(i + 4, Math.min(i + 4 + len, end));
        if (id === 0x100E) read(b, i + 4, i + 4 + len, into);
        else into[id] = data;
        i += 4 + len;
      }
    };
    const found = {};
    read(bytes, 0, bytes.length, found);
    if (!found[0x1045]) return null;
    const authVal = found[0x1003] ? (found[0x1003][0] << 8) | found[0x1003][1] : 0x0020;
    const encVal = found[0x100F] ? (found[0x100F][0] << 8) | found[0x100F][1] : 0x0008;
    const auth = (WIFI_AUTH.find((a) => a[2] === authVal) || WIFI_AUTH[2])[0];
    const encryption = (WIFI_ENC.find((e) => e[2] === encVal) || WIFI_ENC[1])[0];
    return { ssid: text(found[0x1045]), password: found[0x1027] ? text(found[0x1027]) : '', auth, encryption, hidden: false };
  }

  // Bluetooth OOB
  const isValidMAC = (s) => /^([0-9A-Fa-f]{2}[:-]?){5}[0-9A-Fa-f]{2}$/.test(s.trim());
  const normalizeMAC = (s) => normalizeHex(s).match(/.{2}/g).join(':');
  function encodeBluetooth(o) {
    const mac = fromHex(o.address).reverse();
    let eir = new Uint8Array();
    if (o.name) { const n = utf8(o.name); eir = concat(new Uint8Array([n.length + 1, 0x09]), n); }
    const total = 2 + 6 + eir.length;
    return concat(new Uint8Array([total & 255, total >> 8]), mac, eir);
  }
  function decodeBluetooth(b) {
    if (b.length < 8) return null;
    const address = hex(b.slice(2, 8).reverse(), ':');
    let name = null;
    let i = 8;
    while (i + 1 < b.length) {
      const len = b[i];
      if (!len) break;
      const type = b[i + 1];
      if (type === 0x09 || type === 0x08) name = text(b.slice(i + 2, i + 1 + len));
      i += len + 1;
    }
    return { address, name };
  }

  // vCard 3.0
  const VCARD_FIELDS = ['firstName', 'lastName', 'organization', 'title', 'phone', 'email', 'website', 'address', 'note'];
  const vEscape = (s) => s.replace(/\\/g, '\\\\').replace(/;/g, '\\;').replace(/,/g, '\\,').replace(/\r?\n/g, '\\n');
  const vUnescape = (s) => s.replace(/\\n/gi, '\n').replace(/\\,/g, ',').replace(/\\;/g, ';').replace(/\\\\/g, '\\');
  const fullName = (c) => `${c.firstName || ''} ${c.lastName || ''}`.trim();
  function encodeVCard(c) {
    const lines = ['BEGIN:VCARD', 'VERSION:3.0', `N:${vEscape(c.lastName || '')};${vEscape(c.firstName || '')};;;`, `FN:${vEscape(fullName(c))}`];
    if (c.organization) lines.push('ORG:' + vEscape(c.organization));
    if (c.title) lines.push('TITLE:' + vEscape(c.title));
    if (c.phone) lines.push('TEL;TYPE=CELL:' + vEscape(c.phone));
    if (c.email) lines.push('EMAIL:' + vEscape(c.email));
    if (c.website) lines.push('URL:' + vEscape(c.website));
    if (c.address) lines.push('ADR;TYPE=HOME:;;' + vEscape(c.address) + ';;;;');
    if (c.note) lines.push('NOTE:' + vEscape(c.note));
    lines.push('END:VCARD');
    return lines.join('\r\n') + '\r\n';
  }
  function decodeVCard(s) {
    if (!/BEGIN:VCARD/i.test(s)) return null;
    const unfolded = s.replace(/\r?\n[ \t]/g, '');
    const card = { firstName: '', lastName: '', organization: '', title: '', phone: '', email: '', website: '', address: '', note: '' };
    let fn = '';
    for (const line of unfolded.split(/\r?\n/)) {
      const idx = line.indexOf(':');
      if (idx < 0) continue;
      const name = line.slice(0, idx).split(';')[0].toUpperCase();
      const value = line.slice(idx + 1);
      if (name === 'N') { const p = value.split(/(?<!\\);/); card.lastName = vUnescape(p[0] || ''); card.firstName = vUnescape(p[1] || ''); }
      else if (name === 'FN') fn = vUnescape(value);
      else if (name === 'ORG') card.organization = vUnescape(value.split(/(?<!\\);/)[0]);
      else if (name === 'TITLE') card.title = vUnescape(value);
      else if (name === 'TEL' && !card.phone) card.phone = vUnescape(value);
      else if (name === 'EMAIL' && !card.email) card.email = vUnescape(value);
      else if (name === 'URL' && !card.website) card.website = vUnescape(value);
      else if (name === 'ADR' && !card.address) card.address = value.split(/(?<!\\);/).map(vUnescape).filter(Boolean).join(', ');
      else if (name === 'NOTE') card.note = vUnescape(value);
    }
    if (!card.firstName && !card.lastName && fn) { const p = fn.split(' '); card.firstName = p.shift(); card.lastName = p.join(' '); }
    return card;
  }

  // Social
  const SOCIAL = [
    ['x', 'X', (h) => 'https://x.com/' + h, /^https?:\/\/(www\.)?(x|twitter)\.com\/([^/?#]+)/i],
    ['instagram', 'Instagram', (h) => 'https://www.instagram.com/' + h, /^https?:\/\/(www\.)?instagram\.com\/([^/?#]+)/i],
    ['facebook', 'Facebook', (h) => 'https://www.facebook.com/' + h, /^https?:\/\/(www\.)?facebook\.com\/([^/?#]+)/i],
    ['linkedin', 'LinkedIn', (h) => 'https://www.linkedin.com/in/' + h, /^https?:\/\/(www\.)?linkedin\.com\/in\/([^/?#]+)/i],
    ['tiktok', 'TikTok', (h) => 'https://www.tiktok.com/@' + h, /^https?:\/\/(www\.)?tiktok\.com\/@([^/?#]+)/i],
    ['youtube', 'YouTube', (h) => 'https://www.youtube.com/@' + h, /^https?:\/\/(www\.)?youtube\.com\/@([^/?#]+)/i],
    ['whatsapp', 'WhatsApp', (h) => 'https://wa.me/' + h.replace(/\D/g, ''), /^https?:\/\/(www\.)?wa\.me\/([^/?#]+)/i],
    ['snapchat', 'Snapchat', (h) => 'https://www.snapchat.com/add/' + h, /^https?:\/\/(www\.)?snapchat\.com\/add\/([^/?#]+)/i],
    ['threads', 'Threads', (h) => 'https://www.threads.net/@' + h, /^https?:\/\/(www\.)?threads\.net\/@([^/?#]+)/i],
    ['github', 'GitHub', (h) => 'https://github.com/' + h, /^https?:\/\/(www\.)?github\.com\/([^/?#]+)/i],
    ['telegram', 'Telegram', (h) => 'https://t.me/' + h, /^https?:\/\/(www\.)?t\.me\/([^/?#]+)/i],
  ];
  const socialURL = (platform, handle) => {
    const p = SOCIAL.find((s) => s[0] === platform) || SOCIAL[1];
    return p[2](handle.trim().replace(/^@/, ''));
  };
  function detectSocial(url) {
    for (const s of SOCIAL) { const m = url.match(s[3]); if (m) return { platform: s[0], name: s[1], handle: m[m.length - 1] }; }
    return null;
  }

  // Kinds
  const KINDS = [
    ['text', 'Text', 'text', 'A note anyone can read'],
    ['url', 'URL / URI', 'link', 'Opens a website or app link'],
    ['email', 'Email', 'envelope', 'Opens a new email with the address filled in'],
    ['contact', 'Contact', 'person', 'A vCard the phone can add to Contacts'],
    ['phone', 'Phone number', 'phone', 'Starts a call'],
    ['sms', 'SMS', 'message', 'Opens Messages with a number and text'],
    ['geo', 'Location', 'location', 'Coordinates for a map'],
    ['address', 'Address', 'map', 'A street address for a map'],
    ['wifi', 'Wi-Fi network', 'wifi', 'Name and password of a network'],
    ['bluetooth', 'Bluetooth', 'bluetooth', 'Pairing address of a device'],
    ['social', 'Social', 'at', 'A profile on X, Instagram, LinkedIn and others'],
    ['app', 'Application', 'app', 'Opens an Android app by package name'],
    ['customURI', 'Custom URI', 'linkplus', 'Any URI, written as typed'],
    ['customMIME', 'Custom MIME', 'doc', 'A MIME type with text or hex data'],
    ['external', 'External type', 'box', 'A domain:type record with data'],
    ['raw', 'Raw record', 'number', 'Type name format, type and payload in hex'],
    ['empty', 'Empty', 'dashedcircle', 'An empty record'],
    ['smartPoster', 'Smart poster', 'richtext', 'A URL with a title, like a poster'],
    ['handover', 'Handover select', 'bluetooth', 'Bluetooth pairing, as Android expects'],
    ['unknown', 'Unknown', 'question', ''],
  ];
  const kindInfo = (id) => { const k = KINDS.find((x) => x[0] === id) || KINDS[KINDS.length - 1]; return { id: k[0], name: k[1], icon: k[2], blurb: k[3] }; };
  const WRITABLE = KINDS.filter((k) => k[0] !== 'handover' && k[0] !== 'unknown').map((k) => k[0]);

  // Parsing for display
  function parseText(r) {
    if (!isText(r) || !r.payload.length) return null;
    const status = r.payload[0];
    const langLen = status & 0x3F;
    const lang = text(r.payload.slice(1, 1 + langLen));
    const body = r.payload.slice(1 + langLen);
    const value = status & 0x80 ? new TextDecoder('utf-16be').decode(body) : text(body);
    return { text: value, language: lang };
  }
  function parseURI(r) {
    if (isURI(r) && r.payload.length) return expand(r.payload[0], text(r.payload.slice(1)));
    if (r.tnf === TNF.absoluteURI) return typeString(r);
    return null;
  }
  function parseSmartPoster(r) {
    if (!(r.tnf === TNF.wellKnown && typeString(r) === 'Sp')) return null;
    try {
      const inner = decode(r.payload);
      const u = inner.map(parseURI).find(Boolean);
      const t = inner.map(parseText).find(Boolean);
      return u ? { uri: u, title: t ? t.text : null } : null;
    } catch (e) { return null; }
  }
  const query = (s) => { const out = {}; s.split('&').forEach((p) => { const [k, v = ''] = p.split('='); if (k) out[decodeURIComponent(k)] = decodeURIComponent(v.replace(/\+/g, ' ')); }); return out; };
  function parse(r) {
    const base = (kind, detail, fields = [], actions = [], title) => ({ kind, title: title || kindInfo(kind).name, detail, fields, actions, icon: kindInfo(kind).icon });
    const withCopy = (s) => { if (s.detail && !s.actions.some((a) => a.type === 'copy')) s.actions.push({ type: 'copy', value: s.detail, label: 'Copy' }); return s; };
    if (r.tnf === TNF.empty) return base('empty', 'No content');
    if (r.tnf === TNF.wellKnown && typeString(r) === 'Hs') return base('handover', 'Bluetooth pairing', [{ label: 'Record', value: 'Handover select' }]);
    const t = parseText(r);
    if (t) return withCopy(base('text', t.text, [{ label: 'Language', value: t.language || 'none' }]));
    const sp = parseSmartPoster(r);
    if (sp) return withCopy(base('smartPoster', sp.uri, sp.title ? [{ label: 'Title', value: sp.title }] : [], [{ type: 'open', value: sp.uri, label: 'Open link' }]));
    const u = parseURI(r);
    if (u !== null) {
      const lower = u.toLowerCase();
      if (lower.startsWith('mailto:')) {
        const [to, q = ''] = u.slice(7).split('?');
        const p = query(q);
        const fields = [{ label: 'To', value: to }];
        if (p.subject) fields.push({ label: 'Subject', value: p.subject });
        if (p.body) fields.push({ label: 'Body', value: p.body });
        return withCopy(base('email', to, fields, [{ type: 'open', value: u, label: 'Write email' }]));
      }
      if (lower.startsWith('tel:')) return withCopy(base('phone', u.slice(4), [], [{ type: 'open', value: u, label: 'Call' }]));
      if (lower.startsWith('sms:') || lower.startsWith('smsto:')) {
        const rest = u.slice(u.indexOf(':') + 1);
        const [num, q = ''] = rest.split(/[?&]/);
        const p = query(q.replace(/^.*?body=/, 'body='));
        const fields = p.body ? [{ label: 'Message', value: p.body }] : [];
        return withCopy(base('sms', num, fields, [{ type: 'open', value: 'sms:' + num + (p.body ? '&body=' + percentEncode(p.body) : ''), label: 'Send message' }]));
      }
      if (lower.startsWith('geo:')) {
        const m = u.match(/^geo:(-?[\d.]+),(-?[\d.]+)(\?q=(.*))?/i);
        if (m && m[4] && m[1] === '0' && m[2] === '0') { const a = decodeURIComponent(m[4]); return withCopy(base('address', a, [], [{ type: 'open', value: 'https://maps.apple.com/?q=' + percentEncode(a), label: 'Open in Maps' }])); }
        if (m) return withCopy(base('geo', `${m[1]}, ${m[2]}`, [{ label: 'Latitude', value: m[1] }, { label: 'Longitude', value: m[2] }], [{ type: 'open', value: `https://maps.apple.com/?ll=${m[1]},${m[2]}`, label: 'Open in Maps' }]));
      }
      const mapsLL = u.match(/maps\.apple\.com\/\?ll=(-?[\d.]+),(-?[\d.]+)/i) || u.match(/google\.com\/maps\/search\/\?api=1&query=(-?[\d.]+),(-?[\d.]+)$/i);
      if (mapsLL) return withCopy(base('geo', `${mapsLL[1]}, ${mapsLL[2]}`, [{ label: 'Latitude', value: mapsLL[1] }, { label: 'Longitude', value: mapsLL[2] }], [{ type: 'open', value: u, label: 'Open in Maps' }]));
      const mapsQ = u.match(/maps\.apple\.com\/\?q=(.+)$/i) || u.match(/google\.com\/maps\/search\/\?api=1&query=(.+)$/i);
      if (mapsQ) return withCopy(base('address', decodeURIComponent(mapsQ[1]), [], [{ type: 'open', value: u, label: 'Open in Maps' }]));
      const social = detectSocial(u);
      if (social) return withCopy(base('social', u, [{ label: 'Handle', value: social.handle }], [{ type: 'open', value: u, label: 'Open ' + social.name }], social.name));
      const isWeb = /^https?:\/\//i.test(u);
      return withCopy(base('url', u, [], [{ type: 'open', value: u, label: isWeb ? 'Open link' : 'Open' }], isWeb ? 'URL' : 'URI'));
    }
    const type = typeString(r).toLowerCase();
    if (r.tnf === TNF.media) {
      if (type === 'text/vcard' || type === 'text/x-vcard') {
        const card = decodeVCard(text(r.payload));
        if (card) {
          const fields = [];
          if (card.phone) fields.push({ label: 'Phone', value: card.phone });
          if (card.email) fields.push({ label: 'Email', value: card.email });
          if (card.organization) fields.push({ label: 'Organization', value: card.organization });
          if (card.title) fields.push({ label: 'Title', value: card.title });
          if (card.website) fields.push({ label: 'Website', value: card.website });
          if (card.address) fields.push({ label: 'Address', value: card.address });
          if (card.note) fields.push({ label: 'Note', value: card.note });
          const actions = [{ type: 'vcard', value: card, label: 'Add to Contacts' }];
          if (card.phone) actions.push({ type: 'copy', value: card.phone, label: 'Copy phone' });
          return base('contact', fullName(card) || card.organization || 'Contact', fields, actions);
        }
      }
      if (type === 'application/vnd.wfa.wsc') {
        const w = decodeWifi(r.payload);
        if (w) {
          const fields = [{ label: 'Password', value: w.password || 'None' }, { label: 'Security', value: (WIFI_AUTH.find((a) => a[0] === w.auth) || WIFI_AUTH[2])[1] }, { label: 'Encryption', value: (WIFI_ENC.find((e) => e[0] === w.encryption) || WIFI_ENC[1])[1] }];
          const actions = [{ type: 'wifi', value: w, label: 'Join network' }];
          if (w.password) actions.push({ type: 'copy', value: w.password, label: 'Copy password' });
          return base('wifi', w.ssid, fields, actions);
        }
      }
      if (type === 'application/vnd.bluetooth.ep.oob') {
        const b = decodeBluetooth(r.payload);
        if (b) return withCopy(base('bluetooth', b.name || b.address, [{ label: 'Address', value: b.address }], [{ type: 'copy', value: b.address, label: 'Copy address' }]));
      }
      if (type === 'text/plain') return withCopy(base('text', text(r.payload)));
      return withCopy(base('customMIME', typeString(r), [{ label: 'Payload', value: hex(r.payload, ' ') || 'Empty' }, { label: 'As text', value: ascii(r.payload) }]));
    }
    if (r.tnf === TNF.external) {
      if (type === 'android.com:pkg') { const pkg = text(r.payload); return withCopy(base('app', pkg, [], [{ type: 'open', value: 'https://play.google.com/store/apps/details?id=' + pkg, label: 'Open in Play Store' }])); }
      return withCopy(base('external', typeString(r), [{ label: 'Payload', value: hex(r.payload, ' ') || 'Empty' }]));
    }
    return withCopy(base('raw', r.payload.length ? hex(r.payload, ' ') : 'Empty payload', [{ label: 'Type name format', value: TNF_LABEL[r.tnf] }]));
  }

  // Drafts (the editable form model)
  const DEFAULTS = {
    text: { language: 'en' }, smartPoster: { language: 'en' }, geo: { geoFormat: 'geo' }, address: { addressFormat: 'apple' },
    wifi: { auth: 'wpa2PSK', encryption: 'aes', hidden: 'false' }, bluetooth: { handover: 'false' }, social: { platform: 'instagram' },
    customMIME: { payloadIsHex: 'false' }, external: { payloadIsHex: 'false' }, raw: { tnf: '1', payloadIsHex: 'true' }, unknown: { tnf: '1', payloadIsHex: 'true' },
  };
  const draft = (kind, fields = {}) => ({ id: crypto.randomUUID ? crypto.randomUUID() : String(Math.random()), kind, fields: Object.assign({}, DEFAULTS[kind] || {}, fields) });
  const f = (d, k) => (d.fields[k] || '').trim();
  const withScheme = (u) => (/^[a-z][a-z0-9+.-]*:/i.test(u) ? u : 'https://' + u);
  function validate(d) {
    const need = (k, msg) => (f(d, k) ? null : msg);
    switch (d.kind) {
      case 'text': return need('text', 'Enter some text.');
      case 'url': return need('url', 'Enter a URL.');
      case 'customURI': return need('url', 'Enter a URI.') || (/^[a-z][a-z0-9+.-]*:/i.test(f(d, 'url')) ? null : 'A URI needs a scheme, like myapp: or https:.');
      case 'email': return need('email', 'Enter an email address.') || (/^[^@\s]+@[^@\s]+$/.test(f(d, 'email')) ? null : 'Enter a valid email address.');
      case 'contact': return (f(d, 'firstName') || f(d, 'lastName') || f(d, 'organization')) ? null : 'Enter a name or an organization.';
      case 'phone': case 'sms': return need('phone', 'Enter a phone number.');
      case 'geo': { const a = Number(f(d, 'latitude')), b = Number(f(d, 'longitude')); if (!f(d, 'latitude') || !f(d, 'longitude') || isNaN(a) || isNaN(b)) return 'Enter a latitude and a longitude.'; if (a < -90 || a > 90) return 'Latitude must be between -90 and 90.'; if (b < -180 || b > 180) return 'Longitude must be between -180 and 180.'; return null; }
      case 'address': return need('address', 'Enter an address.');
      case 'wifi': { if (!f(d, 'ssid')) return 'Enter the network name.'; if (f(d, 'auth') !== 'open' && (d.fields.password || '').length < 8) return 'The password must be at least 8 characters.'; return null; }
      case 'bluetooth': return isValidMAC(f(d, 'mac')) ? null : 'Enter an address like AA:BB:CC:DD:EE:FF.';
      case 'social': return need('handle', 'Enter a username.');
      case 'app': return /^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$/i.test(f(d, 'package')) ? null : 'Enter a package name like com.example.app.';
      case 'customMIME': { if (!/^[\w.+-]+\/[\w.+-]+$/.test(f(d, 'mime'))) return 'Enter a MIME type like text/plain.'; if (f(d, 'payloadIsHex') === 'true' && f(d, 'payloadHex') && !isValidHex(f(d, 'payloadHex'))) return 'The payload must be whole bytes in hex.'; return null; }
      case 'external': { if (!f(d, 'domain') || !f(d, 'externalType')) return 'Enter a domain and a type.'; if (f(d, 'payloadIsHex') === 'true' && f(d, 'payloadHex') && !isValidHex(f(d, 'payloadHex'))) return 'The payload must be whole bytes in hex.'; return null; }
      case 'raw': case 'unknown': { for (const k of ['type', 'identifier', 'payloadHex']) if (f(d, k) && !isValidHex(f(d, k))) return 'Hex fields must hold whole bytes.'; return null; }
      default: return null;
    }
  }
  function build(d) {
    const err = validate(d);
    if (err) throw new Error(err);
    const payloadBytes = () => (f(d, 'payloadIsHex') === 'true' ? (fromHex(f(d, 'payloadHex')) || new Uint8Array()) : utf8(d.fields.payloadText || ''));
    switch (d.kind) {
      case 'text': return B.text(d.fields.text, f(d, 'language') || 'en');
      case 'url': return B.uri(withScheme(f(d, 'url')));
      case 'customURI': return B.uri(f(d, 'url'));
      case 'email': return B.email(f(d, 'email'), f(d, 'subject'), d.fields.body || '');
      case 'contact': return B.vcard(Object.fromEntries(VCARD_FIELDS.map((k) => [k, f(d, k)])));
      case 'phone': return B.phone(f(d, 'phone'));
      case 'sms': return B.sms(f(d, 'phone'), d.fields.body || '');
      case 'geo': return B.geo(f(d, 'latitude'), f(d, 'longitude'), f(d, 'geoFormat') || 'geo');
      case 'address': return B.address(f(d, 'address'), f(d, 'addressFormat') || 'apple');
      case 'wifi': return B.wifi({ ssid: f(d, 'ssid'), password: d.fields.password || '', auth: f(d, 'auth') || 'wpa2PSK', encryption: f(d, 'encryption') || 'aes', hidden: f(d, 'hidden') === 'true' });
      case 'bluetooth': return B.bluetooth({ address: normalizeMAC(f(d, 'mac')), name: f(d, 'name') });
      case 'social': return B.social(f(d, 'platform') || 'instagram', f(d, 'handle'));
      case 'app': return B.androidApp(f(d, 'package'));
      case 'customMIME': return B.mime(f(d, 'mime'), payloadBytes());
      case 'external': return B.external(f(d, 'domain'), f(d, 'externalType'), payloadBytes());
      case 'raw': case 'unknown': return B.raw(Number(f(d, 'tnf') || 1) & 7, fromHex(f(d, 'type')) || new Uint8Array(), fromHex(f(d, 'identifier')) || new Uint8Array(), fromHex(f(d, 'payloadHex')) || new Uint8Array());
      case 'smartPoster': return B.smartPoster(withScheme(f(d, 'url')), f(d, 'title'), f(d, 'language') || 'en');
      case 'empty': return B.empty();
      default: return B.empty();
    }
  }
  // One draft can expand into more than one record on the tag. A bluetooth draft with handover on
  // becomes a handover select plus the OOB carrier record (identifier "0"), which is what Android pairs with.
  function buildAll(d) {
    if (d.kind === 'bluetooth' && f(d, 'handover') === 'true') {
      const oob = build(d);
      oob.id = utf8('0');
      return [B.handoverSelect('0'), oob];
    }
    return [build(d)];
  }
  function fromRecord(r) {
    const s = parse(r);
    const rawDraft = () => draft('raw', { tnf: String(r.tnf), type: hex(r.type, ' '), identifier: hex(r.id, ' '), payloadHex: hex(r.payload, ' '), payloadIsHex: 'true' });
    switch (s.kind) {
      case 'empty': return draft('empty');
      case 'text': { const t = parseText(r); return t ? draft('text', { text: t.text, language: t.language }) : draft('text', { text: s.detail }); }
      case 'url': { const u = parseURI(r); return /^https?:\/\//i.test(u) ? draft('url', { url: u }) : draft('customURI', { url: u }); }
      case 'email': { const [to, q = ''] = parseURI(r).slice(7).split('?'); const p = query(q); return draft('email', { email: to, subject: p.subject || '', body: p.body || '' }); }
      case 'phone': return draft('phone', { phone: s.detail });
      case 'sms': { const body = (s.fields.find((x) => x.label === 'Message') || {}).value || ''; return draft('sms', { phone: s.detail, body }); }
      case 'geo': { const u = parseURI(r); const lat = s.fields[0].value, lon = s.fields[1].value; const fmt = u.includes('maps.apple.com') ? 'apple' : u.includes('google.com') ? 'google' : 'geo'; return draft('geo', { latitude: lat, longitude: lon, geoFormat: fmt }); }
      case 'address': { const u = parseURI(r); const fmt = u.startsWith('geo:') ? 'geo' : u.includes('google.com') ? 'google' : 'apple'; return draft('address', { address: s.detail, addressFormat: fmt }); }
      case 'social': { const so = detectSocial(parseURI(r)); return draft('social', { platform: so.platform, handle: so.handle }); }
      case 'contact': { const c = decodeVCard(text(r.payload)); return draft('contact', c); }
      case 'wifi': { const w = decodeWifi(r.payload); return draft('wifi', { ssid: w.ssid, password: w.password, auth: w.auth, encryption: w.encryption, hidden: 'false' }); }
      case 'bluetooth': { const b = decodeBluetooth(r.payload); return draft('bluetooth', { mac: b.address, name: b.name || '' }); }
      case 'app': return draft('app', { package: s.detail });
      case 'smartPoster': { const sp = parseSmartPoster(r); return draft('smartPoster', { url: sp.uri, title: sp.title || '' }); }
      case 'customMIME': return draft('customMIME', { mime: typeString(r), payloadHex: hex(r.payload, ' '), payloadIsHex: 'true' });
      case 'external': { const [domain, ...rest] = typeString(r).split(':'); return draft('external', { domain, externalType: rest.join(':'), payloadHex: hex(r.payload, ' '), payloadIsHex: 'true' }); }
      default: return rawDraft();
    }
  }
  function summary(d) {
    switch (d.kind) {
      case 'text': return f(d, 'text') || 'Empty text';
      case 'url': case 'customURI': case 'smartPoster': return f(d, 'url') || 'No URL';
      case 'email': return f(d, 'email') || 'No address';
      case 'contact': return `${f(d, 'firstName')} ${f(d, 'lastName')}`.trim() || f(d, 'organization') || 'No name';
      case 'phone': case 'sms': return f(d, 'phone') || 'No number';
      case 'geo': return f(d, 'latitude') && f(d, 'longitude') ? `${f(d, 'latitude')}, ${f(d, 'longitude')}` : 'No coordinates';
      case 'address': return f(d, 'address') || 'No address';
      case 'wifi': return f(d, 'ssid') || 'No network name';
      case 'bluetooth': return f(d, 'name') || f(d, 'mac') || 'No address';
      case 'social': return (f(d, 'handle') ? '@' + f(d, 'handle').replace(/^@/, '') : 'No username') + ' on ' + ((SOCIAL.find((s) => s[0] === f(d, 'platform')) || SOCIAL[1])[1]);
      case 'app': return f(d, 'package') || 'No package';
      case 'customMIME': return f(d, 'mime') || 'No MIME type';
      case 'external': return f(d, 'domain') && f(d, 'externalType') ? `${f(d, 'domain')}:${f(d, 'externalType')}` : 'No type';
      case 'raw': case 'unknown': return f(d, 'payloadHex') ? f(d, 'payloadHex').replace(/\s+/g, ' ').toUpperCase() : 'Empty payload';
      case 'empty': return 'Empty record';
      default: return '';
    }
  }
  const draftSize = (d) => { try { return buildAll(d).reduce((n, r) => n + encodedSize(r), 0); } catch (e) { return 0; } };

  return { TNF, TNF_LABEL, URI_PREFIXES, utf8, text, hex, fromHex, normalizeHex, isValidHex, concat, equal, ascii, percentEncode,
    record, typeString, encodedSize, encode, decode, byteCount, tlv, messageFromTLV, abbreviate, expand, build: B,
    encodeWifi, decodeWifi, WIFI_AUTH, WIFI_ENC, encodeBluetooth, decodeBluetooth, isValidMAC, normalizeMAC, encodeVCard, decodeVCard, VCARD_FIELDS, fullName,
    SOCIAL, socialURL, detectSocial, KINDS, kindInfo, WRITABLE, parseText, parseURI, parseSmartPoster, parse,
    draft, validate, buildDraft: build, buildAll, fromRecord, summary, draftSize };
})();
