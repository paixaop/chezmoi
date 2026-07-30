
/* FULLSCREEN */

setKeyHandler ( 'space', HYPER_1, () => {

  const window = Window.focused ();

  if( !window || !isUserApp(window) ) return;

  window.setFullScreen ( !window.isFullScreen () );

});

