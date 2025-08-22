# r0

## about

|ico.svg|lore|
|-|-|
|<img src="./r0-ico.svg" width="96"/>|zero-limb humanoidless player controller<br><br>i do not like the black-boxiness of the roblox humanoid<br>i do not like the unnecessary complexities of the roblox playermodule<br><br>demo game: https://www.roblox.com/games/138517315713347/|

## gotchas

1. an empty fork of the playermodule is required for any project using r0

this is because r0 uses a minimal rewrite/functionality of the roblox `PlayerModule` (and therefore has conflicts with it)

```json
"StarterPlayer": {
	"$className": "StarterPlayer",
	"StarterPlayerScripts": {
		"$className": "StarterPlayerScripts",
		"PlayerModule": { "$className": "ModuleScript" },
		"PlayerScriptsLoader": { "$className": "LocalScript" }
	}
}
```

2. r0 must be required on the server and client

this is because r0 has a self-contained replication process where each r0 instance is represented as a 12-wide buffer

3. i do not know how to write comprehensive or proper documentation for a project of this nature

because of this some annotations are on the more verbose side hopefully for better clarity. also for some variables used in the playermodule rewrite i have tried to include their original variable name so it's easier to trace where something came from

## init files

[Client/r0client.luau](Client/r0client.luau) contains example client code for using r0 and doubles as a test case \
[Server/r0server.luau](Client/r0server.luau) requires r0 for the replication process

## actual files

[r0/init.luau](r0/init.luau) contains r0 mutator and step functions and runs the client/server replication process when required by the client/server \
`r0.Input` is the input table read from by the `r0` mutator functions and is meant to be written to externally \
`r0.Output` is the output table written to during `r0.step(...)` and is meant to be read from externally

## the rewritten playermodule

[r0/CameraController.luau](r0/CameraController.luau) \
[r0/InputController.luau](r0/InputController.luau) \
[r0/Limiter.luau](r0/Limiter.luau) \
[r0/Spring.luau](r0/Spring.luau) \
[r0/TransformExtrapolator.luau](r0/TransformExtrapolator.luau) \
...are parts of a minimal rewrite of roblox's `PlayerModule`

[r0/CameraController.luau](r0/CameraController.luau) controls the camera based on inputs read from [r0/InputController.luau](r0/InputController.luau) \
[r0/Limiter.luau](r0/Limiter.luau) is the equivalent of the playermodule poppercam and limits the zoom spring wrt its raycast blacklistparams \
[r0/Spring.luau](r0/Spring.luau) is a de-ooped spring module found in the playermodule camerautils \
[r0/TransformExtrapolator.luau](r0/TransformExtrapolator.luau) is a de-ooped cframe extrapolator found in the playermodule poppercam

---

⌜ r0 by 00826 / overflowed