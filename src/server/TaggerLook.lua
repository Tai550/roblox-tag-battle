-- TaggerLook: 鬼の見た目（少し赤い色と、頭上の薄い Highlight）
-- 速度やタッチ判定には関わらない。鬼の交代に合わせて Apply / Clear を呼ぶ。
-- 鬼でなくなったら、付けたときと同じ Part の色を元に戻し、Highlight を消す。

local GameState = require(script.Parent:WaitForChild("GameState"))

local TaggerLook = {}

local HIGHLIGHT_NAME = "TaggerHighlight"

-- 元の色へこの割合だけ赤を混ぜる（0 だと元のまま、1 だと真っ赤）
TaggerLook.TintAlpha = 0.45
TaggerLook.TintTarget = Color3.fromRGB(255, 90, 90)
TaggerLook.HighlightName = HIGHLIGHT_NAME
TaggerLook.FillTransparency = 0.65

-- 色を混ぜた結果を返す（計算だけ。テストからも呼べる）
-- alpha は TintTarget へ寄せる割合。省略時は TintAlpha。
function TaggerLook.MixColor(original, toward, alpha)
	local goal = toward or TaggerLook.TintTarget
	local t = alpha
	if t == nil then
		t = TaggerLook.TintAlpha
	end
	return Color3.new(
		original.R + (goal.R - original.R) * t,
		original.G + (goal.G - original.G) * t,
		original.B + (goal.B - original.B) * t
	)
end

-- [player] = { character, colors = { [part] = 元の色 }, highlight, descendantConn }
local applied = {}

local function copyColor(color)
	return Color3.new(color.R, color.G, color.B)
end

local function disconnectDescendants(state)
	local conn = state and state.descendantConn
	if conn then
		state.descendantConn = nil
		conn:Disconnect()
	end
end

local function tintPart(state, part)
	if not part or not part.IsA or not part:IsA("BasePart") or not part.Color then
		return
	end
	if state.colors[part] then
		return -- すでに混ぜてある Part をもう一度混ぜない
	end
	state.colors[part] = copyColor(part.Color)
	part.Color = TaggerLook.MixColor(part.Color)
end

local function addHighlight(character)
	local existing = character:FindFirstChild(HIGHLIGHT_NAME)
	if existing then
		existing:Destroy()
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = HIGHLIGHT_NAME
	highlight.Adornee = character
	highlight.FillColor = Color3.fromRGB(255, 96, 96)
	highlight.OutlineColor = Color3.fromRGB(186, 52, 52)
	highlight.FillTransparency = TaggerLook.FillTransparency
	highlight.OutlineTransparency = 0.2
	highlight.Parent = character
	return highlight
end

-- そのプレイヤーに付いている鬼の見た目を外し、色を元に戻す
function TaggerLook.Clear(player)
	local state = applied[player]
	if not state then
		return
	end
	applied[player] = nil
	disconnectDescendants(state)
	for part, color in pairs(state.colors) do
		if part and part.Parent then
			part.Color = color
		end
	end
	if state.highlight and state.highlight.Parent then
		state.highlight:Destroy()
	end
end

-- 今のキャラクターに色と Highlight を付ける。同じキャラクターへ二度目は何もしない
function TaggerLook.Apply(player)
	local character = player and player.Character
	if not character then
		return
	end
	local state = applied[player]
	if state and state.character == character then
		return
	end
	-- リスポーンで体が変わったときは、古い体の色は戻さず記録だけ捨てる
	-- （古いキャラクターはすでに消えている）
	if state then
		disconnectDescendants(state)
		if state.highlight then
			state.highlight:Destroy()
		end
		applied[player] = nil
	end

	state = {
		character = character,
		colors = {},
		highlight = nil,
		descendantConn = nil,
	}
	applied[player] = state

	for _, desc in ipairs(character:GetDescendants()) do
		tintPart(state, desc)
	end
	state.highlight = addHighlight(character)

	-- あとから付いたアクセサリなども、同じ割合で一度だけ混ぜる
	local added = character.DescendantAdded
	if added and added.Connect then
		state.descendantConn = added:Connect(function(desc)
			if applied[player] == state and player.Character == character then
				tintPart(state, desc)
			end
		end)
	end
end

function TaggerLook.ClearAll()
	for player in pairs(applied) do
		TaggerLook.Clear(player)
	end
end

-- 鬼のままキャラクターが作り直されたとき。鬼でなければ見た目を残さない。
function TaggerLook.OnCharacterAdded(player)
	if not player then
		return
	end
	if not GameState.IsTagger(player) then
		TaggerLook.Clear(player)
		return
	end
	local state = applied[player]
	if state and state.character == player.Character then
		return
	end
	if state then
		disconnectDescendants(state)
		if state.highlight then
			state.highlight:Destroy()
		end
		applied[player] = nil
	end
	TaggerLook.Apply(player)
end

return TaggerLook
