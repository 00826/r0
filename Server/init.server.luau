--- ### init.server.luau
---
--- one-time ordered require

workspace:SetAttribute("initserver", (function()
	local start = os.clock()
	for _, module in ipairs{
		script:WaitForChild("CollisionGroups");
		script:WaitForChild("r0server");
		script:WaitForChild("_closer");
	} do
		local s, e = pcall(require, module)
		if not s then warn(`initserver error [{module.Name}]: {e}`) end
	end
	return os.clock() - start
end)())