// Move the cursor to origo
function centerMouse(window = Window.focused()) {
    if( !window || !isUserApp(window) ) return;

    const frame = window.frame();
    Mouse.move({ x: frame.x + frame.width/2, y: frame.y + frame.height/2 });
}
