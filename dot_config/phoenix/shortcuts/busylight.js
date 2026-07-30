// Define the command to run the busylight process
const BUSYLIGHT_COMMAND_ON = "/Users/pedro/Downloads/kill-busylight.sh on";
const BUSYLIGHT_COMMAND_OFF = "/Users/pedro/Downloads/kill-busylight.sh off";

// Define a variable to track whether the process is on or off
let isBusylightOn = false;

// Define a key combination to toggle the busylight process
Key.on("keypad0", HYPER_1, () => {
    if (isBusylightOn) {
        busylight(false); // Turn off
    } else {
        busylight(true); // Turn on
    }
});

function busylight(status) {
    if (status === false) {
        // Stop the busylight command
        Task.run("/bin/bash", ["-c", BUSYLIGHT_COMMAND_OFF], (task) => {
            if (task.error && task.error.length > 0) {
                Phoenix.notify("Error stopping busylight.");
                Phoenix.log(`Error stopping busylight: ${task.error}`);
            } else {
                const lightStatus = task.output ? task.output.trim() : "OFF";
                Phoenix.log(`Busylight has been turned ${lightStatus}`);
                Phoenix.notify("Busylight OFF");
                isBusylightOn = false;
            }
        });
        return;
    }

    // Start the busylight command
    Task.run("/bin/bash", ["-c", BUSYLIGHT_COMMAND_ON], (task) => {
        if (task.error && task.error.length > 0) {
            Phoenix.notify("Error starting busylight.");
            Phoenix.log(`Error starting busylight: ${task.error}`);
        } else {
            const lightStatus = task.output ? task.output.trim() : "ON";
            Phoenix.log(`Busylight has been turned ${lightStatus}`);
            Phoenix.notify("Busylight ON");
            isBusylightOn = true;
        }
    });
}