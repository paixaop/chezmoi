
function activate_layout(layout, apps = APPS) {
    if( !apps ) {
        Phoenix.log(`Please configure APPS in the config/app.js file`);    
        return;
    }

    // Iterate all apps and check if layout is configured for the app
    for (let a in apps) {

        // Check if there are any layouts defined for this app
        if (apps[a].layouts) {

            // get the current layout
            if( apps[a].layouts[layout] ) {
                const [monitor, namedFrame] = apps[a].layouts[layout];

                if( !monitor || !namedFrame ) {
                    Phoenix.log(`ERROR: Incorrect layout definition for app ${a}, please set screen and named-position`)
                    return;
                }
                // Get App window
                const app = App.get(a);
                if ( !app ) {
                    Phoenix.log(`Layout: App ${a} not running.`);
                    continue;
                }
                Phoenix.log(`Layout: App ${a} moved to monitor ${monitor} at ${namedFrame}`);
                const windows = app.windows();
                for(const window of windows) {
                    
                    if( !window || !isUserApp(window) ) continue;
                    window.unminimize();
                    Phoenix.log(`App: ${a} window: ${window.title()}`);
                    const screen = getScreenFromName(monitor).flippedVisibleFrame();
                    const [x, y, width, height] = getNamedFrame(namedFrame);
                    
                    window.setFrame({
                        x: screen.x + ( screen.width * x ),
                        y: screen.y + ( screen.height * y ),
                        width: screen.width * width,
                        height: screen.height * height
                    });
                    
                }
            }
        }
    }        
}


function setLayout(layouts, apps = APPS) {
    if( !apps ) {
        Phoenix.log(`Please configure APPS in the config/app.js file`);    
        return;
    }
    
    for(const l in layouts) {
        const [key, modifier, layout] = layouts[l];
        Phoenix.log(`Layout:  ${layout} key: ${keyToString(key, modifier)}`);

        Key.on(key, modifier, () => {
            activate_layout(layout, apps);
        });            
    }
}
