// What every view of the sky shares: the active rig (for the frame drawn on
// the dome and in "In your frame") and the camera's roll, so turning it in Sky
// View turns it in a target's card too. App keeps `rig` in step with settings.
export const view = $state({ rig: null, roll: 0 });
