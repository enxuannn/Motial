# Remer Pedal (iPhone companion)

Lets a seated person steer **Lantern Glide** on Vision Pro with their ankle.

- Strap the iPhone to the top of the foot with a sports armband, and sit down.
- In the app: **Set resting position** (foot relaxed), then **Set full range** (toes pointed down, only as far as is comfortable).
- 0 % = resting, 100 % = your comfortable range. It works in any phone orientation, because it follows the tilt path between those two poses.
- The phone finds Remer on Vision Pro over the local network (Bonjour `_steadyshin._tcp`). The Vision Pro answers with the lantern count, shown under the dial.
- No sensor (Simulator)? A slider steers the boat instead.

**Run it:** open `SteadyShin.xcodeproj` and press Run on an iPhone or the iPhone simulator. Both devices need to be on the same Wi-Fi, and you need to allow "Local Network" when asked. On a real iPhone, pick your team under Signing & Capabilities first.

**On Vision Pro:** the plan shows **Lantern Glide (seated)** in the first two stages. When the exercise starts, Vision Pro begins listening for the phone. Until the phone connects, the boat glides at a calm demo pace.
