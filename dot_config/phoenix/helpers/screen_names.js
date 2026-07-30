
function setScreenNames(monitors = MONITORS) {
    let screensWithNames = {};
    const screens = Screen.all();

    debugMonitors(monitors);

    for(const s in screens) {
        let id = screens[s].identifier();
        let r = screens[s].flippedFrame();

        let resolution = `${r.width}x${r.height}`;

        for(let m in monitors) {
            if (!Array.isArray(monitors[m])) {
                monitors[m] = Array.from(monitors[m]);
            }

            if( monitors[m].includes(resolution) )  {
                Phoenix.log(`Monitor ${m} associated with screen: ${id} at resolution ${resolution}`);
                screensWithNames[m] = screens[s];
                break;
            }
        } 
    }
    for(let m in monitors) {
        if( !screensWithNames[m]) {
            Phoenix.log(`WARNING: Monitor ${m} @ ${monitors[m]} not detected or has different resolution than specified in Phoenix configuration.`)
        }
    }
    return screensWithNames;
}

function debugMonitors(monitors = MONITORS) {
    for(let m in monitors) {
        Phoenix.log(`Monitor ${m}: ${monitors[m]}`);
    }
}

function getScreenFromName(name) {
    debugMonitors();

    const screensWithNames = setScreenNames();
    //Phoenix.log(`Monitor ${name} mapped to ${screensWithNames[name].identifier()} ${screenToString(screensWithNames[name])}`);
    return screensWithNames[name];
}

function isScreenName(screen, name) {
    const screensWithNames = setScreenNames();
    return screensWithNames[name].identifier() === screen.identifier();
}

function screenToString(screen) {
    const size = screen.flippedFrame();
    return `resolution: ${size.width}x${size.height} origin: (${size.x}, ${size.y})`;
}

function monitor(screen) {
    const screensWithNames = setScreenNames();
    for(const s in screensWithNames) {
        if( screensWithNames[s].identifier() === screen.identifier() ) {
            return s;
        }
    }
    return undefined;
}

function moveWindowToMonitor(window, monitor) {
    if( !window || !isUserApp(window) ) return false;

    if( !isUserApp(window) ) return;

    if ( !window.isNormal() || !window.isMain() ) return; 

    if ( !monitor ) return;
    if ( !(monitor in MONITORS) ) {
        Phoenix.log(`moveWindowToMonitor: Monitor ${monitor} does not exist in your configuration ${MONITORS}`);
        return;
    }

    const name = window.app().name();
    
    const targetScreen = getScreenFromName(monitor);
    const targetScreenFrame = targetScreen.flippedVisibleFrame();

    const currentScreen = window.screen();
    const currentScreenFrame = currentScreen.flippedVisibleFrame();

    if( currentScreen == targetScreen) {
        Phoenix.log(`moveWindowToMonitor: Window ${name} already displayed on monitor ${monitor}. Not moving window.`);
        return;
    }

    const windowTopLeft = window.topLeft();
    
    Phoenix.log(`moveWindowToMonitor: Window TopLeft - x:${windowTopLeft.x}, y:${windowTopLeft.y}`);
    Phoenix.log(`moveWindowToMonitor: Current Screen: x:${currentScreenFrame.x}, y:${currentScreenFrame.y}, w:${currentScreenFrame.width}, h:${currentScreenFrame.height}`);
        
    Phoenix.log(`moveWindowToMonitor: Target Screen - x:${targetScreenFrame.x}, y:${targetScreenFrame.y}, width:${targetScreenFrame.width}, height:${targetScreenFrame.height}`);
    
    const newX = targetScreenFrame.x + Math.abs(currentScreenFrame.x - windowTopLeft.x);
    const newY = targetScreenFrame.y + Math.abs(currentScreenFrame.y - windowTopLeft.y);
    Phoenix.log(`moveWindowToMonitor: Window ${name} move to ${monitor}: (${newX}, ${newY})`);
    window.setTopLeft({
        x: newX,
        y: newY
    });
}


