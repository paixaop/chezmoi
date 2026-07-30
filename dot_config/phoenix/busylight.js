// Define the command to run the busylight process
const BUSYLIGHT_COMMAND = "busylight";
const BUSYLIGHT_ARGS = ["blink", "red"];

// Define a variable to track the running task
let busylightTask = null;

// Define a key combination to toggle the busylight process
Key.on("keypad0", [HYPER_1], busylight);
    
function busylight() {
  if (busylightTask) {
    // If the task is already running, terminate it
    busylightTask.terminate();
    busylightTask = null;
    Phoenix.notify("OFF");
  } else {
    // Start the busylight command
    busylightTask = Task.run(BUSYLIGHT_COMMAND, BUSYLIGHT_ARGS, (handler) => {
      if (handler.exitCode !== 0) {
        Phoenix.notify("Error starting busylight");
        busylightTask = null; // Reset the task variable in case of error
      }
    });

    if (busylightTask) {
      Phoenix.notify("ON");
    }
  }
}
