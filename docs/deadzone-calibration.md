# Deadzone calibration


It applies only to controllers with the matching Godot GUID. Device numbers may change after reconnecting; the GUID match still works. GUIDs generally identify a controller model, so this is one saved profile rather than a library for individually identified controllers. If the saved data is missing, invalid, from an older version, or for another controller, normal input behavior is retained. Custom look or move bindings also keep their existing behavior; the profile calibrates the default stick axes.

With multiple controllers connected, the strongest processed stick wins. Each controller uses its own applicable curve or the default deadzone; axes are not combined across controllers. Mouse aiming is unchanged.

## Tests

Run from the repository directory:

```powershell
.\tests\run-deadzone-tests.ps1 -Godot 'C:\path\to\Godot_console.exe'
.\tests\run-sensitivity-tests.ps1 -Godot 'C:\path\to\Godot_console.exe'
.\tests\run-controller-aim-tests.ps1 -Godot 'C:\path\to\Godot_console.exe'
```

The deadzone runner uses disposable saves under `.godot`. `deadzone_gameplay_test.gd` checks the curves, the save path and player rotation and movement, invalid and old profiles, controller matching and reconnects, multiple controllers, custom bindings, cancellation and temporary profiles; a second Godot process verifies the saved profile loads and affects aiming after restart. `deadzone_flow_test.gd` plays the whole calibration with `simulated_controller.gd`, a worn controller whose sticks settle in a different spot after every release, and checks that 500 later releases never produce drift, both sticks reach full tilt, triggers read 0 at rest and 1 at full pull, on/off triggers are recognised, and a release with a thumb left on the stick is asked again.

Controller input is simulated, so a physical-controller check is still required. Record the controller model, operating system and app version, then:

1. Calibrate and save. Open normal Play, let go of the sticks after aiming in several directions, and confirm the view never creeps.
2. Run the sensitivity calibration and confirm aim doesn't creep there either.
3. Restart the app and repeat the check.
4. Start another calibration and cancel it. Confirm the previous profile is still used.
5. Disconnect and reconnect the controller. Confirm input stops while disconnected and works after reconnecting.
6. Try a different controller and confirm the original calibration is not incorrectly applied.
