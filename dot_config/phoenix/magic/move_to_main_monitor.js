setEventHandler ( 'windowDidOpen', moveWindowToMainScreen );
//setEventHandler ( 'appDidLaunch', moveAppToMainScreen );

/* HELPERS */
function moveWindowToMainScreen ( window ) {
  if( !window || !isUserApp(window) ) return;
  moveWindowToMonitor(window, MAIN_MONITOR);
}

/*
function moveAppToMainScreen ( app ) {
  if ( !app ) return;

  const name = app.name();
  Phoenix.log(`moveAppToMainScreen: Window ${name} move to ${MAIN_MONITOR}.`)
  moveWindowToMonitor(app.mainWindow(), MAIN_MONITOR);
}
*/