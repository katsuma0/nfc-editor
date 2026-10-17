// Simulated tags and the tag operations the iOS app performs on them.
// The Type 2 model is an NTAG/Ultralight emulator: pages, lock bits, capability container,
// password pages, counter and signature, driven by the same commands the real app sends.
const SIM = (() => {
  const H = NDEF.hex, FH = NDEF.fromHex, U8 = (...b) => new Uint8Array(b);

  class NFCError extends Error {
    constructor(code, message) { super(message); this.code = code; }
    get isCancellation() { return this.code === 'cancelled'; }
    get title() {
      return { cancelled: 'Cancelled', invalidInput: 'Check the input', notSupportedOnChip: 'Not supported', unsupportedTag: 'Not supported',
        capacityExceeded: 'Too much data', readOnly: 'Read only', authenticationFailed: 'Wrong password' }[this.code] || 'Something went wrong';
    }
    static map(e) {
      if (e instanceof NFCError) return e;
      const m = (e && e.message) || 'Something went wrong.';
      return new NFCError('failed', /[.!?]$/.test(m) ? m : m + '.');
    }
  }
  const E = {
    cancelled: () => new NFCError('cancelled', 'Cancelled.'),
    timeout: () => new NFCError('timeout', 'The session timed out. Try again.'),
    tagLost: () => new NFCError('tagLost', 'The tag was lost. Hold it steady and try again.'),
    unsupportedTag: (r) => new NFCError('unsupportedTag', 'This tag is not supported. ' + r),
    notNDEFFormatted: () => new NFCError('notNDEFFormatted', 'This tag is not NDEF formatted. Use Format memory in Tools first.'),
    readOnly: () => new NFCError('readOnly', 'This tag is read only.'),
    capacity: (n, c) => new NFCError('capacityExceeded', `The data needs ${n} bytes but the tag holds ${c} bytes.`),
    nak: (code) => new NFCError('nak', code == null ? 'The tag refused the command.' : `The tag refused the command (NAK 0x${code.toString(16).toUpperCase().padStart(2, '0')}).`),
    auth: () => new NFCError('authenticationFailed', 'The password was not accepted.'),
    destroyed: () => new NFCError('tagLost', 'The tag did not answer. A destroyed ICODE tag never responds again until you reset the simulated tags.'),
    privacy: () => new NFCError('commandFailed', 'The tag is in privacy mode, so it only answers once the privacy password is presented, and only until it leaves the field. In the web preview, Reset simulated tags in Settings turns privacy mode off.'),
    input: (m) => new NFCError('invalidInput', m),
    chip: (m) => new NFCError('notSupportedOnChip', 'This chip does not support that. ' + m),
    command: (m) => new NFCError('commandFailed', m),
    failed: (m) => new NFCError('failed', m),
    // A protected tag refuses NDEF reads and writes; say so instead of calling it unformatted.
    passwordNeeded: (tag) => new NFCError('commandFailed', tag && tag.isUlC
      ? 'This tag is protected with a 3DES key. Remove the protection with Ultralight C key in Tools first.'
      : 'This tag is password protected. Enter its password in a tool that asks for one, or remove it with the Password tool.'),
    // Format memory cannot help a DESFire card, so point at the tool that can.
    noNDEFApplication: () => new NFCError('notNDEFFormatted', 'This card has no NDEF application. Create one with DESFire card in Tools first.'),
    configLocked: (what) => new NFCError('commandFailed', `The configuration of this tag is locked for good, so ${what} can no longer change.`),
  };
  const pagesWritten = (n) => (n === 0 ? 'No pages were written.' : n === 1 ? '1 page was written before that.' : `${n} pages were written before that.`);
  // Why a tag's NDEF data cannot be reached, as the message the app shows.
  function ndefUnavailable(tag) {
    if (tag.kind === 'type5' && tag.destroyed) return E.destroyed();
    if (tag.kind === 'type5' && tag.loc101) return E.privacy();
    if (tag.kind === 'type2' && tag.passwordBlocked) return E.passwordNeeded(tag);
    if (tag.kind === 'type4') return E.noNDEFApplication();
    return E.notNDEFFormatted();
  }

  // Chip table
  const type2 = (name, family, o) => Object.assign({ name, manufacturer: 'NXP', family, nfcForumType: 2, isoStandard: 'ISO 14443-3A', pageSize: 4,
    supportsPassword: false, supportsCounter: false, counterCount: 0, supportsSignature: false, supportsRawPages: true, atqa: 0x0044, sak: 0x00, notes: null, cc: null, configPage: null, dynamicLockPage: null }, o);
  const CHIPS = {
    ntag213: type2('NTAG213', 'ntag21x', { totalPages: 45, userRange: [4, 39], userMemoryBytes: 144, configPage: 0x29, dynamicLockPage: 0x28, cc: [0xE1, 0x10, 0x12, 0x00], supportsPassword: true, supportsCounter: true, counterCount: 1, supportsSignature: true, version: '0004040201000F03' }),
    ntag215: type2('NTAG215', 'ntag21x', { totalPages: 135, userRange: [4, 129], userMemoryBytes: 504, configPage: 0x83, dynamicLockPage: 0x82, cc: [0xE1, 0x10, 0x3E, 0x00], supportsPassword: true, supportsCounter: true, counterCount: 1, supportsSignature: true, version: '0004040201001103' }),
    ntag216: type2('NTAG216', 'ntag21x', { totalPages: 231, userRange: [4, 225], userMemoryBytes: 888, configPage: 0xE3, dynamicLockPage: 0xE2, cc: [0xE1, 0x10, 0x6D, 0x00], supportsPassword: true, supportsCounter: true, counterCount: 1, supportsSignature: true, version: '0004040201001303' }),
    ul21: type2('MIFARE Ultralight EV1 (MF0UL21)', 'ultralightEV1', { totalPages: 41, userRange: [4, 35], userMemoryBytes: 128, configPage: 0x25, dynamicLockPage: 0x24, cc: [0xE1, 0x10, 0x10, 0x00], supportsPassword: true, supportsCounter: true, counterCount: 3, supportsSignature: true, version: '0004030101000E03' }),
    ntag213tt: type2('NTAG213 TT', 'ntag21x', { totalPages: 45, userRange: [4, 39], userMemoryBytes: 144, configPage: 0x29, dynamicLockPage: 0x28, cc: [0xE1, 0x10, 0x12, 0x00], supportsPassword: true, supportsCounter: true, counterCount: 1, supportsSignature: true, version: '0004040203000F03', tamper: true }),
    ultralightC: type2('MIFARE Ultralight C', 'ultralightC', { totalPages: 48, userRange: [4, 39], userMemoryBytes: 144, cc: [0xE1, 0x10, 0x12, 0x00], supportsRawPages: true, ulcAuth0Page: 0x2A, ulcAuth1Page: 0x2B, ulcKeyPages: [0x2C, 0x2D, 0x2E, 0x2F], version: null }),
    magicNtag216: type2('Magic NTAG216 (writable serial)', 'ntag21x', { totalPages: 231, userRange: [4, 225], userMemoryBytes: 888, configPage: 0xE3, dynamicLockPage: 0xE2, cc: [0xE1, 0x10, 0x6D, 0x00], supportsPassword: true, supportsCounter: true, counterCount: 1, supportsSignature: true, version: '0004040201001303', magicSerial: true }),
    ntag203: type2('NTAG203', 'ntag203', { totalPages: 42, userRange: [4, 39], userMemoryBytes: 144, dynamicLockPage: 0x28, cc: [0xE1, 0x10, 0x12, 0x00], version: null }),
    classic: type2('Unsupported MIFARE tag', 'mifareClassic', { manufacturer: 'Unknown', totalPages: null, userRange: null, userMemoryBytes: null, supportsRawPages: false, atqa: 0x0004, sak: 0x08, notes: 'iOS cannot read this tag. MIFARE Classic is not supported.', version: null }),
    desfire: { name: 'MIFARE DESFire EV1 4K', manufacturer: 'NXP', family: 'desfire', nfcForumType: 4, isoStandard: 'ISO 14443-4A', pageSize: 1, totalPages: null, userRange: null, userMemoryBytes: 4096, freshFreeMemory: 4864, supportsPassword: false, supportsCounter: false, counterCount: 0, supportsSignature: false, supportsRawPages: false, atqa: 0x0344, sak: 0x20, notes: null, cc: null, configPage: null, dynamicLockPage: null },
    desfireEV2: { name: 'MIFARE DESFire EV2 2K', manufacturer: 'NXP', family: 'desfire', nfcForumType: 4, isoStandard: 'ISO 14443-4A', pageSize: 1, totalPages: null, userRange: null, userMemoryBytes: 2048, freshFreeMemory: 2304, supportsPassword: false, supportsCounter: false, counterCount: 0, supportsSignature: false, supportsRawPages: false, atqa: 0x0344, sak: 0x20, notes: null, cc: null, configPage: null, dynamicLockPage: null },
    slix: { name: 'ICODE SLIX', manufacturer: 'NXP', family: 'icodeSLIX', nfcForumType: 5, isoStandard: 'ISO 15693', pageSize: 4, totalPages: 28, userRange: [0, 27], userMemoryBytes: 112, supportsPassword: false, supportsCounter: false, counterCount: 0, supportsSignature: false, supportsRawPages: true, atqa: null, sak: null, notes: null, cc: null, configPage: null, dynamicLockPage: null },
    st25tv: { name: 'ST25TV02K', manufacturer: 'STMicroelectronics', family: 'st25tv', nfcForumType: 5, isoStandard: 'ISO 15693', pageSize: 4, totalPages: 64, userRange: [0, 63], userMemoryBytes: 256, supportsPassword: false, supportsCounter: false, counterCount: 0, supportsSignature: false, supportsRawPages: true, atqa: null, sak: null, notes: null, cc: null, configPage: null, dynamicLockPage: null },
    felica: { name: 'FeliCa (NDEF)', manufacturer: 'Sony', family: 'feliCa', nfcForumType: 3, isoStandard: 'ISO 18092 (JIS X 6319-4)', pageSize: 16, totalPages: null, userRange: null, userMemoryBytes: null, supportsPassword: false, supportsCounter: false, counterCount: 0, supportsSignature: false, supportsRawPages: false, atqa: null, sak: null, notes: null, cc: null, configPage: null, dynamicLockPage: null },
  };
  const chipPages = (c) => ({ cfg0: c.configPage, cfg1: c.configPage == null ? null : c.configPage + 1, pwd: c.configPage == null ? null : c.configPage + 2, pack: c.configPage == null ? null : c.configPage + 3 });
  const isNTAG21x = (c) => c.family === 'ntag21x';
  const isUlC = (c) => c.family === 'ultralightC';
  const hex6 = (n) => (n & 0xFFFFFF).toString(16).toUpperCase().padStart(6, '0');
  // Dynamic lock bits: how many user pages one lock bit covers, where they start and how many bits there are.
  function dynamicLayout(spec) {
    if (spec.dynamicLockPage == null || !spec.userRange) return null;
    const lastUser = spec.userRange[1];
    const pagesPerBit = spec.totalPages >= 128 ? 16 : 2;
    const bitCount = Math.ceil((lastUser - 15) / pagesPerBit);
    return { pagesPerBit, firstPage: 16, bitCount };
  }
  // Lock state as the groups the Lock pages tool shows: static pages 3..15 one per group, then the dynamic groups.
  function lockGroups(tag) {
    const spec = tag.spec, out = [];
    if (!spec.userRange) return out;
    const b2 = tag.pages[2][2], b3 = tag.pages[2][3];
    const staticLocked = (p) => (p === 3 ? (b2 & 0x08) : p <= 7 ? (b2 & (1 << p)) : (b3 & (1 << (p - 8))));
    for (let p = 3; p <= 15 && p <= spec.userRange[1]; p++) out.push({ from: p, to: p, locked: !!staticLocked(p), lockable: true });
    const layout = dynamicLayout(spec);
    if (layout) {
      const d = tag.pages[spec.dynamicLockPage];
      for (let g = 0; g < layout.bitCount; g++) {
        const from = layout.firstPage + g * layout.pagesPerBit;
        const to = Math.min(from + layout.pagesPerBit - 1, spec.userRange[1]);
        out.push({ from, to, locked: !!(d[Math.floor(g / 8)] & (1 << (g % 8))), lockable: true });
      }
    }
    return out;
  }

  // NTAG mirror placeholders and CFG0 MIRROR_CONF codes. "both" is the UID, an "x", then the counter.
  const MIRROR_PLACEHOLDER = { none: '', uid: '0'.repeat(14), counter: '0'.repeat(6), both: '0'.repeat(14) + 'x' + '0'.repeat(6) };
  const MIRROR_CONF = { none: 0, uid: 1, counter: 2, both: 3 };
  // Put the placeholder where "{mirror}" is, or append it, and say where in the URL string it starts.
  function mirroredURL(url, kind) {
    const ph = MIRROR_PLACEHOLDER[kind] || '';
    const at = url.indexOf('{mirror}');
    if (at >= 0) return { fullURL: url.slice(0, at) + ph + url.slice(at + 8), placeholderIndex: at };
    return { fullURL: url + ph, placeholderIndex: url.length };
  }

  // Type 2 emulator
  class Type2Tag {
    constructor(id, name, chipKey, uidHex, setup) {
      this.id = id; this.name = name; this.kind = 'type2'; this.chipKey = chipKey; this.spec = CHIPS[chipKey];
      this.uid = FH(uidHex);
      this.genuine = true; // the originality signature matches NXP's key; a clone sets this false
      this.tamperOpen = false; // NTAG213TT tamper loop, closed from the factory
      this.factory();
      if (setup) setup(this);
      this.authenticated = false;
    }
    factory() {
      const c = this.spec, u = this.uid;
      this.pages = Array.from({ length: c.totalPages }, () => U8(0, 0, 0, 0));
      this.pages[0] = U8(u[0], u[1], u[2], 0x88 ^ u[0] ^ u[1] ^ u[2]);
      this.pages[1] = U8(u[3], u[4], u[5], u[6]);
      this.pages[2] = U8(u[3] ^ u[4] ^ u[5] ^ u[6], 0x48, 0x00, 0x00);
      this.pages[3] = U8(...c.cc);
      this.pages[4] = U8(0x03, 0x00, 0xFE, 0x00);
      if (c.configPage != null) {
        const p = chipPages(c);
        this.pages[p.cfg0] = U8(0x04, 0x00, 0x00, 0xFF);
        this.pages[p.cfg1] = U8(0x00, 0x05, 0x00, 0x00);
        this.pages[p.pwd] = U8(0xFF, 0xFF, 0xFF, 0xFF);
        this.pages[p.pack] = U8(0x00, 0x00, 0x00, 0x00);
      }
      if (isUlC(c)) {
        this.ulcKey = NDEF.utf8('BREAKMEIFYOUCAN!'); // 16 byte 3DES key, kept off the page map like the real chip
        this.pages[c.ulcAuth0Page] = U8(0x30, 0x00, 0x00, 0x00); // AUTH0 = 0x30 means no page is protected
        this.pages[c.ulcAuth1Page] = U8(0x00, 0x00, 0x00, 0x00); // AUTH1 bit 0: 0 protects reads and writes, 1 writes only
      }
      this.password = U8(0xFF, 0xFF, 0xFF, 0xFF);
      this.pack = U8(0x00, 0x00);
      this.counter = 0;
      this.failedAuth = 0;
      this.signature = FH('8D1E7B2C4A5F6E3D9C0B1A2F3E4D5C6B7A8F9E0D1C2B3A4F5E6D7C8B9A0F1E2D');
      this.version = c.version ? FH(c.version) : null;
    }
    get cfg() { return chipPages(this.spec); }
    get isUlC() { return isUlC(this.spec); }
    syncUID() { const a = this.pages[0], b = this.pages[1]; this.uid = U8(a[0], a[1], a[2], b[0], b[1], b[2], b[3]); }
    // The capability container is there but the NDEF pages are behind a password or 3DES key.
    get passwordBlocked() { return this.pages[3][0] === 0xE1 && !!this.spec.userRange && this.protectedRead(this.spec.userRange[0]); }
    get auth0() {
      if (this.isUlC) return this.pages[this.spec.ulcAuth0Page][0];
      return this.cfg.cfg0 == null ? 0xFF : this.pages[this.cfg.cfg0][3];
    }
    get ulcWriteOnly() { return this.isUlC && (this.pages[this.spec.ulcAuth1Page][0] & 0x01) === 0x01; }
    get access() { return this.cfg.cfg1 == null ? 0 : this.pages[this.cfg.cfg1][0]; }
    get prot() { return this.isUlC ? true : (this.access & 0x80) !== 0; }
    get cfgLocked() { return (this.access & 0x40) !== 0; }
    get counterPwdProt() { return (this.access & 0x08) !== 0; }
    get counterEnabled() { return isNTAG21x(this.spec) ? (this.access & 0x10) !== 0 : this.spec.supportsCounter; }
    get authLimit() { return this.access & 0x07; }
    get staticLocked() { return this.pages[2][2] === 0xFF && this.pages[2][3] === 0xFF; }
    get readOnly() { return (this.pages[3][3] & 0x0F) === 0x0F || this.staticLocked; }
    lockedPage(page) {
      if (page < 3 || !this.spec.userRange) return false;
      if (page <= 15) {
        const b2 = this.pages[2][2], b3 = this.pages[2][3];
        if (page === 3) return !!(b2 & 0x08);
        if (page <= 7) return !!(b2 & (1 << page));
        return !!(b3 & (1 << (page - 8)));
      }
      const layout = dynamicLayout(this.spec);
      if (layout && page <= this.spec.userRange[1]) { const g = Math.floor((page - layout.firstPage) / layout.pagesPerBit); const d = this.pages[this.spec.dynamicLockPage]; return !!(d[Math.floor(g / 8)] & (1 << (g % 8))); }
      return false;
    }
    // ICODE-style privacy and NXP mirror both live in the config, so protection for Ultralight C uses AUTH0/AUTH1 directly.
    protectedRead(page) {
      if (this.isUlC) return page >= this.auth0 && !this.ulcWriteOnly && !this.authenticated;
      return page >= this.auth0 && this.prot && !this.authenticated;
    }
    protectedWrite(page) { return page >= this.auth0 && !this.authenticated; }
    // NTAG21x UID and counter mirror. When on, reads of the user pages show the serial number and scan count as ASCII.
    mirror() {
      if (!isNTAG21x(this.spec) || this.cfg.cfg0 == null) return null;
      const cfg0 = this.pages[this.cfg.cfg0];
      const conf = (cfg0[0] >> 6) & 3;
      if (conf === 0) return null;
      const kind = ['none', 'uid', 'counter', 'both'][conf];
      const byte = (cfg0[0] >> 4) & 3, page = cfg0[2];
      const ascii = kind === 'uid' ? H(this.uid) : kind === 'counter' ? hex6(this.counter) : H(this.uid) + 'x' + hex6(this.counter);
      return { kind, page, byte, ascii };
    }
    sessionStart() {
      this.authenticated = false;
      if (this.counterEnabled && this.spec.supportsCounter) this.counter = (this.counter + 1) & 0xFFFFFF;
    }
    readPage(p) {
      if (p >= this.spec.totalPages || p < 0) throw E.nak(0x00);
      if (this.protectedRead(p)) throw E.nak(0x04);
      if (p === this.cfg.pwd || p === this.cfg.pack) return U8(0, 0, 0, 0);
      if (this.isUlC && this.spec.ulcKeyPages.indexOf(p) >= 0) return U8(0, 0, 0, 0); // the 3DES key never reads back
      const m = this.mirror();
      if (m && m.ascii.length) {
        const start = m.page * 4 + m.byte;
        const out = new Uint8Array(this.pages[p]);
        for (let i = 0; i < 4; i++) { const abs = p * 4 + i; if (abs >= start && abs < start + m.ascii.length) out[i] = m.ascii.charCodeAt(abs - start); }
        return out;
      }
      return this.pages[p];
    }
    command(bytes) {
      const cmd = bytes[0];
      const t = this.spec.totalPages;
      if (cmd === 0x60) { if (!this.version) throw E.nak(0x00); return this.version; }
      if (cmd === 0x30) {
        const p = bytes[1]; if (p >= t) throw E.nak(0x00);
        return NDEF.concat(...[0, 1, 2, 3].map((i) => this.readPage((p + i) % t)));
      }
      if (cmd === 0x3A) {
        const s = bytes[1], e = bytes[2]; if (s > e || e >= t) throw E.nak(0x00);
        const out = []; for (let p = s; p <= e; p++) out.push(this.readPage(p)); return NDEF.concat(...out);
      }
      if (cmd === 0xA2) {
        const p = bytes[1]; const data = bytes.slice(2, 6); if (data.length !== 4 || p >= t) throw E.nak(0x00);
        if (p <= 1 && !this.spec.magicSerial) throw E.nak(0x00); // real chips refuse the serial number pages; magic clones accept them
        if (this.lockedPage(p)) throw E.nak(0x00); // the NDEF read only flag blocks NDEF writes only, so raw page writes still work
        if (this.cfgLocked && (p === this.cfg.cfg0 || p === this.cfg.cfg1)) throw E.nak(0x00); // CFGLCK freezes CFG0 and CFG1; PWD and PACK stay writable
        if (this.protectedWrite(p)) throw E.nak(0x04);
        if (p === 2) { this.pages[2] = U8(this.pages[2][0], this.pages[2][1], this.pages[2][2] | data[2], this.pages[2][3] | data[3]); return U8(0x0A); }
        if (p === 3) { this.pages[3] = U8(...[0, 1, 2, 3].map((i) => this.pages[3][i] | data[i])); return U8(0x0A); }
        if (p === this.cfg.pwd) { this.password = data; return U8(0x0A); }
        if (p === this.cfg.pack) { this.pack = data.slice(0, 2); return U8(0x0A); }
        if (p === this.spec.dynamicLockPage) { this.pages[p] = U8(this.pages[p][0] | data[0], this.pages[p][1] | data[1], this.pages[p][2] | data[2], data[3]); return U8(0x0A); }
        // Ultralight C key pages 2C to 2F take the key in this byte order; they never read back.
        if (this.isUlC && this.spec.ulcKeyPages.indexOf(p) >= 0) { const at = [7, 3, 15, 11][p - this.spec.ulcKeyPages[0]]; for (let i = 0; i < 4; i++) this.ulcKey[at - i] = data[i]; return U8(0x0A); }
        this.pages[p] = new Uint8Array(data);
        if (p <= 1) this.syncUID(); // a magic chip takes its serial number from pages 0 and 1
        return U8(0x0A);
      }
      if (cmd === 0x1B) {
        if (!this.spec.supportsPassword) throw E.nak(0x00);
        const pwd = bytes.slice(1, 5);
        if (this.authLimit && this.failedAuth >= this.authLimit) throw E.nak(0x04);
        if (NDEF.equal(pwd, this.password)) { this.authenticated = true; this.failedAuth = 0; return this.pack; }
        if (this.authLimit) this.failedAuth++;
        throw E.nak(0x04);
      }
      if (cmd === 0x3C) { if (!this.spec.supportsSignature) throw E.nak(0x00); return this.signature; }
      if (cmd === 0x39) {
        const a = bytes[1];
        if (!this.spec.supportsCounter) throw E.nak(0x00);
        if (isNTAG21x(this.spec) && (a !== 2 || !this.counterEnabled)) throw E.nak(0x00);
        if (isNTAG21x(this.spec) && this.counterPwdProt && !this.authenticated) throw E.nak(0x04); // NFC_CNT_PWD_PROT
        if (!isNTAG21x(this.spec) && a > 2) throw E.nak(0x00);
        const v = isNTAG21x(this.spec) ? this.counter : this.counter + a;
        return U8(v & 255, (v >> 8) & 255, (v >> 16) & 255);
      }
      throw E.nak(0x00);
    }
    // NDEF reads see the mirror too: the chip overlays the UID or counter ASCII on every read of those bytes.
    userBytes() {
      const [a, b] = this.spec.userRange;
      const bytes = new Uint8Array(NDEF.concat(...this.pages.slice(a, b + 1)));
      const m = this.mirror();
      if (m) { const start = m.page * 4 + m.byte - a * 4; for (let i = 0; i < m.ascii.length; i++) if (start + i >= 0 && start + i < bytes.length) bytes[start + i] = m.ascii.charCodeAt(i); }
      return bytes;
    }
    ndefStatus() {
      if (this.pages[3][0] !== 0xE1) return 'notSupported';
      if (this.protectedRead(this.spec.userRange[0])) return 'notSupported';
      return this.readOnly ? 'readOnly' : 'readWrite';
    }
    ndefCapacity() { return Math.max(0, this.pages[3][2] * 8 - 4); } // a capability container written by hand can say 0
    readNDEF() {
      if (this.ndefStatus() === 'notSupported') throw ndefUnavailable(this);
      const msg = NDEF.messageFromTLV(this.userBytes());
      if (!msg || !msg.length) return [];
      return NDEF.decode(msg);
    }
    writeNDEF(records) {
      const st = this.ndefStatus();
      if (st === 'notSupported') throw ndefUnavailable(this);
      if (st === 'readOnly') throw E.readOnly();
      const bytes = NDEF.tlv(NDEF.encode(records));
      if (bytes.length > this.spec.userMemoryBytes) throw E.capacity(bytes.length - 3, this.ndefCapacity());
      const start = this.spec.userRange[0], last = start + Math.ceil(bytes.length / 4) - 1;
      // Check every page first: a write protected or locked page refuses, and nothing is half written.
      for (let page = start; page <= last; page++) {
        if (this.protectedWrite(page)) throw E.passwordNeeded(this);
        if (this.lockedPage(page)) throw E.command(`Page ${page} is locked, so the records cannot be written there. Locked pages can never be written again.`);
      }
      for (let i = 0; i < bytes.length; i += 4) this.pages[start + i / 4] = U8(bytes[i] || 0, bytes[i + 1] || 0, bytes[i + 2] || 0, bytes[i + 3] || 0);
    }
    writeLock() {
      this.pages[3] = U8(this.pages[3][0], this.pages[3][1], this.pages[3][2], this.pages[3][3] | 0x0F);
      this.pages[2] = U8(this.pages[2][0], this.pages[2][1], 0xFF, 0xFF);
      if (this.spec.dynamicLockPage != null) this.pages[this.spec.dynamicLockPage] = U8(0xFF, 0xFF, 0xFF, this.pages[this.spec.dynamicLockPage][3]);
    }
    serialize() { return { pages: this.pages.map((p) => H(p)), password: H(this.password), pack: H(this.pack), counter: this.counter, failedAuth: this.failedAuth, ulcKey: this.ulcKey ? H(this.ulcKey) : null, tamperOpen: this.tamperOpen }; }
    restore(s) { if (!s || !s.pages || s.pages.length !== this.pages.length) return; this.pages = s.pages.map(FH); this.password = FH(s.password); this.pack = FH(s.pack); this.counter = s.counter || 0; this.failedAuth = s.failedAuth || 0; if (s.ulcKey && this.ulcKey) this.ulcKey = FH(s.ulcKey); this.tamperOpen = !!s.tamperOpen; if (this.spec.magicSerial) this.syncUID(); }
  }

  // Type 4 (DESFire): NDEF application with a CC file and an NDEF file, read through ISO APDUs.
  class Type4Tag {
    constructor(id, name, uidHex, records, opts = {}) {
      this.id = id; this.name = name; this.kind = 'type4'; this.chipKey = opts.chipKey || 'desfire'; this.spec = CHIPS[this.chipKey]; this.uid = FH(uidHex);
      this.hasNDEF = records != null;
      this.records = records || []; this.readOnly = false; this.capacity = opts.capacity || 2048; this.selected = null; this.frame = 0;
      // GetFreeMemory on an empty card: a 2K card reports 2304 bytes, a 4K card 4864.
      this.totalMemory = this.spec.freshFreeMemory || this.spec.userMemoryBytes;
      this.applications = this.hasNDEF ? ['000001'] : [];
      this.masterKey = U8(0, 0, 0, 0, 0, 0, 0, 0); // legacy D40 master key, all zeros from the factory
      this.keySettings = 0x0F; this.maxKeys = 1;
      this.freeMemory = this.hasNDEF ? Math.max(0, this.totalMemory - this.capacity - 32) : this.totalMemory;
      // GetVersion: hardware and software frames (vendor, type, subtype, major, minor, storage size, protocol),
      // then the UID, batch number and production week and year. Major 0x01 is EV1, 0x12 is EV2; storage 0x18 is 4K, 0x16 is 2K.
      const versions = { desfire: ['04010101001805', '04010101041805'], desfireEV2: ['04010112001605', '04010112001605'] }[this.chipKey];
      this.versionFrames = opts.versionFrames || [FH(versions[0]), FH(versions[1]), NDEF.concat(this.uid, FH('BA7C4100001022'))];
      this.historicalBytes = FH('80');
    }
    sessionStart() { this.selected = null; this.frame = 0; }
    ndefFile() { const msg = NDEF.encode(this.records); return NDEF.concat(U8(msg.length >> 8, msg.length & 255), msg); }
    ccFile() { return U8(0x00, 0x0F, 0x20, 0x00, 0xF0, 0x00, 0xF0, 0x04, 0x06, 0xE1, 0x04, this.capacity >> 8, this.capacity & 255, 0x00, this.readOnly ? 0xFF : 0x00); }
    apdu(b) {
      const ok = (data) => ({ data, sw1: 0x90, sw2: 0x00 });
      if (b[0] === 0x90 && b[1] === 0x60) { this.frame = 1; return { data: this.versionFrames[0], sw1: 0x91, sw2: 0xAF }; }
      if (b[0] === 0x90 && b[1] === 0xAF) { if (this.frame === 1) { this.frame = 2; return { data: this.versionFrames[1], sw1: 0x91, sw2: 0xAF }; } if (this.frame === 2) { this.frame = 0; return { data: this.versionFrames[2], sw1: 0x91, sw2: 0x00 }; } return { data: U8(), sw1: 0x91, sw2: 0x1C }; }
      if (b[0] === 0x00 && b[1] === 0xA4 && b[2] === 0x04) { const aid = H(b.slice(5, 5 + b[4])); if (aid === 'D2760000850101' && this.hasNDEF) { this.selected = 'app'; return ok(U8()); } return { data: U8(), sw1: 0x6A, sw2: 0x82 }; }
      if (b[0] === 0x00 && b[1] === 0xA4 && b[2] === 0x00) { const fid = H(b.slice(5, 7)); if (this.selected && fid === 'E103') { this.selected = 'cc'; return ok(U8()); } if (this.selected && fid === 'E104') { this.selected = 'ndef'; return ok(U8()); } return { data: U8(), sw1: 0x6A, sw2: 0x82 }; }
      if (b[0] === 0x00 && b[1] === 0xB0) { const off = (b[2] << 8) | b[3]; const le = b[4] === 0 ? 256 : (b[4] == null ? 256 : b[4]); const file = this.selected === 'cc' ? this.ccFile() : this.selected === 'ndef' ? this.ndefFile() : null; if (!file) return { data: U8(), sw1: 0x69, sw2: 0x86 }; return ok(file.slice(off, off + le)); }
      if (b[0] === 0x90) return { data: U8(), sw1: 0x91, sw2: 0x1C };
      return { data: U8(), sw1: 0x6D, sw2: 0x00 };
    }
    // A native DESFire frame (command byte then data) answers with its status byte first, like 90 cmd 00 00 wrapping.
    native(bytes) { const a = this.apdu(NDEF.concat(U8(0x90, bytes[0], 0, 0), bytes.length > 1 ? U8(bytes.length - 1, ...bytes.slice(1)) : U8(), U8(0))); return NDEF.concat(U8(a.sw2), a.data); }
    ndefStatus() { if (!this.hasNDEF) return 'notSupported'; return this.readOnly ? 'readOnly' : 'readWrite'; }
    ndefCapacity() { return this.capacity; }
    readNDEF() { if (!this.hasNDEF) throw E.noNDEFApplication(); return this.records; }
    writeNDEF(records) { if (!this.hasNDEF) throw E.noNDEFApplication(); if (this.readOnly) throw E.readOnly(); const n = NDEF.byteCount(records); if (n > this.capacity) throw E.capacity(n, this.capacity); this.records = records; }
    writeLock() { if (!this.hasNDEF) throw E.noNDEFApplication(); this.readOnly = true; }
    serialize() { return { records: this.records.map(serializeRecord), readOnly: this.readOnly, hasNDEF: this.hasNDEF, applications: this.applications.slice(), masterKey: H(this.masterKey), keySettings: this.keySettings, maxKeys: this.maxKeys, capacity: this.capacity, freeMemory: this.freeMemory }; }
    restore(s) {
      if (!s) return;
      this.records = (s.records || []).map(restoreRecord); this.readOnly = !!s.readOnly;
      if (typeof s.hasNDEF === 'boolean') this.hasNDEF = s.hasNDEF;
      if (s.applications) this.applications = s.applications.slice();
      if (s.masterKey) this.masterKey = FH(s.masterKey);
      if (s.keySettings != null) this.keySettings = s.keySettings;
      if (s.maxKeys != null) this.maxKeys = s.maxKeys;
      if (s.capacity != null) this.capacity = s.capacity;
      if (s.freeMemory != null) this.freeMemory = s.freeMemory;
    }
  }
  // A legacy DESFire master key is accepted when it is all zeros (8 or 16 bytes) and the card still has its factory key.
  function desfireKeyOk(provided, tag) {
    if (!provided || (provided.length !== 8 && provided.length !== 16)) return false;
    const allZero = Array.from(provided).every((b) => b === 0);
    return allZero && Array.from(tag.masterKey).every((b) => b === 0);
  }

  // Type 5 (ISO 15693): blocks of 4 bytes, capability container in block 0. Models both ICODE SLIX and ST25TV.
  class Type5Tag {
    constructor(id, name, uidHex, records, opts = {}) {
      this.id = id; this.name = name; this.kind = 'type5'; this.chipKey = opts.chipKey || 'slix'; this.spec = CHIPS[this.chipKey]; this.uid = FH(uidHex);
      this.totalBlocks = opts.totalBlocks || this.spec.totalPages;
      this.ndefBlocks = Math.min(this.totalBlocks, 28); // the first 28 blocks carry NDEF; the rest is plain memory
      this.blocks = Array.from({ length: this.totalBlocks }, () => U8(0, 0, 0, 0)); this.locked = new Array(this.totalBlocks).fill(false);
      this.dsfid = 0x00; this.afi = 0x00; this.lockedDSFID = false; this.lockedAFI = false;
      this.isSLIX = !!opts.isSLIX; this.isST = !!opts.isST;
      // SLIX password set, all zeros from the factory: read, write, privacy, destroy and the shared EAS/AFI password.
      this.passwords = { read: U8(0, 0, 0, 0), write: U8(0, 0, 0, 0), privacy: U8(0, 0, 0, 0), destroy: U8(0, 0, 0, 0), easAFI: U8(0, 0, 0, 0) };
      this.stPasswords = [U8(0, 0, 0, 0, 0, 0, 0, 0), U8(0, 0, 0, 0, 0, 0, 0, 0), U8(0, 0, 0, 0, 0, 0, 0, 0)]; // ST config, read, write
      this.privacyOn = false; this.easOn = false; this.destroyed = false;
      this.presented = {}; this.privacyUnlocked = false; // reset each session
      const cap = Math.min(this.ndefBlocks * 4 / 8, 0x7F);
      this.blocks[0] = U8(0xE1, 0x40, cap, 0x00);
      this.writeNDEF(records);
    }
    sessionStart() { this.presented = {}; this.privacyUnlocked = false; }
    get loc101() { return this.privacyOn && !this.privacyUnlocked; } // in privacy mode the tag answers only its UID
    systemInfo() { return { blockSize: 4, totalBlocks: this.totalBlocks, icReference: 0x01, dsfid: this.dsfid, afi: this.afi, uid: this.uid }; }
    readBlock(i) { if (this.destroyed) throw E.destroyed(); if (this.loc101) throw E.privacy(); if (i < 0 || i >= this.totalBlocks) throw E.command('The tag has no block ' + i + '.'); return this.blocks[i]; }
    writeBlock(i, bytes) { if (this.destroyed) throw E.destroyed(); if (this.loc101) throw E.privacy(); if (i < 0 || i >= this.totalBlocks) throw E.command('The tag has no block ' + i + '.'); if (this.locked[i]) throw E.command('Block ' + i + ' is locked.'); if (bytes.length !== 4) throw E.input('Enter exactly 4 bytes.'); this.blocks[i] = new Uint8Array(bytes); }
    lockBlock(i) { this.locked[i] = true; }
    custom(flags, code, params) { if (code === 0x2B) return NDEF.concat(U8(0x00, 0x0F), this.uid.slice().reverse(), U8(this.afi, this.dsfid, this.totalBlocks - 1, 0x03, 0x01)); if (code === 0x20 && params.length) return this.readBlock(params[0]); throw E.command('The tag did not answer command 0x' + code.toString(16).toUpperCase().padStart(2, '0') + '.'); }
    userBytes() { return NDEF.concat(...this.blocks.slice(1, this.ndefBlocks)); }
    ndefCap() { return (this.ndefBlocks - 1) * 4; } // bytes available for the TLV after the capability container
    ndefStatus() { if (this.destroyed || this.loc101) return 'notSupported'; if (this.blocks[0][0] !== 0xE1 && this.blocks[0][0] !== 0xE2) return 'notSupported'; return (this.blocks[0][1] & 0x0F) === 0x0F || this.locked.slice(1, this.ndefBlocks).every(Boolean) ? 'readOnly' : 'readWrite'; }
    ndefCapacity() { return Math.max(0, Math.min(this.blocks[0][2] * 8, this.ndefCap()) - 4); }
    readNDEF() { if (this.ndefStatus() === 'notSupported') throw ndefUnavailable(this); const m = NDEF.messageFromTLV(this.userBytes()); return m && m.length ? NDEF.decode(m) : []; }
    writeNDEF(records) {
      const st = this.ndefStatus(); if (st === 'notSupported') throw ndefUnavailable(this); if (st === 'readOnly') throw E.readOnly();
      const bytes = NDEF.tlv(NDEF.encode(records)); if (bytes.length > this.ndefCap()) throw E.capacity(bytes.length - 3, this.ndefCapacity());
      // A locked block refuses the write, so check them all before writing any.
      for (let b = 1; b <= Math.ceil(bytes.length / 4); b++) if (this.locked[b]) throw E.command(`Block ${b} is locked, so the records cannot be written there. Locked blocks can never be written again.`);
      for (let i = 0; i < bytes.length; i += 4) this.blocks[1 + i / 4] = U8(bytes[i] || 0, bytes[i + 1] || 0, bytes[i + 2] || 0, bytes[i + 3] || 0);
    }
    writeLock() { this.blocks[0] = U8(this.blocks[0][0], (this.blocks[0][1] & 0xF0) | 0x0F, this.blocks[0][2], this.blocks[0][3]); this.locked.fill(true); }
    serialize() { return { blocks: this.blocks.map((b) => H(b)), locked: this.locked, dsfid: this.dsfid, afi: this.afi, lockedDSFID: this.lockedDSFID, lockedAFI: this.lockedAFI, passwords: Object.fromEntries(Object.entries(this.passwords).map(([k, v]) => [k, H(v)])), stPasswords: this.stPasswords.map((p) => H(p)), privacyOn: this.privacyOn, easOn: this.easOn, destroyed: this.destroyed }; }
    restore(s) {
      if (!s || !s.blocks) return;
      this.blocks = s.blocks.map(FH); this.locked = s.locked || this.locked;
      if (s.dsfid != null) this.dsfid = s.dsfid; if (s.afi != null) this.afi = s.afi;
      this.lockedDSFID = !!s.lockedDSFID; this.lockedAFI = !!s.lockedAFI;
      if (s.passwords) for (const k of Object.keys(this.passwords)) if (s.passwords[k]) this.passwords[k] = FH(s.passwords[k]);
      if (s.stPasswords) this.stPasswords = s.stPasswords.map(FH);
      this.privacyOn = !!s.privacyOn; this.easOn = !!s.easOn; this.destroyed = !!s.destroyed;
    }
  }

  // Type 3 (FeliCa)
  class Type3Tag {
    constructor(id, name, idmHex, records) {
      this.id = id; this.name = name; this.kind = 'type3'; this.chipKey = 'felica'; this.spec = CHIPS.felica; this.uid = FH(idmHex);
      this.pmm = FH('01E0000000FFFF00'); this.systemCode = U8(0x12, 0xFC); this.records = records; this.readOnly = false;
      // Two services with four 16-byte blocks each: 0x000B read only, 0x0009 read and write.
      const fill = (label) => Array.from({ length: 4 }, (_, i) => { const b = new Uint8Array(16); NDEF.utf8(`${label} block ${i}`).forEach((c, j) => { if (j < 16) b[j] = c; }); return b; });
      this.services = { 0x000B: { writable: false, blocks: fill('read only') }, 0x0009: { writable: true, blocks: fill('read write') } };
    }
    sessionStart() {}
    felica(packet) { if (packet[0] === 0x0C) return NDEF.concat(U8(0x0D), this.uid, U8(0x01), this.systemCode); if (packet[0] === 0x00) return NDEF.concat(U8(0x01), this.uid, this.pmm); throw E.command('The tag did not answer command 0x' + packet[0].toString(16).toUpperCase().padStart(2, '0') + '.'); }
    ndefStatus() { return this.readOnly ? 'readOnly' : 'readWrite'; }
    ndefCapacity() { return 496; }
    readNDEF() { return this.records; }
    writeNDEF(records) { if (this.readOnly) throw E.readOnly(); const n = NDEF.byteCount(records); if (n > 496) throw E.capacity(n, 496); this.records = records; }
    writeLock() { this.readOnly = true; }
    serialize() { return { records: this.records.map(serializeRecord), readOnly: this.readOnly, services: Object.fromEntries(Object.entries(this.services).map(([k, v]) => [k, { writable: v.writable, blocks: v.blocks.map((b) => H(b)) }])) }; }
    restore(s) { if (!s) return; this.records = (s.records || []).map(restoreRecord); this.readOnly = !!s.readOnly; if (s.services) for (const k of Object.keys(this.services)) if (s.services[k] && s.services[k].blocks) this.services[k].blocks = s.services[k].blocks.map(FH); }
  }

  const unsupportedClassic = () => E.unsupportedTag('iOS cannot read MIFARE Classic tags.');
  class ClassicTag {
    constructor(id, name, uidHex) { this.id = id; this.name = name; this.kind = 'classic'; this.chipKey = 'classic'; this.spec = CHIPS.classic; this.uid = FH(uidHex); }
    sessionStart() {}
    command() { throw E.nak(0x00); }
    ndefStatus() { return 'notSupported'; }
    ndefCapacity() { return 0; }
    readNDEF() { throw unsupportedClassic(); }
    writeNDEF() { throw unsupportedClassic(); }
    writeLock() { throw unsupportedClassic(); }
    serialize() { return {}; }
    restore() {}
  }

  const serializeRecord = (r) => ({ tnf: r.tnf, type: H(r.type), id: H(r.id), payload: H(r.payload) });
  const restoreRecord = (s) => NDEF.record(s.tnf, FH(s.type) || new Uint8Array(), FH(s.payload) || new Uint8Array(), FH(s.id) || new Uint8Array());

  // Catalog of simulated tags. State persists in localStorage so a write shows up on the next read.
  const KEY = 'nfce.simTags.v1';
  const sampleCard = () => NDEF.build.vcard({ firstName: 'Katsuma', lastName: 'Onishi', organization: 'Selvedge denim goods', title: '', phone: '+1 905 555 0142', email: 'hello@example.ca', website: 'https://katsuma.ca', address: 'Markham, Ontario', note: '' });
  function makeCatalog() {
    return [
      new Type2Tag('ntag216-blank', 'NTAG216, blank', 'ntag216', '04583A62956781', null),
      new Type2Tag('ntag213-blank', 'NTAG213, blank', 'ntag213', '041A2B3C4D5E6F', null),
      new Type2Tag('ntag215-link', 'NTAG215 with a link', 'ntag215', '04A1B2C3D4E5F6', (t) => t.writeNDEF([NDEF.build.uri('https://katsuma.ca'), NDEF.build.text('Scanned from a denim card', 'en')])),
      new Type2Tag('ntag216-card', 'NTAG216, contact and Wi-Fi', 'ntag216', '04112233445566', (t) => t.writeNDEF([sampleCard(), NDEF.build.wifi({ ssid: 'Workshop', password: 'indigo2026', auth: 'wpa2PSK', encryption: 'aes' })])),
      new Type2Tag('ntag213-locked', 'NTAG213, locked', 'ntag213', '04778899AABBCC', (t) => { t.writeNDEF([NDEF.build.uri('https://example.com/menu')]); t.writeLock(); }),
      new Type2Tag('ntag215-protected', 'NTAG215, password 12 34 56 78', 'ntag215', '04DEADBEEF0102', (t) => { t.writeNDEF([NDEF.build.text('Protected note', 'en')]); t.password = U8(0x12, 0x34, 0x56, 0x78); t.pack = U8(0xAB, 0xCD); const p = t.cfg; t.pages[p.cfg1] = U8(0x80, 0x05, 0x00, 0x00); t.pages[p.cfg0] = U8(0x04, 0x00, 0x00, 0x04); }),
      new Type2Tag('ntag216-unformatted', 'NTAG216, not formatted', 'ntag216', '04000011112222', (t) => { t.pages[3] = U8(0, 0, 0, 0); t.pages[4] = U8(0, 0, 0, 0); }),
      new Type2Tag('ul21', 'Ultralight EV1 (MF0UL21)', 'ul21', '04C0FFEE010203', (t) => t.writeNDEF([NDEF.build.text('Ultralight', 'en')])),
      new Type2Tag('ntag203', 'NTAG203 (old, no GET_VERSION)', 'ntag203', '04203203203203', (t) => t.writeNDEF([NDEF.build.uri('https://example.com')])),
      new Type2Tag('ntag215-clone', 'NTAG215 clone (fake signature)', 'ntag215', '04BADBADBAD001', (t) => { t.writeNDEF([NDEF.build.uri('https://katsuma.ca')]); t.genuine = false; }),
      new Type2Tag('ntag213tt', 'NTAG213 TT, tamper loop closed', 'ntag213tt', '0413371337AB01', (t) => t.writeNDEF([NDEF.build.text('Tamper evident', 'en')])),
      new Type2Tag('ultralightc', 'Ultralight C, key BREAKMEIFYOUCAN!', 'ultralightC', '04C1C2C3C4C5C6', (t) => t.writeNDEF([NDEF.build.text('3DES protected', 'en')])),
      new Type2Tag('magic-ntag216', 'Magic NTAG216 (writable serial)', 'magicNtag216', '04FACADE000001', (t) => { t.writeNDEF([NDEF.build.uri('https://katsuma.ca')]); t.genuine = false; }), // a clone chip: its signature is not NXP's
      new Type4Tag('desfire', 'DESFire EV1 4K', '04D3F1AE000001', [NDEF.build.uri('https://example.com/desfire')]),
      new Type4Tag('desfire-blank', 'DESFire EV2, blank', '04D3F1AE0000E2', null, { chipKey: 'desfireEV2' }),
      new Type5Tag('slix', 'ICODE SLIX', 'E004010012345678', [NDEF.build.text('Type 5 tag', 'en')], { chipKey: 'slix', isSLIX: true }),
      new Type5Tag('st25tv', 'ST25TV02K', 'E002010087654321', [NDEF.build.text('ST25TV tag', 'en')], { chipKey: 'st25tv', totalBlocks: 64, isST: true }),
      new Type3Tag('felica', 'FeliCa', '01020304050607F8', [NDEF.build.text('FeliCa tag', 'ja')]),
      new ClassicTag('classic', 'MIFARE Classic 1K', 'A1B2C3D4'),
    ];
  }
  let catalog = makeCatalog();
  function load() {
    try {
      const saved = JSON.parse(localStorage.getItem(KEY) || '{}');
      catalog.forEach((t) => t.restore(saved[t.id]));
    } catch (e) { /* a corrupt store just means factory state */ }
  }
  function save() {
    const out = {};
    catalog.forEach((t) => { out[t.id] = t.serialize(); });
    try { localStorage.setItem(KEY, JSON.stringify(out)); } catch (e) { /* storage may be unavailable in private mode */ }
  }
  function reset() { catalog = makeCatalog(); try { localStorage.removeItem(KEY); } catch (e) { /* ignore */ } }
  load();
  const list = () => catalog.map((t) => ({ id: t.id, name: t.name, chip: t.spec.name }));
  const get = (id) => catalog.find((t) => t.id === id) || catalog[0];

  // Tag info and operations (mirror of TagOperations.swift)
  const field = (label, value, icon) => ({ label, value, icon: icon || 'info' });
  const technology = (tag) => ({ type2: 'ISO 14443-3A', classic: 'ISO 14443-3A', type4: 'ISO 14443-4', type5: 'ISO 15693', type3: 'FeliCa (ISO 18092)' })[tag.kind];
  function ndefContent(tag) {
    const status = tag.ndefStatus();
    const c = { status, capacity: status === 'notSupported' ? null : tag.ndefCapacity(), records: [] };
    if (status !== 'notSupported') { try { c.records = tag.readNDEF(); } catch (e) { c.records = []; } }
    return c;
  }
  async function dumpType2(session, tag) {
    const pages = [];
    const total = tag.spec.totalPages;
    for (let p = 0; p < total; p++) {
      try { pages.push({ index: p, bytes: tag.readPage(p), readable: true }); } catch (e) { pages.push({ index: p, bytes: new Uint8Array(), readable: false }); }
      if (p % 32 === 31 || p === total - 1) { session.alertMessage = `Reading page ${p + 1} of ${total}.`; await session.delay(90); }
    }
    return { pageSize: 4, pages, chip: tag.spec, readAt: new Date().toISOString() };
  }
  async function dumpType5(session, tag) {
    const pages = [];
    const total = tag.totalBlocks;
    for (let i = 0; i < total; i++) {
      try { pages.push({ index: i, bytes: tag.readBlock(i), readable: true }); } catch (e) { pages.push({ index: i, bytes: new Uint8Array(4), readable: false }); }
      if (i % 32 === 31 || i === total - 1) { session.alertMessage = `Reading block ${i + 1} of ${total}.`; await session.delay(120); }
    }
    return { pageSize: 4, pages, chip: tag.spec, readAt: new Date().toISOString() };
  }
  function type4Dump(tag) {
    const file = tag.ndefFile();
    const pages = [];
    for (let i = 0; i < file.length; i += 16) pages.push({ index: i / 16, bytes: file.slice(i, i + 16), readable: true });
    return { pageSize: 16, pages, chip: Object.assign({}, tag.spec, { pageSize: 16 }), readAt: new Date().toISOString() };
  }
  const ops = {
    async identify(session, tag) {
      session.alertMessage = 'Identifying the tag.'; await session.delay(250);
      if (tag.kind === 'lostHalfway') throw E.tagLost();
      return { spec: tag.spec, uid: tag.uid };
    },
    async readTag(session, tag, opts = {}) {
      const includeDump = opts.includeDump !== false;
      session.alertMessage = 'Identifying the tag.'; await session.delay(300);
      if (tag.kind === 'type5' && tag.destroyed) throw E.destroyed();
      const info = { id: NDEF.uuid(), scannedAt: new Date().toISOString(), technology: technology(tag), chip: tag.spec, uid: H(tag.uid), ndefStatus: 'unknown', ndefCapacity: null, ndefUsedBytes: null, records: [], passwordProtected: null, counter: null, counterEnabled: null, signature: null, signatureVerdict: null, tamperStatus: null, versionBytes: null, dump: null, extras: [] };
      session.alertMessage = 'Reading records.'; await session.delay(350);
      const c = ndefContent(tag);
      info.ndefStatus = c.status; info.ndefCapacity = c.capacity; info.records = c.records; info.ndefUsedBytes = c.status === 'notSupported' ? null : (c.records.length ? NDEF.byteCount(c.records) : 0);
      if (tag.kind === 'type2') {
        info.versionBytes = tag.version ? H(tag.version) : null;
        if (includeDump) info.dump = await dumpType2(session, tag);
        const header = (() => { try { return NDEF.concat(tag.readPage(0), tag.readPage(1), tag.readPage(2), tag.readPage(3)); } catch (e) { return null; } })();
        if (header) { info.extras.push(field('Static lock bytes', H(header.slice(10, 12), ' '), 'lock')); info.extras.push(field('Capability container', H(header.slice(12, 16), ' '), 'doc')); }
        if (tag.spec.dynamicLockPage != null) { try { info.extras.push(field('Dynamic lock bytes', H(tag.readPage(tag.spec.dynamicLockPage).slice(0, 3), ' '), 'lock')); } catch (e) { /* protected */ } }
        if (tag.cfg.cfg0 != null) {
          try {
            const cfg0 = tag.readPage(tag.cfg.cfg0), cfg1 = tag.readPage(tag.cfg.cfg1);
            const auth0 = cfg0[3], lastPage = tag.spec.totalPages - 1;
            info.passwordProtected = auth0 <= lastPage;
            if (isNTAG21x(tag.spec)) info.counterEnabled = (cfg1[0] & 0x10) !== 0;
            if (info.passwordProtected) { info.extras.push(field('Protected from page', String(auth0), 'lock')); info.extras.push(field('Protection', (cfg1[0] & 0x80) ? 'Read and write' : 'Write only', 'lock')); info.extras.push(field('Wrong attempts allowed', (cfg1[0] & 7) ? String(cfg1[0] & 7) : 'Unlimited', 'lock')); }
          } catch (e) { info.passwordProtected = true; } // config pages are always readable unless a password protects them
        }
        if (tag.spec.supportsCounter) {
          if (isNTAG21x(tag.spec)) { try { const v = tag.command(U8(0x39, 0x02)); info.counter = v[0] | (v[1] << 8) | (v[2] << 16); } catch (e) { /* disabled */ } }
          else for (let a = 0; a < 3; a++) { try { const v = tag.command(U8(0x39, a)); const n = v[0] | (v[1] << 8) | (v[2] << 16); if (info.counter == null) info.counter = n; info.extras.push(field('Counter ' + a, String(n), 'number')); } catch (e) { /* ignore */ } }
        }
        if (tag.spec.supportsSignature) { try { info.signature = H(tag.command(U8(0x3C, 0x00))); info.signatureVerdict = tag.genuine ? 'genuine' : 'notGenuine'; } catch (e) { /* ignore */ } }
        if (isNTAG21x(tag.spec)) { const m = tag.mirror(); info.extras.push(field('Mirror', m ? `${{ uid: 'UID', counter: 'Counter', both: 'UID and counter' }[m.kind]} at page ${m.page}, byte ${m.byte}` : 'Off', 'link')); }
        if (tag.spec.tamper) info.tamperStatus = H(ops.tamperBytes(tag), ' ');
        if (tag.version) info.extras.push(field('GET_VERSION', H(tag.version, ' '), 'info'));
      } else if (tag.kind === 'type4') {
        info.versionBytes = H(NDEF.concat(...tag.versionFrames));
        // Same fields as TagOperations.readTag: major.minor in decimal and the storage size code, from the GetVersion frames.
        const [hw, sw] = tag.versionFrames;
        info.extras.push(field('Historical bytes', H(tag.historicalBytes, ' '), 'info'), field('Hardware version', `${hw[3]}.${hw[4]}`, 'cpu'), field('Storage size code', '0x' + H(hw.slice(5, 6)), 'cpu'), field('Software version', `${sw[3]}.${sw[4]}`, 'cpu'));
        info.extras.push(field('Applications', tag.applications.length ? tag.applications.join(', ') : 'None', 'app'), field('Free memory', tag.freeMemory + ' bytes', 'memorychip'));
        if (includeDump && tag.hasNDEF) { session.alertMessage = 'Reading the NDEF file.'; await session.delay(300); info.dump = type4Dump(tag); }
      } else if (tag.kind === 'type5') {
        const s = tag.systemInfo();
        info.extras.push(field('DSFID', '0x' + s.dsfid.toString(16).toUpperCase().padStart(2, '0'), 'info'), field('AFI', '0x' + s.afi.toString(16).toUpperCase().padStart(2, '0'), 'info'), field('IC reference', '0x01', 'cpu'), field('Blocks', `${s.totalBlocks} blocks of ${s.blockSize} bytes`, 'grid'), field('IC manufacturer code', tag.isST ? '0x02' : '0x04', 'building'));
        const lockedCount = tag.locked.filter(Boolean).length;
        if (lockedCount) info.extras.push(field('Locked blocks', String(lockedCount), 'lock'));
        if (tag.isSLIX) info.extras.push(field('Privacy mode', tag.privacyOn ? 'On' : 'Off', 'lock'), field('EAS', tag.easOn ? 'On' : 'Off', 'info'));
        if (includeDump) info.dump = await dumpType5(session, tag);
      } else if (tag.kind === 'type3') {
        info.extras.push(field('PMm', H(tag.pmm, ' '), 'info'), field('System code', '0x12FC', 'number'));
      }
      return info;
    },
    async writeRecords(session, tag, records, options = {}) {
      if (!records.length) throw E.input('Add at least one record.');
      session.alertMessage = 'Checking the tag.'; await session.delay(250);
      if (tag.kind === 'classic') throw unsupportedClassic();
      let status = tag.ndefStatus();
      if (status === 'notSupported' && tag.kind === 'type2' && tag.spec.cc && tag.pages[3].every((b) => b === 0)) {
        await ops.format(session, tag); status = tag.ndefStatus();
      }
      if (status === 'notSupported') throw ndefUnavailable(tag);
      if (status === 'readOnly') throw E.readOnly();
      const capacity = tag.ndefCapacity();
      const needed = NDEF.byteCount(records);
      if (capacity > 0 && needed > capacity) throw E.capacity(needed, capacity);
      if (options.eraseFirst) { session.alertMessage = 'Erasing.'; await session.delay(250); tag.writeNDEF([]); }
      session.alertMessage = `Writing ${needed} bytes.`; await session.delay(400 + Math.min(needed, 900) / 3);
      tag.writeNDEF(records);
      let verified = null;
      if (options.verifyAfterWrite !== false) { session.alertMessage = 'Verifying.'; await session.delay(300); const back = tag.readNDEF(); if (!NDEF.equal(NDEF.encode(back), NDEF.encode(records))) throw E.failed('The data read back from the tag does not match what was written.'); verified = true; }
      let locked = false;
      if (options.lockAfterWrite) { session.alertMessage = 'Locking the tag.'; await session.delay(300); tag.writeLock(); locked = true; }
      return { bytesWritten: needed, capacity: capacity > 0 ? capacity : null, locked, verified };
    },
    async erase(session, tag, zeroUserMemory) {
      session.alertMessage = 'Checking the tag.'; await session.delay(250);
      if (tag.kind === 'classic') throw unsupportedClassic();
      const status = tag.ndefStatus();
      if (status === 'readOnly') throw E.readOnly();
      if (status === 'notSupported') throw ndefUnavailable(tag);
      session.alertMessage = 'Erasing.'; await session.delay(400);
      // Zeroing checks every page first, so a protected or locked page stops it before anything changes.
      const zeroStop = (unit, n) => E.command(`${unit} ${n} is locked, so the whole user memory cannot be zeroed. Turn off the switch to erase just the records.`);
      if (zeroUserMemory && tag.kind === 'type2') {
        const [a, b] = tag.spec.userRange;
        for (let p = a; p <= b; p++) { if (tag.protectedWrite(p)) throw E.passwordNeeded(tag); if (tag.lockedPage(p)) throw zeroStop('Page', p); }
        for (let p = a + 1; p <= b; p++) tag.pages[p] = U8(0, 0, 0, 0);
        tag.pages[a] = U8(0x03, 0x00, 0xFE, 0x00); return;
      }
      if (zeroUserMemory && tag.kind === 'type5') {
        for (let i = 1; i < tag.ndefBlocks; i++) if (tag.locked[i]) throw zeroStop('Block', i);
        for (let i = 2; i < tag.ndefBlocks; i++) tag.writeBlock(i, U8(0, 0, 0, 0));
        tag.writeBlock(1, U8(0x03, 0x00, 0xFE, 0x00)); return;
      }
      tag.writeNDEF([]);
    },
    async lock(session, tag) {
      session.alertMessage = 'Checking the tag.'; await session.delay(250);
      if (tag.kind === 'classic') throw unsupportedClassic();
      const status = tag.ndefStatus();
      if (status === 'notSupported') throw ndefUnavailable(tag);
      if (status === 'readOnly') throw E.readOnly();
      session.alertMessage = 'Locking the tag.'; await session.delay(400);
      tag.writeLock();
    },
    async format(session, tag) {
      if (tag.kind === 'type2') {
        session.alertMessage = 'Identifying the tag.'; await session.delay(250);
        if (!tag.spec.userRange) throw E.chip(`The memory layout of ${tag.spec.name} is not known, so it cannot be formatted.`);
        session.alertMessage = 'Checking the capability container.'; await session.delay(200);
        const page3 = tag.readPage(3);
        if (page3.every((b) => b === 0)) { session.alertMessage = 'Writing the capability container.'; await session.delay(200); tag.command(U8(0xA2, 3, ...tag.spec.cc)); }
        else if (page3[0] !== 0xE1) throw E.failed('Page 3 holds data that is not a capability container, and it cannot be changed.');
        const [a, b] = tag.spec.userRange;
        // A locked or protected page would refuse halfway; say why before anything is written.
        for (let p = a; p <= b; p++) {
          if (tag.protectedWrite(p)) throw E.passwordNeeded(tag);
          if (tag.lockedPage(p)) throw tag.staticLocked ? E.readOnly() : E.command(`Page ${p} is locked, so the tag cannot be formatted. Locked pages can never be written again.`);
        }
        session.alertMessage = 'Formatting.';
        for (let p = a; p <= b; p++) { tag.command(U8(0xA2, p, ...(p === a ? [0x03, 0x00, 0xFE, 0x00] : [0, 0, 0, 0]))); if (p % 32 === 0) { session.alertMessage = `Writing page ${p - a + 1} of ${b - a + 1}.`; await session.delay(80); } }
        return;
      }
      if (tag.kind === 'type5') {
        if (tag.destroyed) throw E.destroyed();
        if (tag.loc101) throw E.privacy();
        for (let i = 0; i < tag.ndefBlocks; i++) if (tag.locked[i]) throw E.command(`Block ${i} is locked, so the tag cannot be formatted. Locked blocks can never be written again.`);
        session.alertMessage = 'Formatting.'; await session.delay(400);
        tag.writeBlock(0, U8(0xE1, 0x40, 0x0E, 0x00));
        for (let i = 1; i < tag.ndefBlocks; i++) tag.writeBlock(i, i === 1 ? U8(0x03, 0x00, 0xFE, 0x00) : U8(0, 0, 0, 0));
        return;
      }
      throw E.chip('Formatting is only available for Type 2 and Type 5 tags.');
    },
    async readMemory(session, tag, password) {
      if (tag.kind === 'type2') {
        session.alertMessage = 'Identifying the tag.'; await session.delay(250);
        if (!tag.spec.supportsRawPages) throw E.chip(`The memory of ${tag.spec.name} cannot be read by iOS.`);
        if (password) { session.alertMessage = 'Authenticating.'; await session.delay(200); authenticate(tag, password); }
        return dumpType2(session, tag);
      }
      if (tag.kind === 'type5') {
        session.alertMessage = 'Identifying the tag.'; await session.delay(250);
        // The memory editor starts with Get System Info, which a destroyed tag or one in privacy mode never answers.
        if (tag.destroyed) throw E.destroyed();
        if (tag.loc101) throw E.privacy();
        return dumpType5(session, tag);
      }
      if (tag.kind === 'type4') { session.alertMessage = 'Reading the NDEF file.'; await session.delay(400); return type4Dump(tag); }
      if (tag.kind === 'classic') throw E.chip('The memory of this tag cannot be read by iOS.');
      throw E.chip('Reading raw memory is not supported on FeliCa tags.');
    },
    async writePage(session, tag, index, bytes, password) {
      if (tag.kind === 'type2') {
        if (bytes.length !== 4) throw E.input('Enter exactly 4 bytes.');
        if (password) { session.alertMessage = 'Authenticating.'; await session.delay(200); authenticate(tag, password); }
        session.alertMessage = `Writing page ${index}.`; await session.delay(300);
        try { tag.command(U8(0xA2, index, ...bytes)); } catch (e) { throw refusedWrite(tag, index, e); }
        return;
      }
      if (tag.kind === 'type5') { session.alertMessage = `Writing block ${index}.`; await session.delay(300); tag.writeBlock(index, bytes); return; }
      throw E.chip('Writing single pages is only available for Type 2 and Type 5 tags.');
    },
    async writeDump(session, tag, dump, range, password, includeSerialPages) {
      if (tag.kind !== 'type2' && tag.kind !== 'type5') throw E.chip('Writing a memory dump is only available for Type 2 and Type 5 tags.');
      session.alertMessage = 'Identifying the tag.'; await session.delay(250);
      if (dump.pageSize !== 4) throw E.input('The dump must use 4-byte pages for this tag.');
      const target = range || tag.spec.userRange;
      let pages = dump.pages.filter((p) => p.readable && p.bytes.length === 4 && p.index >= target[0] && p.index <= target[1]);
      if (!includeSerialPages) pages = pages.filter((p) => p.index > 1); // the serial number pages only go in when asked, and only magic chips accept them
      if (!pages.length) throw E.input('The dump has no pages in the selected range.');
      if (password && tag.kind === 'type2') { session.alertMessage = 'Authenticating.'; await session.delay(200); authenticate(tag, password); }
      let written = 0;
      for (const p of pages) {
        session.alertMessage = `Writing page ${p.index} (${written + 1} of ${pages.length}).`;
        if (written % 16 === 0) await session.delay(90);
        try { if (tag.kind === 'type2') tag.command(U8(0xA2, p.index, ...p.bytes)); else tag.writeBlock(p.index, p.bytes); }
        catch (e) { if (e.code === 'nak') throw E.command(`The tag refused page ${p.index}. ${refusalReason(tag, p.index, e)}${pagesWritten(written)}`); throw e; }
        written++;
      }
      return written;
    },
    async setPassword(session, tag, config) {
      if (tag.kind !== 'type2' || !tag.spec.supportsPassword) throw E.chip('Passwords are only available on NTAG and Ultralight EV1 tags.');
      if (config.password.length !== 4) throw E.input('The password must be 4 bytes.');
      if (config.pack.length !== 2) throw E.input('The PACK must be 2 bytes.');
      session.alertMessage = 'Identifying the tag.'; await session.delay(250);
      if (config.currentPassword) { session.alertMessage = 'Authenticating.'; await session.delay(200); authenticate(tag, config.currentPassword); }
      const cfg = tag.cfg;
      const cfg0 = Array.from(readConfig(tag, cfg.cfg0)), cfg1 = Array.from(readConfig(tag, cfg.cfg1));
      // CFGLCK freezes CFG0 and CFG1. Stop before PWD and PACK change, or the tag would take a new password it never asks for.
      if (cfg1[0] & 0x40) throw E.configLocked('the protected pages and the protection mode');
      session.alertMessage = 'Setting the password.'; await session.delay(400);
      tag.command(U8(0xA2, cfg.pwd, ...config.password));
      tag.command(U8(0xA2, cfg.pack, config.pack[0], config.pack[1], 0, 0));
      cfg1[0] = (cfg1[0] & 0x78) | (config.protectReads ? 0x80 : 0) | (config.authLimit & 7);
      tag.command(U8(0xA2, cfg.cfg1, ...cfg1));
      cfg0[3] = config.protectFromPage;
      tag.command(U8(0xA2, cfg.cfg0, ...cfg0));
    },
    async removePassword(session, tag, current) {
      if (tag.kind !== 'type2' || !tag.spec.supportsPassword) throw E.chip('Passwords are only available on NTAG and Ultralight EV1 tags.');
      session.alertMessage = 'Identifying the tag.'; await session.delay(250);
      session.alertMessage = 'Authenticating.'; await session.delay(250); authenticate(tag, current);
      const cfg = tag.cfg;
      const cfg0 = Array.from(readConfig(tag, cfg.cfg0)), cfg1 = Array.from(readConfig(tag, cfg.cfg1));
      if (cfg1[0] & 0x40) throw E.configLocked('the password protection');
      session.alertMessage = 'Removing the password.'; await session.delay(300);
      cfg1[0] &= 0x78; tag.command(U8(0xA2, cfg.cfg1, ...cfg1));
      cfg0[3] = 0xFF; tag.command(U8(0xA2, cfg.cfg0, ...cfg0));
    },
    async readCounter(session, tag, address) {
      if (tag.kind !== 'type2') throw E.chip('Counters are only available on NTAG and Ultralight EV1 tags.');
      session.alertMessage = 'Identifying the tag.'; await session.delay(250);
      if (!tag.spec.supportsCounter) throw E.chip(`${tag.spec.name} has no counter.`);
      session.alertMessage = 'Reading the counter.'; await session.delay(250);
      try { const v = tag.command(U8(0x39, address)); return v[0] | (v[1] << 8) | (v[2] << 16); }
      catch (e) { if (e.code === 'nak') throw E.command('The tag refused to show the counter. It may be disabled or password protected.'); throw e; }
    },
    async setCounter(session, tag, enabled, passwordProtected, password) {
      if (tag.kind !== 'type2' || !isNTAG21x(tag.spec)) throw E.chip('Counters can only be switched on NTAG tags.');
      session.alertMessage = 'Identifying the tag.'; await session.delay(250);
      if (password) { session.alertMessage = 'Authenticating.'; await session.delay(200); authenticate(tag, password); }
      const cfg1 = Array.from(readConfig(tag, tag.cfg.cfg1));
      if (cfg1[0] & 0x40) throw E.configLocked('the counter settings');
      session.alertMessage = enabled ? 'Enabling the counter.' : 'Disabling the counter.'; await session.delay(300);
      cfg1[0] = enabled ? cfg1[0] | 0x10 : cfg1[0] & 0xEF;
      if (passwordProtected === true) cfg1[0] |= 0x08; // NFC_CNT_PWD_PROT
      else if (passwordProtected === false) cfg1[0] &= 0xF7; // leaving it null keeps the current setting
      tag.command(U8(0xA2, tag.cfg.cfg1, ...cfg1));
    },
    async readSignature(session, tag) {
      if (tag.kind !== 'type2') throw E.chip('Signatures are only available on NTAG and Ultralight EV1 tags.');
      session.alertMessage = 'Identifying the tag.'; await session.delay(250);
      if (!tag.spec.supportsSignature) throw E.chip(`${tag.spec.name} has no originality signature.`);
      session.alertMessage = 'Reading the signature.'; await session.delay(300);
      return H(tag.command(U8(0x3C, 0x00)));
    },
    // Verify the originality signature against NXP's public key. The simulator carries a genuine flag per tag
    // instead of running ECDSA, so the verdict is the flag; chips with no signature report no key.
    async verifySignature(session, tag) {
      if (tag.kind !== 'type2') throw E.chip('Signatures are only available on NTAG and Ultralight EV1 tags.');
      session.alertMessage = 'Identifying the tag.'; await session.delay(250);
      if (!tag.spec.supportsSignature) return 'noKey';
      session.alertMessage = 'Reading the signature.'; await session.delay(300);
      tag.command(U8(0x3C, 0x00));
      session.alertMessage = 'Verifying against NXP’s key.'; await session.delay(400);
      return tag.genuine ? 'genuine' : 'notGenuine';
    },

    // NTAG mirror. The URL is written with a placeholder and CFG0 points at it; on every read the chip overlays the UID or counter.
    mirroredURL,
    async writeMirroredURL(session, tag, url, kind, password) {
      if (tag.kind !== 'type2' || !isNTAG21x(tag.spec)) throw E.chip('The UID and counter mirror is only on NTAG21x tags.');
      if (MIRROR_CONF[kind] == null) throw E.input('Choose what to mirror.');
      session.alertMessage = 'Identifying the tag.'; await session.delay(250);
      if (password) { session.alertMessage = 'Authenticating.'; await session.delay(200); authenticate(tag, password); }
      // Check CFGLCK first: with the configuration locked the link would be written but the mirror never switched on.
      if (readConfig(tag, tag.cfg.cfg1)[0] & 0x40) throw E.configLocked('the mirror settings');
      const m = mirroredURL(url, kind);
      const rec = NDEF.build.uri(m.fullURL);
      const message = NDEF.encode([rec]);
      const prefixLength = NDEF.URI_PREFIXES[NDEF.abbreviate(m.fullURL).code].length;
      const tlvHeaderLength = message.length < 255 ? 2 : 4;
      const offset = tlvHeaderLength + 5 + (m.placeholderIndex - prefixLength);
      const page = 4 + Math.floor(offset / 4), byte = offset % 4;
      const ph = MIRROR_PLACEHOLDER[kind];
      if (kind !== 'none') {
        const lastPage = 4 + Math.floor((offset + ph.length - 1) / 4);
        if (page < 4 || lastPage > tag.spec.userRange[1] - 1) throw E.input('The mirror does not fit on this tag. Shorten the URL.');
      }
      session.alertMessage = `Writing ${message.length + 3} bytes.`; await session.delay(400);
      tag.writeNDEF([rec]);
      session.alertMessage = 'Setting the mirror configuration.'; await session.delay(300);
      const cfg0 = Array.from(readConfig(tag, tag.cfg.cfg0));
      cfg0[0] = (cfg0[0] & 0x0F) | (MIRROR_CONF[kind] << 6) | ((byte & 3) << 4);
      cfg0[2] = page;
      tag.command(U8(0xA2, tag.cfg.cfg0, ...cfg0));
      if (kind === 'counter' || kind === 'both') { const cfg1 = Array.from(readConfig(tag, tag.cfg.cfg1)); cfg1[0] |= 0x10; tag.command(U8(0xA2, tag.cfg.cfg1, ...cfg1)); }
      return m.fullURL;
    },
    async readMirror(session, tag) {
      if (tag.kind !== 'type2' || !isNTAG21x(tag.spec)) throw E.chip('The mirror is only on NTAG21x tags.');
      session.alertMessage = 'Reading the mirror setting.'; await session.delay(300);
      const cfg0 = readConfig(tag, tag.cfg.cfg0);
      return { kind: ['none', 'uid', 'counter', 'both'][(cfg0[0] >> 6) & 3], page: cfg0[2], byte: (cfg0[0] >> 4) & 3 };
    },
    async disableMirror(session, tag, password) {
      if (tag.kind !== 'type2' || !isNTAG21x(tag.spec)) throw E.chip('The mirror is only on NTAG21x tags.');
      session.alertMessage = 'Identifying the tag.'; await session.delay(250);
      if (password) { session.alertMessage = 'Authenticating.'; await session.delay(200); authenticate(tag, password); }
      session.alertMessage = 'Turning the mirror off.'; await session.delay(300);
      if (readConfig(tag, tag.cfg.cfg1)[0] & 0x40) throw E.configLocked('the mirror settings');
      const cfg0 = Array.from(readConfig(tag, tag.cfg.cfg0));
      cfg0[0] = cfg0[0] & 0x0F;
      tag.command(U8(0xA2, tag.cfg.cfg0, ...cfg0));
    },

    // Lock bits (single pages and page groups), static and dynamic.
    async lockState(session, tag) {
      if (tag.kind !== 'type2' || !tag.spec.userRange) throw E.chip('Lock bits are only on NTAG and Ultralight tags.');
      session.alertMessage = 'Reading the lock state.'; await session.delay(300);
      return lockGroups(tag);
    },
    async lockPages(session, tag, groups, password) {
      if (tag.kind !== 'type2' || !tag.spec.userRange) throw E.chip('Lock bits are only on NTAG and Ultralight tags.');
      session.alertMessage = 'Identifying the tag.'; await session.delay(250);
      if (password) { session.alertMessage = 'Authenticating.'; await session.delay(200); authenticate(tag, password); }
      const layout = dynamicLayout(tag.spec);
      let b2 = 0, b3 = 0; const dyn = [0, 0, 0];
      for (const g of (groups || [])) {
        if (!g.locked) continue;
        if (g.from <= 15) { const p = g.from; if (p === 3) b2 |= 0x08; else if (p <= 7) b2 |= (1 << p); else b3 |= (1 << (p - 8)); }
        else if (layout) { const gi = Math.round((g.from - layout.firstPage) / layout.pagesPerBit); dyn[Math.floor(gi / 8)] |= (1 << (gi % 8)); }
      }
      session.alertMessage = 'Locking the chosen pages.'; await session.delay(400);
      if (b2 || b3) tag.command(U8(0xA2, 2, 0, 0, b2, b3));
      if ((dyn[0] || dyn[1]) && tag.spec.dynamicLockPage != null) { const d = tag.pages[tag.spec.dynamicLockPage]; tag.command(U8(0xA2, tag.spec.dynamicLockPage, dyn[0], dyn[1], 0, d[3])); }
      return lockGroups(tag);
    },

    // NDEF read only flag (CC byte 3 on Type 2, CC nibble on Type 5). Raw page writes still work afterwards.
    async setNDEFReadOnlyFlag(session, tag) {
      if (tag.kind === 'type2') {
        session.alertMessage = 'Identifying the tag.'; await session.delay(250);
        if (tag.pages[3][0] !== 0xE1) throw E.notNDEFFormatted();
        if (tag.ndefStatus() === 'readOnly') throw E.readOnly();
        session.alertMessage = 'Setting the read only flag.'; await session.delay(300);
        tag.command(U8(0xA2, 3, 0, 0, 0, 0x0F));
        return;
      }
      if (tag.kind === 'type5') {
        if (tag.ndefStatus() === 'readOnly') throw E.readOnly();
        session.alertMessage = 'Setting the read only flag.'; await session.delay(300);
        const b0 = tag.readBlock(0); tag.writeBlock(0, U8(b0[0], (b0[1] & 0xF0) | 0x0F, b0[2], b0[3]));
        return;
      }
      throw E.chip('The NDEF read only flag is only on Type 2 and Type 5 tags.');
    },

    // Config lock (CFGLCK): afterwards the configuration, password and PACK pages refuse writes.
    async lockConfiguration(session, tag, password) {
      if (tag.kind !== 'type2' || tag.cfg.cfg1 == null) throw E.chip('The configuration lock is only on NTAG and Ultralight EV1 tags.');
      session.alertMessage = 'Identifying the tag.'; await session.delay(250);
      if (password) { session.alertMessage = 'Authenticating.'; await session.delay(200); authenticate(tag, password); }
      session.alertMessage = 'Locking the configuration.'; await session.delay(300);
      const cfg1 = Array.from(readConfig(tag, tag.cfg.cfg1));
      if (cfg1[0] & 0x40) throw E.command('The configuration of this tag is already locked.');
      cfg1[0] |= 0x40;
      tag.command(U8(0xA2, tag.cfg.cfg1, ...cfg1));
    },

    // NTAG213TT tamper loop.
    // READ_TT_STATUS answers the 4-byte TT message, then the status byte: C (0x43) closed loop, O (0x4F) open, I (0x49) not determined.
    tamperBytes(tag) { return U8(0x00, 0x00, 0x00, 0x00, tag.tamperOpen ? 0x4F : 0x43); },
    async readTamperStatus(session, tag) {
      if (tag.kind !== 'type2' || !tag.spec.tamper) throw E.chip('A tamper status is only on NTAG213 TT tags.');
      session.alertMessage = 'Reading the tamper status.'; await session.delay(300);
      return ops.tamperBytes(tag);
    },
    async setTamperStatus(session, tag, opened) {
      if (tag.kind !== 'type2' || !tag.spec.tamper) throw E.chip('A tamper status is only on NTAG213 TT tags.');
      session.alertMessage = opened ? 'Opening the tamper loop.' : 'Closing the tamper loop.'; await session.delay(300);
      tag.tamperOpen = !!opened;
    },

    // Ultralight C: 3DES authentication is faked by comparing the 16 byte key.
    async ultralightCAuthenticate(session, tag, key) {
      if (tag.kind !== 'type2' || !tag.isUlC) throw E.chip('3DES authentication is only on Ultralight C tags.');
      if (key.length !== 16) throw E.input('The key must be 16 bytes.');
      session.alertMessage = 'Authenticating.'; await session.delay(400);
      if (!NDEF.equal(key, tag.ulcKey)) throw E.auth();
      tag.authenticated = true;
      return true;
    },
    async ultralightCSetKey(session, tag, currentKey, newKey, firstPage, writeOnly) {
      if (tag.kind !== 'type2' || !tag.isUlC) throw E.chip('3DES authentication is only on Ultralight C tags.');
      if (newKey.length !== 16) throw E.input('The new key must be 16 bytes.');
      session.alertMessage = 'Authenticating.'; await session.delay(300);
      if (!NDEF.equal(currentKey, tag.ulcKey)) throw E.auth();
      tag.authenticated = true;
      session.alertMessage = 'Setting the key and protection.'; await session.delay(400);
      tag.ulcKey = new Uint8Array(newKey);
      tag.pages[tag.spec.ulcAuth0Page] = U8(firstPage & 0xFF, 0, 0, 0);
      tag.pages[tag.spec.ulcAuth1Page] = U8(writeOnly ? 1 : 0, 0, 0, 0);
    },
    async ultralightCRemoveProtection(session, tag, key) {
      if (tag.kind !== 'type2' || !tag.isUlC) throw E.chip('3DES authentication is only on Ultralight C tags.');
      session.alertMessage = 'Authenticating.'; await session.delay(300);
      if (!NDEF.equal(key, tag.ulcKey)) throw E.auth();
      tag.authenticated = true;
      session.alertMessage = 'Removing the protection.'; await session.delay(300);
      tag.pages[tag.spec.ulcAuth0Page] = U8(0x30, 0, 0, 0);
    },

    // DESFire overview, format and NDEF application creation.
    async desfireOverview(session, tag) {
      if (tag.kind !== 'type4') throw E.chip('DESFire commands need an ISO 14443-4 tag.');
      session.alertMessage = 'Reading the card.'; await session.delay(300);
      session.alertMessage = 'Listing applications.'; await session.delay(250);
      return { version: H(NDEF.concat(...tag.versionFrames)), applications: tag.applications.slice(), freeMemory: tag.freeMemory, keySettings: tag.keySettings, maxKeys: tag.maxKeys, hasNDEFApplication: tag.hasNDEF };
    },
    async desfireFormat(session, tag, masterKey) {
      if (tag.kind !== 'type4') throw E.chip('DESFire commands need an ISO 14443-4 tag.');
      session.alertMessage = 'Identifying the tag.'; await session.delay(250);
      session.alertMessage = 'Authenticating with the master key.'; await session.delay(300);
      if (!desfireKeyOk(masterKey, tag)) throw new NFCError('authenticationFailed', 'The card did not accept the master key.');
      session.alertMessage = 'Formatting the card.'; await session.delay(500);
      tag.applications = []; tag.hasNDEF = false; tag.records = []; tag.freeMemory = tag.totalMemory;
    },
    async desfireCreateNDEFApplication(session, tag, masterKey, formatFirst, ndefFileSize) {
      if (tag.kind !== 'type4') throw E.chip('DESFire commands need an ISO 14443-4 tag.');
      if (!(ndefFileSize > 0)) throw E.input('Choose an NDEF file size.');
      session.alertMessage = 'Selecting the master application.'; await session.delay(250);
      session.alertMessage = 'Authenticating with the master key.'; await session.delay(300);
      if (!desfireKeyOk(masterKey, tag)) throw new NFCError('authenticationFailed', 'The card did not accept the master key.');
      if (formatFirst) { session.alertMessage = 'Formatting the card.'; await session.delay(400); tag.applications = []; tag.hasNDEF = false; tag.records = []; tag.freeMemory = tag.totalMemory; }
      if (tag.hasNDEF) throw E.command('The card already has an NDEF application.');
      session.alertMessage = 'Creating application 000001.'; await session.delay(300);
      // The 15 byte CC file takes one 32 byte block next to the NDEF file, the same margin DESFireToolView warns about.
      // A card without room answers 0E, out of EEPROM, at CreateStdDataFile.
      if (ndefFileSize + 32 > tag.freeMemory) {
        const fits = Math.floor((tag.freeMemory - 32) / 256) * 256;
        throw E.command(`The card is out of memory (status 0E). It has ${tag.freeMemory} bytes free, ` + (fits >= 256 ? `so choose an NDEF file of at most ${fits} bytes.` : 'which is not enough for an NDEF file. Format the card first.'));
      }
      session.alertMessage = 'Creating the CC and NDEF files.'; await session.delay(300);
      tag.applications = Array.from(new Set(['000001', ...tag.applications]));
      tag.hasNDEF = true; tag.capacity = ndefFileSize; tag.records = [];
      tag.freeMemory = Math.max(0, tag.freeMemory - ndefFileSize - 32);
    },

    // Type 5 settings: AFI, DSFID, block locks, and the ICODE SLIX and ST25TV password commands.
    async type5Settings(session, tag) {
      if (tag.kind !== 'type5') throw E.chip('Type 5 settings are only on ISO 15693 tags.');
      if (tag.destroyed) throw E.destroyed();
      if (tag.loc101) throw E.privacy();
      session.alertMessage = 'Reading settings.'; await session.delay(300);
      return { dsfid: tag.dsfid, afi: tag.afi, blockSize: 4, totalBlocks: tag.totalBlocks, lockedBlocks: tag.locked.slice(), isSLIX: tag.isSLIX, isST: tag.isST };
    },
    async type5WriteAFI(session, tag, afi, lock) {
      if (tag.kind !== 'type5') throw E.chip('The AFI is only on ISO 15693 tags.');
      if (tag.destroyed) throw E.destroyed();
      if (tag.loc101) throw E.privacy(); // in privacy mode the tag only answers GET RANDOM NUMBER and SET PASSWORD
      if (tag.lockedAFI) throw E.command('The AFI is locked and cannot be changed.');
      session.alertMessage = 'Writing the AFI.'; await session.delay(300);
      tag.afi = afi & 0xFF; if (lock) tag.lockedAFI = true;
    },
    async type5WriteDSFID(session, tag, dsfid, lock) {
      if (tag.kind !== 'type5') throw E.chip('The DSFID is only on ISO 15693 tags.');
      if (tag.destroyed) throw E.destroyed();
      if (tag.loc101) throw E.privacy(); // in privacy mode the tag only answers GET RANDOM NUMBER and SET PASSWORD
      if (tag.lockedDSFID) throw E.command('The DSFID is locked and cannot be changed.');
      session.alertMessage = 'Writing the DSFID.'; await session.delay(300);
      tag.dsfid = dsfid & 0xFF; if (lock) tag.lockedDSFID = true;
    },
    async type5LockBlocks(session, tag, blocks) {
      if (tag.kind !== 'type5') throw E.chip('Block locks are only on ISO 15693 tags.');
      if (tag.destroyed) throw E.destroyed();
      if (tag.loc101) throw E.privacy(); // in privacy mode the tag only answers GET RANDOM NUMBER and SET PASSWORD
      session.alertMessage = 'Locking blocks.'; await session.delay(300);
      for (const b of (blocks || [])) { if (b < 0 || b >= tag.totalBlocks) throw E.input('Block ' + b + ' is out of range.'); tag.lockBlock(b); }
      return tag.locked.slice();
    },
    async slixSetPassword(session, tag, identifier, currentPassword, newPassword) {
      if (tag.kind !== 'type5' || !tag.isSLIX) throw E.chip('SLIX passwords are only on ICODE SLIX tags.');
      if (tag.destroyed) throw E.destroyed();
      if (!(identifier in tag.passwords)) throw E.input('Unknown password identifier.');
      if (newPassword.length !== 4) throw E.input('The password must be 4 bytes.');
      session.alertMessage = 'Authenticating.'; await session.delay(250);
      if (currentPassword) { if (!NDEF.equal(currentPassword, tag.passwords[identifier])) throw E.auth(); }
      else if (!NDEF.equal(tag.passwords[identifier], U8(0, 0, 0, 0))) throw E.input('Enter the current password first.');
      tag.presented[identifier] = true;
      session.alertMessage = 'Setting the password.'; await session.delay(300);
      tag.passwords[identifier] = new Uint8Array(newPassword);
    },
    async slixPresentPassword(session, tag, identifier, password) {
      if (tag.kind !== 'type5' || !tag.isSLIX) throw E.chip('SLIX passwords are only on ICODE SLIX tags.');
      if (tag.destroyed) throw E.destroyed();
      if (!(identifier in tag.passwords)) throw E.input('Unknown password identifier.');
      if (password.length !== 4) throw E.input('The password must be 4 bytes.');
      session.alertMessage = 'Presenting the password.'; await session.delay(300);
      if (!NDEF.equal(password, tag.passwords[identifier])) throw E.auth();
      tag.presented[identifier] = true;
      if (identifier === 'privacy') tag.privacyUnlocked = true;
    },
    async slixSetPrivacy(session, tag, enabled, password) {
      if (tag.kind !== 'type5' || !tag.isSLIX) throw E.chip('Privacy mode is only on ICODE SLIX tags.');
      if (tag.destroyed) throw E.destroyed();
      if (password.length !== 4) throw E.input('The privacy password must be 4 bytes.');
      session.alertMessage = 'Presenting the privacy password.'; await session.delay(300);
      if (!NDEF.equal(password, tag.passwords.privacy)) throw E.auth();
      tag.privacyUnlocked = true;
      session.alertMessage = enabled ? 'Enabling privacy mode.' : 'Leaving privacy mode.'; await session.delay(300);
      // Presenting the privacy password only lifts privacy until the tag loses power, so privacyOn stays set
      // and the next session starts hidden again.
      if (enabled) tag.privacyOn = true;
    },
    async slixSetEAS(session, tag, enabled) {
      if (tag.kind !== 'type5' || !tag.isSLIX) throw E.chip('EAS is only on ICODE SLIX tags.');
      if (tag.destroyed) throw E.destroyed();
      if (tag.loc101) throw E.privacy(); // in privacy mode the tag only answers GET RANDOM NUMBER and SET PASSWORD
      session.alertMessage = enabled ? 'Setting EAS.' : 'Resetting EAS.'; await session.delay(300);
      tag.easOn = !!enabled;
    },
    async slixEASAlarm(session, tag) {
      if (tag.kind !== 'type5' || !tag.isSLIX) throw E.chip('EAS is only on ICODE SLIX tags.');
      if (tag.destroyed) throw E.destroyed();
      if (tag.loc101) throw E.privacy(); // in privacy mode the tag only answers GET RANDOM NUMBER and SET PASSWORD
      session.alertMessage = 'Sending the EAS alarm command.'; await session.delay(300);
      return tag.easOn;
    },
    async slixDestroy(session, tag, password) {
      if (tag.kind !== 'type5' || !tag.isSLIX) throw E.chip('Destroy is only on ICODE SLIX tags.');
      if (tag.destroyed) throw E.destroyed();
      if (tag.loc101) throw E.privacy(); // in privacy mode the tag only answers GET RANDOM NUMBER and SET PASSWORD
      if (password.length !== 4) throw E.input('The destroy password must be 4 bytes.');
      session.alertMessage = 'Authenticating.'; await session.delay(300);
      if (!NDEF.equal(password, tag.passwords.destroy)) throw E.auth();
      session.alertMessage = 'Destroying the tag.'; await session.delay(400);
      tag.destroyed = true;
    },
    async stPresentPassword(session, tag, number, password) {
      if (tag.kind !== 'type5' || !tag.isST) throw E.chip('ST passwords are only on ST25TV tags.');
      if (tag.destroyed) throw E.destroyed();
      if (password.length !== 8) throw E.input('The ST password must be 8 bytes.');
      session.alertMessage = 'Presenting the password.'; await session.delay(300);
      if (!NDEF.equal(password, tag.stPasswords[number] || U8(0, 0, 0, 0, 0, 0, 0, 0))) throw E.auth();
      tag.presented['st' + number] = true;
    },
    async stWritePassword(session, tag, number, password) {
      if (tag.kind !== 'type5' || !tag.isST) throw E.chip('ST passwords are only on ST25TV tags.');
      if (tag.destroyed) throw E.destroyed();
      if (password.length !== 8) throw E.input('The ST password must be 8 bytes.');
      if (!tag.presented['st' + number]) throw E.command('Present the current password before writing a new one.');
      session.alertMessage = 'Writing the password.'; await session.delay(300);
      tag.stPasswords[number] = new Uint8Array(password);
    },

    // FeliCa services: read and write 16 byte blocks without encryption, and check which services exist.
    async feliCaRead(session, tag, serviceCode, blocks) {
      if (tag.kind !== 'type3') throw E.chip('FeliCa commands need a FeliCa tag.');
      const svc = tag.services[serviceCode];
      if (!svc) throw E.command('Service 0x' + serviceCode.toString(16).toUpperCase().padStart(4, '0') + ' does not exist on this tag.');
      session.alertMessage = 'Reading blocks.'; await session.delay(300);
      return (blocks || []).map((b) => { if (b < 0 || b >= svc.blocks.length) throw E.command('Block ' + b + ' is out of range for this service.'); return svc.blocks[b]; });
    },
    async feliCaWrite(session, tag, serviceCode, block, data) {
      if (tag.kind !== 'type3') throw E.chip('FeliCa commands need a FeliCa tag.');
      const svc = tag.services[serviceCode];
      if (!svc) throw E.command('Service 0x' + serviceCode.toString(16).toUpperCase().padStart(4, '0') + ' does not exist on this tag.');
      if (!svc.writable) throw E.command('Service 0x' + serviceCode.toString(16).toUpperCase().padStart(4, '0') + ' is read only.');
      if (data.length !== 16) throw E.input('A FeliCa block is 16 bytes.');
      if (block < 0 || block >= svc.blocks.length) throw E.command('Block ' + block + ' is out of range for this service.');
      session.alertMessage = 'Writing the block.'; await session.delay(300);
      svc.blocks[block] = new Uint8Array(data);
    },
    async feliCaServices(session, tag, codes) {
      if (tag.kind !== 'type3') throw E.chip('FeliCa commands need a FeliCa tag.');
      session.alertMessage = 'Checking services.'; await session.delay(300);
      return (codes || []).map((c) => ({ code: c, exists: !!tag.services[c] }));
    },

    defaultTransport(tag) { return { type2: 'mifare', classic: 'mifare', type4: 'apdu', type5: 'iso15693', type3: 'feliCa' }[tag.kind] || 'mifare'; },
    async sendRaw(session, tag, commands) {
      if (!commands.length) throw E.input('Enter at least one command.');
      const out = [];
      for (let i = 0; i < commands.length; i++) {
        const c = commands[i];
        session.alertMessage = `Sending command ${i + 1} of ${commands.length}.`; await session.delay(180);
        const started = performance.now();
        try {
          let r;
          if (c.transport === 'mifare') {
            if (tag.kind === 'type4') r = { bytes: H(tag.native(c.bytes)) }; // DESFire takes native commands as raw frames too
            else if (tag.kind !== 'type2' && tag.kind !== 'classic') throw E.chip('MIFARE commands need an NTAG, Ultralight or DESFire tag.');
            else r = { bytes: H(tag.command(c.bytes)) };
          }
          else if (c.transport === 'apdu') { if (tag.kind !== 'type4') throw E.chip('APDUs need an ISO 14443-4 tag such as DESFire.'); if (c.bytes.length < 4) throw E.input('Enter a valid APDU: CLA INS P1 P2, then optional data and Le.'); const a = tag.apdu(c.bytes); r = { bytes: H(a.data), sw1: a.sw1, sw2: a.sw2 }; }
          else if (c.transport === 'iso15693') { if (tag.kind !== 'type5') throw E.chip('ISO 15693 commands need a Type 5 tag.'); if (c.bytes.length < 2) throw E.input('Enter the request flags byte and the command code.'); r = { bytes: H(tag.custom(c.bytes[0], c.bytes[1], c.bytes.slice(2))) }; }
          else { if (tag.kind !== 'type3') throw E.chip('FeliCa commands need a FeliCa tag.'); r = { bytes: H(tag.felica(c.bytes)) }; }
          r.elapsedMS = Math.max(1, Math.round(performance.now() - started + 4));
          out.push(r);
        } catch (e) {
          const m = NFCError.map(e);
          if (m.code === 'cancelled' || m.code === 'tagLost') throw m;
          throw E.command(`Command ${i + 1} failed: ${m.message}`);
        }
      }
      return out;
    },
  };
  // Config pages behind a password answer NAK 0x04; that means the tool needs the password, not that something broke.
  function readConfig(tag, page) {
    try { return tag.readPage(page); } catch (e) { if (e.code === 'nak' && /0x04/.test(e.message)) throw E.passwordNeeded(tag); throw e; }
  }
  // Why a Type 2 page write was refused, in words, so a NAK is never the whole story.
  function refusalReason(tag, page, e) {
    if (page <= 1 && !tag.spec.magicSerial) return 'Pages 0 and 1 hold the serial number, and only magic clone chips let them change. ';
    if (tag.lockedPage && tag.lockedPage(page)) return `Page ${page} is locked. `;
    if (tag.cfgLocked && (page === tag.cfg.cfg0 || page === tag.cfg.cfg1)) return 'The configuration of this tag is locked. ';
    if (e && e.message && /0x04/.test(e.message)) return 'It needs the password first. ';
    return '';
  }
  function refusedWrite(tag, page, e) {
    if (!e || e.code !== 'nak') return e;
    const why = refusalReason(tag, page, e);
    return why ? E.command(`${e.message} ${why.trim()}`) : e;
  }
  function authenticate(tag, password) {
    if (password.length !== 4) throw E.input('The password must be 4 bytes.');
    try { tag.command(U8(0x1B, ...password)); } catch (e) { if (e.code === 'nak') throw E.auth(); throw e; }
  }

  // Display helpers for TagInfo (same strings as TagInfo.swift)
  const info = {
    typeLine: (i) => i.chip.isoStandard + (i.chip.nfcForumType ? ` (NFC Forum Type ${i.chip.nfcForumType})` : ''),
    chipLine: (i) => { const m = (i.chip.manufacturer || '').trim(); return !m || m === 'Unknown' || i.chip.name.startsWith(m) ? i.chip.name : `${m} ${i.chip.name}`; },
    serialLine: (i) => (i.uid.match(/.{2}/g) || []).join(':'),
    memoryLine: (i) => (i.chip.totalPages ? `${i.chip.totalPages * i.chip.pageSize} bytes : ${i.chip.totalPages} pages (${i.chip.pageSize} bytes each)` : null),
    sizeLine: (i) => (i.ndefCapacity != null ? `${i.ndefUsedBytes || 0} / ${i.ndefCapacity} bytes (${i.ndefCapacity > 0 ? Math.round(((i.ndefUsedBytes || 0) / i.ndefCapacity) * 100) : 0}%)` : null),
    atqaLine: (i) => (i.chip.atqa != null ? '0x' + i.chip.atqa.toString(16).toUpperCase().padStart(4, '0') : null),
    sakLine: (i) => (i.chip.sak != null ? '0x' + i.chip.sak.toString(16).toUpperCase().padStart(2, '0') : null),
    writableLine: (i) => ({ readWrite: 'Yes', readOnly: 'No', notSupported: 'No' })[i.ndefStatus] || 'Unknown',
    statusLabel: (s) => ({ notSupported: 'Not supported', readWrite: 'Read and write', readOnly: 'Read only' })[s] || 'Unknown',
  };
  const dumpFlat = (d) => NDEF.concat(...d.pages.map((p) => (p.readable ? p.bytes : new Uint8Array(d.pageSize))));
  const dumpFromFlat = (bytes, pageSize) => { const pages = []; for (let i = 0; i < bytes.length; i += pageSize) { const chunk = new Uint8Array(pageSize); chunk.set(bytes.slice(i, i + pageSize)); pages.push({ index: i / pageSize, bytes: chunk, readable: true }); } return { pageSize, pages, chip: null, readAt: new Date().toISOString() }; };
  const serializeDump = (d) => (d ? { pageSize: d.pageSize, chip: d.chip, readAt: d.readAt, pages: d.pages.map((p) => ({ index: p.index, bytes: H(p.bytes), readable: p.readable })) } : null);
  const restoreDump = (d) => (d ? { pageSize: d.pageSize, chip: d.chip, readAt: d.readAt, pages: d.pages.map((p) => ({ index: p.index, bytes: FH(p.bytes) || new Uint8Array(), readable: p.readable })) } : null);
  const serializeInfo = (i) => Object.assign({}, i, { records: i.records.map(serializeRecord), dump: serializeDump(i.dump) });
  const restoreInfo = (i) => Object.assign({}, i, { records: (i.records || []).map(restoreRecord), dump: restoreDump(i.dump) });

  return { NFCError, E, CHIPS, list, get, save, reset, ops, info, dumpFlat, dumpFromFlat, serializeRecord, restoreRecord, serializeDump, restoreDump, serializeInfo, restoreInfo, isNTAG21x };
})();
