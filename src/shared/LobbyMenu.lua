-- ロビーのメニュー項目を表示順に定義する。
local LobbyMenu = {}

local items = {
	{ Id = "Status", Label = "ステータス" },
	{ Id = "Deck", Label = "デッキ", AdminOnly = false },
	{ Id = "Shop", Label = "アイテム購入", AdminOnly = false },
	{ Id = "Store", Label = "ショップ", AdminOnly = false },
	{ Id = "Room", Label = "友達部屋", AdminOnly = false },
	{ Id = "Roulette", Label = "ルーレット", AdminOnly = false },
	{ Id = "Beasts", Label = "召喚獣ガチャ", AdminOnly = false },
	{ Id = "Trade", Label = "召喚獣交換", AdminOnly = false, Color = "Secondary" },
	{ Id = "Solo", Label = "ひとりで遊ぶ", AdminOnly = false, Color = "Accent" },
	{ Id = "Admin", Label = "管理", AdminOnly = true },
}

for _, item in ipairs(items) do
	table.freeze(item)
end

function LobbyMenu.VisibleItems(isAdmin)
	local visible = {}
	for _, item in ipairs(items) do
		if not item.AdminOnly or isAdmin == true then
			table.insert(visible, item)
		end
	end
	return visible
end

return LobbyMenu
