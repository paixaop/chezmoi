
/* INFO */

setKeyHandler ( 'o', HYPER_2, () => {

  const window = Window.focused();
  if( !window || !isUserApp(window) ) return;

  const app = window.app().name();
  const title = window.title();
  const main = window.isMain() ? 'Yes' : 'No';
  const visible = window.isVisible() ? 'Yes' : 'No';
  const screen = window.screen();
  const m = monitor(screen);
  const size = window.frame();
 
  const info = `App: ${app}\nTitle: ${title}\n\nMain: ${main}\nVisible: ${visible}\nMonitor: ${m}\nSize: ${JSON.stringify(size)}`;
  alert ( info);
});
