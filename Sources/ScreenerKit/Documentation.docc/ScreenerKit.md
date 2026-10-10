# ``ScreenerKit``

Record your app's UI states and named events so an agent can inspect what happened.

## Overview

A menu can disappear before an agent takes a screenshot. Screener records sampled
keyframes and semantic markers into a local `.vtrace` bundle. The separate
`screener-mcp` executable lets your agent inspect that bundle after a reproduction.

Use this SDK in Debug builds of an iOS 16+ or macOS 13+ app, with Swift 6.1 or later.
It records keyframes, not video: sampling can miss transitions, and hierarchy
rendering does not guarantee compositor-exact glass or intermediate animation states.

Start with <doc:RecordingAReproduction>, then follow <doc:InspectingWithAnAgent>.
The guided <doc:Tutorials> walks through creating and closing your first trace.

## Topics

### Getting started

- <doc:Tutorials>
- <doc:RecordingAReproduction>
- <doc:ChoosingACaptureBackend>
- <doc:InspectingWithAnAgent>

### Recording

- ``Screener``
- ``ScreenerCaptureSession``
- ``ScreenerCaptureSource``
- ``CapturedImage``

### Failure handling

- ``ScreenerError``
- ``ScreenerCaptureError``

## See Also

- [Source and examples](https://github.com/SoundBlaster/Screener)
- [macOS API reference](https://soundblaster.github.io/Screener/macos/documentation/screenerkit/)
