Mechanics (optional "mechanics" field of the object spec)

Players can ride, fly, wear and use objects. You describe the mechanic with data;
the game runs it with its own controllers, so you never write code. Pick the
type that fits and tune the numbers. Forward is -Z for every object: build
vehicles with the nose toward -Z and the rear toward +Z.

Give the moving parts an "id" (part field, a short name). Several parts with
the same id move together. Then animate them:
"animations": [ {
  "part": "id of the parts",
  "motion": "spin" | "swing" | "bob" | "angle",
  "axis": "x" | "y" | "z",        // local axis; wheels rolling forward spin around x
  "amount": number,               // spin: degrees per second at full input; swing/angle: degrees; bob: meters
  "rate": number,                 // swing/bob: cycles per second (default 1)
  "by": "always" | "speed" | "throttle" | "steer" | "climb" | "active",
  "pivot": [x, y, z]              // optional rotation center, default the first part's position
} ]
by: speed is the vehicle speed from -1 to 1 (wheels: amount = max_speed / radius in degrees,
e.g. 10 m/s on a 0.35 m wheel is about 1600), throttle 0..1 (propellers, rotors),
steer -1..1 (handlebars, front wheels, rudder: use "angle"), climb -1..1 (elevator
flaps), active is 1 while someone drives the vehicle or after a player toggles the
prop with E (doors, levers, lamps), always runs forever (windmill, carousel).
Two animations on the same part combine: list the spin first, then the steer.
Animated parts of props stop blocking players while they move.

1. Vehicle: the player walks up, presses E to get in and E to get out.
"mechanics": {
  "type": "vehicle",
  "movement": "ground" | "air" | "hover",
  "seat": [x, y, z],          // where the driver's hips are, in object coordinates
  "max_speed": m/s,           // ground 10, air 40, hover 12 by default
  "acceleration": m/s²,       // default 6 / 8 / 10
  "brake": m/s²,
  "turn_speed": degrees/s,    // default 90 / 50 / 100
  "reverse_speed": m/s,       // ground and hover
  "lean": degrees,            // ground: lean into turns (bicycle 20, motorbike 30, car 0); air: max bank (45)
  "tilt": degrees,            // hover: nose tilt when moving
  "jump": m/s,                // ground: Space jumps (bike hop 5, monster truck 8)
  "gravity_scale": 0..5,      // ground and air 1, hover 0
  "takeoff_speed": m/s,       // air: speed where lift beats gravity (default 18)
  "pitch_speed": degrees/s,   // air
  "climb_speed": m/s,         // hover: Space up, Shift down (default 6)
  "controls_hint": "short controls text in the player's language",
  "animations": [...]
}
ground: cars, bicycles, carts, horses, skateboards. W/S throttle and brake, A/D steer.
air: planes, gliders, dragons. W/S throttle, A/D bank, Space nose up, Shift nose down;
it takes off after a run-up faster than takeoff_speed and stalls when too slow.
hover: helicopters, brooms, flying carpets, balloons, drones, UFOs. W/S forward and back,
A/D turn, Space up, Shift down. A vehicle uses a box around all its parts for collision.

2. Equipment: the player presses E to put it on and E again to drop it.
Model it around the attach point (origin) at its real size.
"mechanics": {
  "type": "equipment",
  "attach": "back" | "head" | "hand" | "feet" | "body",
  "offset": [x, y, z],
  "abilities": {
    "speed": 0.2..5,         // run speed multiplier
    "jump": 0.2..5,          // jump height multiplier
    "extra_jumps": 0..5,     // jumps in mid-air
    "glide": 0..10,          // max fall speed in m/s while Space is held (wings, umbrella)
    "fly": 0..40,            // free flight speed in m/s: Space up, Shift down (jetpack, cape)
    "gravity": 0..3          // personal gravity multiplier
  },
  "controls_hint": "...",
  "animations": [...]
}

3. Prop: an interactive object without a driver.
"mechanics": {
  "type": "prop",
  "on_touch": { "bounce": m/s up (trampoline 15), "push": [x, y, z] m/s in object coordinates (speed pad, catapult) },
  "interact": "toggle",      // E toggles animations with "by": "active" (door, lever, gate)
  "animations": [...]
}
Use physics mode "static" for props that players stand on.

Examples (parts shortened):
Bicycle: {"name": "Велосипед", "parts": [
  {"shape": "torus", "id": "wheel_back", "radius": 0.35, "inner_radius": 0.3, "position": [0, 0.35, 0.55], "rotation": [0, 0, 90], "color": "beam"},
  {"shape": "torus", "id": "wheel_front", "radius": 0.35, "inner_radius": 0.3, "position": [0, 0.35, -0.55], "rotation": [0, 0, 90], "color": "beam"},
  {"shape": "box", "size": [0.06, 0.06, 1.1], "position": [0, 0.6, 0], "color": "wood"},
  {"shape": "box", "id": "handlebar", "size": [0.6, 0.05, 0.05], "position": [0, 1.0, -0.5], "color": "beam"}],
 "mechanics": {"type": "vehicle", "movement": "ground", "seat": [0, 0.95, 0.15], "max_speed": 9, "turn_speed": 110, "lean": 20, "jump": 4,
  "animations": [
   {"part": "wheel_back", "motion": "spin", "axis": "x", "amount": -1500, "by": "speed"},
   {"part": "wheel_front", "motion": "spin", "axis": "x", "amount": -1500, "by": "speed"},
   {"part": "wheel_front", "motion": "angle", "axis": "y", "amount": 25, "by": "steer"},
   {"part": "handlebar", "motion": "angle", "axis": "y", "amount": 25, "by": "steer"}]}}
A torus lies flat in XZ, so rotate wheels 90 degrees around z to stand them up;
spin them around x with a negative amount so they roll forward (toward -Z).
Plane: "mechanics": {"type": "vehicle", "movement": "air", "seat": [0, 1.2, 0.5], "max_speed": 45, "takeoff_speed": 20,
  "animations": [{"part": "propeller", "motion": "spin", "axis": "z", "amount": 2000, "by": "throttle"}]}
Jetpack: "mechanics": {"type": "equipment", "attach": "back", "abilities": {"fly": 10}}
Trampoline: "physics": {"mode": "static"}, "mechanics": {"type": "prop", "on_touch": {"bounce": 16}}
Door: "mechanics": {"type": "prop", "interact": "toggle",
  "animations": [{"part": "door", "motion": "angle", "axis": "y", "amount": 100, "by": "active", "pivot": [-0.5, 1, 0]}]}

World physics: set_world_physics changes gravity, player speed, jump and time
scale for everyone in the world (e.g. gravity 0.16 for the moon).
