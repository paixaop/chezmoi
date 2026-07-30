
/* HYPER_1 */

setEventHandler ( 'windowDidOpen', magicHyperOpen );

/* HANDLER */

function magicHyperOpen ( window ) {

  if( !window || !isUserApp(window) ) return;
  if ( !window.isNormal () || !window.isMain () ) return;

  const name = window.app ().name ();

  if ( !/Hyper/.test ( name ) || false ) return;

  setFrame ( 'bottom-left', window );

}
