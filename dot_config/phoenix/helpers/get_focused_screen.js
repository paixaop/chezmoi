
/* GET FOCUSED SCREEN */

function getFocusedScreen ( window = Window.focused () ) {

  if( !isUserApp(window) ) return null;  
  return getWindowScreen ( window );

}
