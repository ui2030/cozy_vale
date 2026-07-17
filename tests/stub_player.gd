extends Node
# 테스트용 최소 플레이어 스텁 (정산 gold 수령 확인).
var gold := 0
func add_gold(n: int) -> void:
	gold += n
