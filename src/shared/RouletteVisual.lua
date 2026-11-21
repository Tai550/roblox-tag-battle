-- 角度は針の真上を 0°、画面上の時計回りを正とする。
local RouletteVisual = {}

function RouletteVisual.SectorAngle(prizeIndex, prizeCount)
	return (prizeIndex - 1) * 360 / prizeCount
end

function RouletteVisual.StopAngle(prizeIndex, prizeCount)
	return -RouletteVisual.SectorAngle(prizeIndex, prizeCount) % 360
end

function RouletteVisual.TargetRotation(currentAngle, prizeIndex, prizeCount)
	local remaining = (RouletteVisual.StopAngle(prizeIndex, prizeCount) - currentAngle) % 360
	return currentAngle + 4 * 360 + remaining
end

function RouletteVisual.SpinAngle(startAngle, targetAngle, progress)
	local eased = 1 - (1 - math.clamp(progress, 0, 1)) ^ 3
	return startAngle + (targetAngle - startAngle) * eased
end

return RouletteVisual
