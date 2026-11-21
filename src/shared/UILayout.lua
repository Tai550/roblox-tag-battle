-- タッチ操作と安全領域の共通設定。
local UILayout = {
	EdgeMargin = 16,
	MinTouchSize = 52,
	BottomClearance = 120,
}

function UILayout.ApplySafeArea(gui)
	-- CoreUISafeInsets は端末の安全領域と Roblox の標準バーの両方を避ける。
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end)
end

return UILayout
