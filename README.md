# busk
Live basketball form coach: phone camera shot tracking with spoken feedback

Set your iPhone on a tripod at the court. Busk tracks your jump shot with Apple's on-device body pose
detection (Vision) and speaks feedback on your elbow, arc, release and follow-through. Nothing leaves the phone.

## Develop
- Xcode 26+, iOS 17+. The project is generated from `project.yml`: `brew install xcodegen && xcodegen generate`.
- Tests: `xcodebuild test -project Busk.xcodeproj -scheme Busk -destination "$(scripts/sim-destination.sh)"`.
- In the simulator and UI tests the camera is replaced by a demo shooter (`ShotSimulator`) cycling through common form faults.

## Ship to TestFlight
`scripts/testflight.sh` archives, cloud-signs and uploads to TestFlight (internal testing only) using an
App Store Connect API key in `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_P8`. CI (`.github/workflows/ci.yml`) builds and runs
the unit and UI tests on every PR.
