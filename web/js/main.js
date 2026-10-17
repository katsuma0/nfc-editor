// Boot: four tabs, each with its own navigation stack, like the iOS TabView.
(() => {
  const tabs = [['read', 'Read', 'wave', SCREENS.read], ['write', 'Write', 'pencil', SCREENS.write], ['tools', 'Tools', 'wrench', SCREENS.tools], ['saved', 'Saved', 'folder', SCREENS.saved]];
  const tabsHost = document.getElementById('tabs');
  const bar = document.getElementById('tabbar');
  const panes = {}, buttons = {};
  let current = null;
  function select(id) {
    if (current === id) { const nav = SCREENS.app.navs[id]; if (nav) nav.popToRoot(); return; }
    current = id;
    for (const [k] of tabs) { panes[k].classList.toggle('active', k === id); buttons[k].classList.toggle('active', k === id); }
    // Tab roots show state other tabs change (scans, saved items, the write queue), so rebuild on every switch.
    const nav = SCREENS.app.navs[id]; if (nav) nav.refreshTop();
    try { localStorage.setItem('nfce.tab', id); } catch (e) { /* ignore */ }
  }
  SCREENS.app.select = select;
  for (const [id, label, icon, make] of tabs) {
    const pane = UI.el('div', { class: 'tab' });
    const navHost = UI.el('div', { class: 'nav' });
    pane.append(navHost);
    tabsHost.append(pane);
    panes[id] = pane;
    const nav = new UI.NavStack(navHost);
    SCREENS.app.navs[id] = nav;
    nav.push(make(), false);
    const b = UI.el('button', { type: 'button', 'aria-label': label, onClick: () => select(id) }, UI.icon(icon), UI.el('span', { text: label }));
    buttons[id] = b;
    bar.append(b);
  }
  let start = 'read';
  try { start = localStorage.getItem('nfce.tab') || 'read'; } catch (e) { /* ignore */ }
  select(panes[start] ? start : 'read');

  // Keep screen awake maps to the Screen Wake Lock API where the browser has it.
  let lock = null;
  UI.applyWakeLock = async (on) => {
    try { if (on && navigator.wakeLock) lock = await navigator.wakeLock.request('screen'); else if (!on && lock) { await lock.release(); lock = null; } } catch (e) { /* not available */ }
  };
  if (STORE.settings.keepScreenAwake) UI.applyWakeLock(true);
})();
