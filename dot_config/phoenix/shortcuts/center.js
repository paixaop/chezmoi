
/* CENTER */

setKeyHandler ( 'keypad5', HYPER_1, () => {

  const window = Window.focused ();
  if( !window || !isUserApp(window) ) return;

  if ( !window ) return;
  const screen = getWindowScreen(window);
  const sFrame = screen.flippedVisibleFrame();
  const frame = window.frame();
  window.setFrame ({
    x: frame.x,
    y: frame.y,
    width: Math.floor(sFrame.width / 2),
    height: sFrame.height
  });
  centerWindow ( window );

});

setKeyHandler ( 'keypad5', HYPER_2, () => {

  const window = Window.focused ();
  if( !window || !isUserApp(window) ) return;

  const frame = window.frame ();

  window.setFrame ({
    x: frame.x,
    y: frame.y,
    width: CENTER_WIDTH,
    height: CENTER_HEIGHT
  });

  centerWindow ( window );

});

setKeyHandler ( 'm', HYPER_2, () => {
  centerMouse();
});