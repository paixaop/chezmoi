
/* INFO */

setKeyHandler ( 'i', HYPER_1, () => {

  const windows = Space.active ().windows ();

  windows.forEach ( window => {
    //Phoenix.log("Window info called");
    if( !window || !isUserApp(window) ) return;
    if ( !window.isVisible () || !window.title () ) return;
    
    modalWindow ( {}, window );

  });

});

setKeyHandler ( 'i', HYPER_2, () => {

  shell ( 'pmset -g batt | grep -Eo "\\d+%" | cut -d% -f1', ( id, output ) => {

    shell ( 'music-current-name', ( id, songName ) => {

      shell ( 'music-current-status', ( id, songLiked, songDisliked ) => {

        const battery = output.trim ();

        const monthsNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
        const daysNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
        const pad = x => `00${x}`.slice ( -2 );

        const date = new Date ();
        const hours = pad ( date.getHours () );
        const minutes = pad ( date.getMinutes () );
        const seconds = pad ( date.getSeconds () );
        const wday = daysNames[date.getDay ()];
        const day = date.getDate ();
        const month = monthsNames[date.getMonth ()];
        const year = date.getFullYear ();

        const infoStatus = `Bat: ${battery}% - ${wday} ${day} ${month} ${year} - ${hours}:${minutes}:${seconds}`;
        const infoMusic = songName ? `\n•\n${songDisliked ? '♡' : '♥'} - ${_.truncate ( songName.trim (), { length: 40 } )}` : '';
        const info = `${infoStatus}${infoMusic}`;

        const screens = Screen.all();
        let scr = '\n\nScreens:\n';
        for(const s in screens) {
          const frame = screens[s].flippedVisibleFrame();
          scr += `${frame.width}x${frame.height} : ${frame.x}, ${frame.y}\n`;
        }

        alert ( info + scr);

      });

    });

  });

});
