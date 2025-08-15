--!strict

--- ### collisiongroups.luau
---
--- sets collision groups

local PhysicsService = game:GetService("PhysicsService")

PhysicsService:RegisterCollisionGroup("Entities")

PhysicsService:CollisionGroupSetCollidable("Entities", "Entities", false)

return true