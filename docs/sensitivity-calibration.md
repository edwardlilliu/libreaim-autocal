# Sensitivity calibration: initial benchmark

Open **Auto Calibrate → Controller Sensitivity → Calibrate**. Connect a controller, then start calibration. Manual controller sensitivity can also be saved on this screen. **Use default (180°/s)** restores a starting speed that turns halfway around in one second at full right-stick deflection. Controller speed is independent of mouse sensitivity.

## Flow

1. Snapshot the current controller speed. Use 180°/s when there is no valid saved controller setting. Explicit saved speeds are preserved until the user saves a change.
2. Test the current speed, 80% of it, and 120% of it, in shuffled order. For a baseline below 90°/s, compare it with 144°/s and 216°/s instead, so an old slow setting does not trap the search. Clamp values to 1–720°/s and remove duplicates.
3. Before each measurement, run 3 unscored practice targets. Each measured round then requires 9 hits: 3 outer, 3 intermediate, 3 central targets. Reuse the existing aim-test scene, with a minimum target radius of 3.5% of its distance for this sensitivity flow. The same target sizes apply to every candidate and validation round; the original precision test is unchanged. The crosshair uses the same centered renderer as normal Play and deadzone verification.
4. Select a faster candidate only if it completes the equal-target benchmark at least 5% faster and its accuracy is no more than 2 percentage points lower than the baseline. Invalid/incomplete measurements cannot win. If no candidate qualifies, keep the baseline without further rounds.
5. Compare the selected candidate and baseline again, in shuffled order, using a fresh seed and another practice block before each measurement. Apply the same acceptance rule to these independent validation results.
6. Present the measured comparison. Only **Apply recommendation** saves a winning sensitivity and its evidence. **Keep current**, cancellation, timeout, or disconnect does not save trial settings.

Up to 60 targets are required: 3 search blocks and 2 validation blocks, each with 3 practice and 9 measured targets. The speed default, target sizes, 5% improvement threshold, 2-point accuracy tolerance, search interval and target count are prototype defaults in `sensitivity_benchmark.gd`, not scientifically established calibration parameters.

## Input, measurement, and interruption rules

- Only the selected controller supplies aim and shots during calibration. Mouse/keyboard aiming is ignored. These trials keep the existing look deadzone. [Deadzone calibration](deadzone-calibration.md) is a separate flow whose saved curve is used in normal Play.
- The shoot action uses the project's mapping (right shoulder by default). Esc or controller Back/Select pauses. Losing window focus also pauses.
- Each measured timer starts when Begin is pressed, including acquisition of the first target. Paused time is excluded. Hits, shots, accuracy, total elapsed time, and acquisition intervals are recorded.
- Every block has a 75-second limit. A timeout or selected-controller disconnect invalidates the current run. Restart through setup rather than resuming partial measurements after reconnection.
- Candidate settings exist only on the temporary player instance. Ordinary Play reads the saved independent `controls/controller_sensitivity` value.
- Applying stores `controls/sensitivity_profile` with the baseline, chosen speed, controller metadata, seed, version, timestamp, search measurements, and validation measurements. This is one active controller setting, not a device-specific profile library.

## Reuse and scope

`sensitivity_calibration.gd` coordinates the screens and rounds. `sensitivity_benchmark.gd` contains pure selection/validation rules. The existing `CalibrationTargetSpawner` accepts an optional seed; its default behavior remains random for the original aim test.

Seeds and identical stage parameters make trials comparable. Target placement still depends on current view and the spawner's visibility/recentering rules, so this does not guarantee identical world-space target sequences. Shuffled trial order and a separate validation seed reduce, but do not eliminate, practice/order effects. A short benchmark does not prove a universal best sensitivity. Physical-controller playtesting is required to tune the thresholds, target count, and search interval.

Related fixes: live mouse sensitivity changes now update immediately; the controller connection callback accepts both Godot signal arguments; shooting a non-target collider is counted as a miss, and the raycast is refreshed before shooting.

## Verification

On Windows, from the repository directory:

```powershell
.\tests\run-sensitivity-tests.ps1 -Godot 'C:\path\to\Godot_console.exe'
.\tests\run-controller-aim-tests.ps1 -Godot 'C:\path\to\Godot_console.exe'
```

The runners import the project and use disposable save directories under `.godot`, never the player's normal save data. The sensitivity suite covers candidate selection, incomplete/invalid measurements, full stage progression, temporary overrides, validation, saving/reloading, manual entry, pause, cancellation, disconnect, timeout, controller-only input, menu routing, and existing gameplay sensitivity updates. The aiming suite additionally checks shared speed defaults, crosshair alignment at different window sizes and real physics ray hits and misses against visible targets. These checks do not replace a physical-controller usability test.

Manual acceptance check:

1. Without a controller, Start is disabled and connection instructions are visible.
2. With a controller, complete practice and measurement blocks. Verify aiming speed differs between candidates, mouse input does not move the camera, and stage progress is readable.
3. Pause and resume; disconnect and restart; confirm no unwanted settings changes.
4. Reach either recommendation or no-improvement results. Apply if offered, restart the game, and confirm the selected speed persists in ordinary Play.
5. Run the original Controller Aim Test and normal training modes to check for regressions.

During baseline review, the existing humanoid glTF import produced a texture-index error, and the dummy renderer reported resource allocations at exit. These pre-existing diagnostics are separate from calibration assertions. Real-renderer preview of the new flow was also checked.
