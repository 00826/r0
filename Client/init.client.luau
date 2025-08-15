--- ### init.client.luau
---
--- one-time ordered require

workspace:SetAttribute("initclient", (function()
	local start = os.clock()
	for _, module in ipairs{
		script:WaitForChild("r0client");
		script:WaitForChild("_closer");
	} do
		local s, e = pcall(require, module)
		if not s then warn(`initclient error [{module.Name}]: {e}`) end
	end
	return os.clock() - start
end)())