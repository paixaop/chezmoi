
/* Thunderbird */

setEventHandler ('windowDidOpen', magicThunderbirdOpen);

/* HELPERS */

function magicThunderbirdOpen ( window ) {
  if( !window || !isUserApp(window) ) return;

  const appName = window.app().name();
  const windowTitle = window.title();

  if ( !window.isNormal() ) return;
  Phoenix.log(`Window open event: ${appName}, Title: ${windowTitle}`);

  if ( !/Thunderbird/.test(appName) ) return;
  if ( !/Write/.test(windowTitle) ) return;
  Phoenix.log(`Center Thunderbird writing window`);

  for(const w of window.app().windows()) {
    if( !w || !isUserApp(w) ) return false;
    Phoenix.log(`Thunderbird ${w.title}`);
    if ( !/Write/.test(w.title()) ) {
      const sFrame = w.screen().flippedVisibleFrame();
      const wFrame = window.frame();
      window.setFrame ({
        x: sFrame.x + ( sFrame.width / 2 ) - ( wFrame.width / 2 ),
        y: sFrame.y + ( sFrame.height / 2 ) - ( wFrame.height / 2 ),
        width: wFrame.width,
        height: wFrame.height
      });
      return;
    }
  }

  centerWindow(window);
  
}
