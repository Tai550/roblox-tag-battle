-- 各層は足元から上へ。/ で区切った行は正面（-Z）から背面へ並べる。
local BeastModels = {}

local colors = {
	t = Color3.fromRGB(20, 135, 128),
	c = Color3.fromRGB(65, 195, 168),
	u = Color3.fromRGB(37, 96, 176),
	p = Color3.fromRGB(49, 27, 79),
	v = Color3.fromRGB(95, 56, 132),
	g = Color3.fromRGB(244, 186, 61),
	w = Color3.fromRGB(241, 235, 218),
	k = Color3.fromRGB(26, 24, 34),
	s = Color3.fromRGB(58, 118, 64),
	l = Color3.fromRGB(131, 172, 77),
	b = Color3.fromRGB(108, 62, 42),
	r = Color3.fromRGB(159, 45, 36),
	o = Color3.fromRGB(191, 124, 50),
}

local layers = {
	Bastet = {
		"...../.p.p./.p.p./.....",
		"...../.p.p./.ppp./...p.",
		"...../.ppp./.ppp./...v.",
		"...../.ppp./.pvp./...v.",
		"...../.ggg./.ppp./.....",
		"..v../.ppp./.ppp./.....",
		"...../.gpg./.ppp./.....",
		"...../.p.p./.v.v./.....",
		"...../.v.v./...../.....",
	},
	Thoth = {
		".k.k./...../...../.....",
		".k.k./...../...../.....",
		".w.w./.www./...../.....",
		"...../.www./.wkw./.....",
		"...../wwwww/.kkk./..k..",
		"..k../.www./..w../.....",
		"..k../.kwk./..w../.....",
		"...../.www./..w../.....",
	},
	Sobek = {
		"...../.s.s./.s.s./...../.....",
		"...../.s.s./.sss./..s../..l..",
		"...../.lll./.sss./..l../.....",
		"...../sssss/.sls./...../.....",
		"...../.lsl./.sss./...../.....",
		".wlw./.sss./.sss./...../.....",
		".sls./.sls./.ksk./...../.....",
		"...../...../.sss./...../.....",
	},
	Sekhmet = {
		"...../.o.o./.o.o./.....",
		"...../.o.o./.ooo./...r.",
		"...../.ooo./.oro./...o.",
		"...../.ggg./.rrr./.....",
		"...../.oro./rrrrr/.....",
		".ooo./roror/rrrrr/.....",
		"...../rgogr/rrrrr/.....",
		"...../.o.o./.rrr./.....",
		"...../...../..g../.....",
	},
	Horus = {
		"...../..g.g../..b.b../.....",
		"...../..b.b../..bbb../.....",
		"...../.bbbbb./..bbb../...b...",
		"...../bbbbbbb/..wbw../...b...",
		"...../b.bwb.b/..wbw../.....",
		"...../...g.../..bbb../.....",
		"...g.../..www../..wbw../.....",
		"...../..kwk../..www../.....",
		"...../..www../..bbb../.....",
	},
	Anubis = {
		"...../.k.k./.k.k./.....",
		"...../.k.k./.kkk./.....",
		"...../.ggg./.kgk./.....",
		"...../.kkk./kkkkk/.....",
		"...../.ggg./.kgk./.....",
		".kkk./.kkk./.gkg./.....",
		"..k../.gkg./.kkk./.....",
		"...../.k.k./.k.k./.....",
		"...../.g.g./...../.....",
		"...../.k.k./...../.....",
	},
	Khepri = {
		"......./.t...t./.t...t./.t...t./.......",
		"......./ctttttc/ctttttc/ctttttc/.......",
		"..ktk../.ttctt./.ttctt./..tct../.......",
		".c.t.c./..tct../..tct../...t.../.......",
		"..c.c../...g.../...c.../......./.......",
	},
	Hathor = {
		"......./.b...b./.b...b./.......",
		"......./.w...w./.w...w./.....b.",
		"......./.wwbww./.bwwwb./.....b.",
		"..bbb../.wwwww./.wwbww./.......",
		"..wbw../.bwbbb./.bwwwb./.......",
		"..kwk../.gwwwg./......./.......",
		"......./g.....g/......./.......",
		"......./g.....g/......./.......",
	},
	Isis = {
		"........./...u.u.../...uuu.../.........",
		"........./...uuu.../...ugu.../.........",
		"........./...uuu.../..uuuuu../.........",
		"........./...ggg.../.uuguguu./.........",
		"........./...uuu.../uuguuuguu/.........",
		"........./...owo.../ug..u..gu/.........",
		"........./...uwu.../g...u...g/.........",
		"........./...gug.../........./.........",
		"........./....g..../........./.........",
	},
	Osiris = {
		"...../.w.w./.www./.....",
		"...../.www./.www./.....",
		"...../.wsw./.www./.....",
		"...../.wsw./.www./.....",
		"...../.sws./.www./.....",
		"..g../.sss./.www./.....",
		"...../.ksk./.sss./.....",
		"...../.wsw./.www./.....",
		"...../.w.w./..w../.....",
		"...../...w./...../.....",
	},
	Set = {
		"...../.b.b./.b.b./...../.....",
		"...../.b.b./.rrr./..b../.....",
		"...../.rrr./.rbr./..b../..r..",
		"...../.rrr./.rrr./...../.....",
		"...../.bgb./.rrr./...../.....",
		".bbb./.rrr./.rrr./...../.....",
		".krk./.brb./.krk./...../.....",
		"...../...../.rrr./...../.....",
		"...../...../.b.b./...../.....",
		"...../...../.r.r./...../.....",
		"...../...../.b.b./...../.....",
	},
	Ra = {
		"......./..g.g../..r.r../.......",
		"......./..r.r../..rrr../.......",
		"......./.rrgrr./..rgr../.......",
		"......./rrggrrr/..grg../.......",
		"...g.../g.rgr.g/..rrr../.......",
		"...g.../..gkg../..ggg../.......",
		"......./..grg../..ggg../.......",
		"......./...g.../......./.......",
		"......./..ggg../......./.......",
		"......./.ggrgg./......./.......",
		"......./..ggg../......./.......",
	},
}

-- origin は足元の中心。モデルの正面は origin の前方。
function BeastModels.Build(id, origin, blockSize)
	local shape = layers[id]
	if not shape then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = id
	local size = Vector3.new(blockSize, blockSize, blockSize)
	for y, layer in ipairs(shape) do
		local rows = string.split(layer, "/")
		for z, row in ipairs(rows) do
			for x = 1, #row do
				local color = colors[string.sub(row, x, x)]
				if color then
					local block = Instance.new("Part")
					block.Size = size
					block.CFrame = origin * CFrame.new(
						(x - (#row + 1) / 2) * blockSize,
						(y - 0.5) * blockSize,
						(z - (#rows + 1) / 2) * blockSize
					)
					block.Color = color
					block.Anchored = true
					block.CanCollide = false
					block.CanTouch = false
					block.CanQuery = false
					block.Parent = model
				end
			end
		end
	end
	return model
end

return BeastModels
