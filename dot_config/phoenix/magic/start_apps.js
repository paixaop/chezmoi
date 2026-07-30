// Start all work applications
setKeyHandler('s', HYPER_1, () => {
    App.launch('Google Chrome');
    App.launch('Terminal');
    App.launch('Telegram');
    App.launch('Messages');
    App.launch('Microsoft Teams');
    App.launch('Code');
    App.launch('Thunderbird');
    activate_layout('twoMonitors');
});
