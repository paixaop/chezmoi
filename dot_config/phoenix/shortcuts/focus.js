
/* IMPORT */

require ( './magic/terminal.js' );

/* LAUNCHERS */

const launchChrome = `
  tell application "Google Chrome"
    make new window
    activate
  end tell
`;

function launchDevTools () {

  const chrome = Space.active ().windows ().find ( window => /Google Chrome/.test ( window.app ().name () ) );

  if ( !chrome ) return alert ( 'Chrome is not opened' );

  osascript (`
    tell application "Google Chrome" to activate
    tell application "System Events" to tell process "Google Chrome"
      click menu item "Developer Tools" of menu 1 of menu item "Developer" of menu 1 of menu bar item "View" of menu bar 1
    end tell
  `);

}

const launchVSC = () => Task.run ( '/usr/local/bin/code', ['-n'] );

const launchHyper = () => Task.run ( '/usr/local/bin/hyper' );

const launchiTerm = `
  if application "iTerm" is running then
    tell application "iTerm"
      activate
      if not (exists current window) then
        create window with default profile
      end if
    end tell
  else
    tell application "iTerm"
      create window with default profile
    end tell
  end if
`;

const launchTerminal = `
  tell application "Terminal"
    do script ""
    activate
  end tell
`;

const launchFinder = `
  tell application "Finder"
    make new Finder window to (get new window target of Finder preferences)
    activate
  end tell
`;

/* CALLBACKS */

function callbackTerminal ( isNewWindow ) {

  if ( !isNewWindow ) return;

  setTimeout ( () => {

    const window = Window.focused ();

    if( !window || !isUserApp(window) ) return;

    //magicTerminalOpen ( window );

  }, 600 );

}

function callbackHyper ( isNewWindow ) {

  if ( !isNewWindow ) return;

  setTimeout ( () => {

    const window = Window.focused ();
    if( !window || !isUserApp(window) ) return;

    magicHyperOpen ( window );

  }, 1200 );

}

function callbackiTerm ( isNewWindow ) {

  if ( !isNewWindow ) return;

  setTimeout ( () => {

    const window = Window.focused ();

    if( !window || !isUserApp(window) ) return;

    //magiciTermOpen ( window );

  }, 600 );

}

/* FOCUS */

const focus = [
  ['c', HYPER_1, ['Google Chrome', false, /^(?!Developer Tools)/, /Picture in Picture/, launchChrome]],
  ['d', HYPER_1, ['Google Chrome', true, /(Developer Tools)|(chrome-devtools)/, /Picture in Picture/, launchDevTools]],
  ['v', HYPER_1, ['Code', false, false, false, launchVSC]],
  ['t', HYPER_1, ['Terminal', false, false, false, launchTerminal, callbackTerminal]],
  ['f', HYPER_1, ['Finder', false, false, false, launchFinder]],
  ['g', HYPER_1, ['Tower']]
];

setKeysHandler ( focusWindow, focus );
