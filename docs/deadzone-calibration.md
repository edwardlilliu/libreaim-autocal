# Deadzone calibration

Open **Auto Calibrate → Controller Deadzones → Calibrate**. Choose the controller, let the right stick rest, then roll it around its full range. Review the profile and optionally compare it with the default on the aim test. **Save now** or **Save profile** makes it available in normal Play. Cancelling or discarding leaves the saved profile alone.

Normal training loads the saved curve automatically, including after restarting LibreAim. It applies only to controllers with the matching Godot GUID. Device numbers may change after reconnecting; the GUID match still works. GUIDs generally identify a controller model, so this is one saved profile rather than a library for individually identified controllers.

The curve compensates for the measured resting offset and scales stick movement between the inner and outer deadzones. If the saved data is missing, invalid, from an unsupported version, or for another controller, normal input behavior is retained. Custom look bindings also keep their existing behavior; this profile calibrates the default right-stick axes.

With multiple controllers connected, the strongest processed stick controls aim. Each controller uses its own applicable curve or the default deadzone; axes are not combined across controllers. Mouse aiming and movement are unchanged. Calibration's A/B trials use their temporary curves, while sensitivity trials retain their original deadzone.

## Tests

Run from the repository directory:

```powershell
.\tests\run-deadzone-tests.ps1 -Godot 'C:\path\to\Godot_console.exe'
.\tests\run-sensitivity-tests.ps1 -Godot 'C:\path\to\Godot_console.exe'
```

The deadzone runner uses disposable saves under `.godot`. It checks the actual calibration save path and player rotation, invalid profiles, controller matching and reconnects, multiple controllers, custom look bindings, cancellation, and temporary calibration curves. A second Godot process verifies that the saved profile loads and affects aiming after restart. Controller input is simulated, so a physical-controller check is still required.

For SCRUM-36, record the controller model, operating system and app version, then:

1. Calibrate and save. Open normal Play and confirm the resting stick does not drift and aiming responds to the new curve.
2. Restart the app and repeat the check.
3. Start another calibration and cancel or discard it. Confirm the previous profile is still used.
4. Disconnect and reconnect the controller. Confirm input stops while disconnected and works after reconnecting.
5. Try a different controller and confirm the original calibration is not incorrectly applied.
